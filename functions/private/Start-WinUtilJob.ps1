function Start-WinUtilJob {
    <#
        .SYNOPSIS
            Executa uma operação longa fora da thread da interface, com progresso, barra de tarefas, log e
            tratamento de erros compartilhados aplicados ao redor dela

        .DESCRIPTION
            Um job por vez. É dono da sinalização de ocupado, da barra de progresso, do item da barra de
            tarefas, do banner do console e das linhas de log durante toda a vida do job. O corpo faz o
            trabalho e chama Step-WinUtilJob; ele não deve imprimir banner nem definir a sinalização de
            ocupado por conta própria. Um corpo que lança exceção é capturado e a interface é
            restaurada em um finally, para que uma falha não deixe a interface presa como ocupada.

        .PARAMETER Name
            Componente de log e texto de progresso, por exemplo Install.

        .PARAMETER ScriptBlock
            O trabalho. Recebe Parameters como parâmetros nomeados.

        .PARAMETER Parameters
            Valores passados ao corpo por nome.

        .PARAMETER Description
            Texto de progresso exibido enquanto o job inicia. Por padrão, é o nome do job.

        .PARAMETER DisableAppList
            Acinza a lista de aplicativos durante a execução, para jobs que alteram o que está instalado.

        .PARAMETER QueueIfBusy
            Espera em $sync.JobQueue pela sua vez em vez de ser recusado, para ações iniciadas pelo
            usuário. Os parâmetros são mantidos como estavam quando foi enfileirado. Um job com o mesmo
            nome e parâmetros do último job enfileirado é ignorado, para que cliques consecutivos não repitam
            o trabalho.

        .PARAMETER FromQueue
            Interno de Start-WinUtilNextQueuedJob: este é o job enfileirado assumindo sua vez, então ele
            pode tomar o slot enquanto $sync.JobHandoff o reserva para a fila.

        .EXAMPLE
            Start-WinUtilJob -Name "Install" -Parameters @{ Packages = $packages } -ScriptBlock {
                param($Packages)
                Step-WinUtilJob -Status "Instalando" -Percent 10
            }
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,

        [hashtable]$Parameters = @{},

        [string]$Description,

        [switch]$DisableAppList,

        [switch]$QueueIfBusy,

        [switch]$FromQueue
    )

    if ($sync.ShuttingDown -or $sync.FinishInConsole) {
        if ($FromQueue) { Reset-WinUtilJobHandoff }
        Write-WinUtilLog -Level "WARN" -Component $Name -Message "Recusado iniciar $Name, o WinUtil está fechando."
        return $null
    }

    # Um job aninhado roda inline: o externo já é dono do slot e do relatório, então reivindicar
    # novamente o recusaria e ignoraria seu trabalho. Instalações de recursos chegam duas vezes, de feature.json
    # e de Invoke-WPFFeatureInstall.
    if ($global:WinUtilIsJobWorker) {
        & $ScriptBlock @Parameters
        return $null
    }

    # Com bloqueio: um chamador sem interface ou agendado não é serializado pelo dispatcher, onde
    # testar-e-atribuir permite que dois jobs sejam donos do slot. O token identifica a execução, para que um worker
    # ainda em desconstrução não possa liberar um slot que o próximo job detém.
    $jobToken = [guid]::NewGuid().ToString()
    $blockedBy = $null
    $queuePosition = 0
    $duplicate = $false

    # Construído fora do bloqueio. Um valor que não pode ser serializado apenas deixa o job sem deduplicação.
    $signature = $null
    if ($QueueIfBusy) {
        try {
            $sortedKeys = [string[]]$Parameters.Keys
            [array]::Sort($sortedKeys)
            $ordered = [ordered]@{}
            foreach ($key in $sortedKeys) { $ordered[$key] = $Parameters[$key] }
            $signature = "$Name|" + (ConvertTo-Json -InputObject $ordered -Compress -Depth 5 -WarningAction SilentlyContinue)
        } catch {
            Write-WinUtilLog -Level "WARN" -Component $Name -Message "Não foi possível comparar $Name com a fila, então ele não será verificado quanto a duplicatas: $($_.Exception.Message)"
        }
    }

    [System.Threading.Monitor]::Enter($sync.SyncRoot)
    try {
        # O fechamento pode vencer enquanto a assinatura é construída ou este chamador espera pelo bloqueio.
        if ($sync.ShuttingDown -or $sync.FinishInConsole) {
            if ($FromQueue) { $sync.JobHandoff = $false }
            Write-WinUtilLog -Level "WARN" -Component $Name -Message "Recusado iniciar $Name, o WinUtil está fechando."
            return $null
        }
        if ($FromQueue) {
            $sync.JobHandoff = $false
        }
        # O slot de um job concluído fica prometido à fila até que seu primeiro item tenha iniciado
        if ($sync.ActiveJob -or $sync.JobHandoff) {
            $blockedBy = if ($sync.ActiveJob) { $sync.ActiveJob } else { "Operações na fila" }
            # No mesmo bloqueio do teste de ocupado: um job que terminasse entre os dois deixaria
            # este enfileirado atrás de nada
            if ($QueueIfBusy -and $signature -and $sync.JobQueue.Count -gt 0) {
                # Uma ação interveniente pode mudar o estado novamente; agrupe apenas cliques adjacentes.
                $duplicate = $sync.JobQueue[$sync.JobQueue.Count - 1].Signature -eq $signature
            }
            if ($QueueIfBusy -and -not $duplicate) {
                $sync.JobQueue.Add([pscustomobject]@{
                    Id = [guid]::NewGuid().ToString()
                    Signature = $signature
                    Name = $Name
                    Description = $Description
                    ScriptBlock = $ScriptBlock.ToString()
                    Parameters = $Parameters
                    DisableAppList = [bool]$DisableAppList
                })
                $queuePosition = $sync.JobQueue.Count
            }
        } else {
            $sync.ActiveJob = $Name
            $sync.ActiveJobToken = $jobToken
            $sync.LastJobResult = $null
        }
    } finally {
        [System.Threading.Monitor]::Exit($sync.SyncRoot)
    }

    if ($duplicate) {
        Write-WinUtilLog -Component $Name -Message "$Name já está na fila, ignorado."
        return $null
    }

    if ($queuePosition -gt 0) {
        Write-WinUtilLog -Component $Name -Message "$Name enfileirado atrás de $blockedBy, posição $queuePosition."
        Invoke-WPFUIThread -Async -ScriptBlock { Update-WinUtilJobQueueUI }
        return $null
    }

    if ($blockedBy) {
        Show-WinUtilMessage -Message "$blockedBy ainda está em execução. Aguarde-o terminar antes de iniciar outra ação." -Title "WinUtil" -Button "OK" -Icon "Warning" | Out-Null
        return $null
    }

    $label = if ($Description) { $Description } else { $Name }
    try {
        $timingStartIndex = if ($sync.StepTimings) { $sync.StepTimings.Count } else { 0 }

        Write-WinUtilLog -Component $Name -Message "Job $Name iniciado."
        Invoke-WPFUIThread -Async -ScriptBlock { Update-WinUtilJobQueueUI }
        Write-WinUtilJobBanner -Message $label
        Step-WinUtilJob -Status "$label..." -Percent 0 -State "Normal" -Overlay "logo"

        # Abas com uma visualização de trabalho (girador + status ao vivo) trocam para ela enquanto seus
        # jobs rodam. Adicionar uma nova significa um novo painel XAML mais uma entrada aqui.
        $jobWorkingArea = switch ($Name) {
            "Install"     { "Install" }
            "Uninstall"   { "Install" }
            "Upgrade all Applications" { "Install" }
            "Tweaks"      { "Tweaks" }
            "Undo tweaks" { "Tweaks" }
            default       { $null }
        }

        if ($jobWorkingArea) {
            Set-WinUtilWorkingView -Area $jobWorkingArea -Working $true -Label "$label..."
        }

        if ($DisableAppList -and (Test-WinUtilUIAlive)) {
            Invoke-WPFUIThread -ScriptBlock {
                if ($null -ne $sync.ItemsControl) { $sync.ItemsControl.IsEnabled = $false }
            }
        }

        # Reconstruído a partir de seu texto dentro do runspace: um scriptblock carrega o estado de sessão em que foi
        # definido, e recriá-lo lá o vincula ao worker. O handle é descartado,
        # imprimi-lo coloca uma tabela IAsyncResult no console a cada clique de botão.
        $null = Invoke-WPFRunspace -ParameterList @(
            ("JobName", $Name),
            ("JobLabel", $label),
            ("JobBody", $ScriptBlock.ToString()),
            ("JobParameters", $Parameters),
            ("JobRestoresAppList", [bool]$DisableAppList),
            ("JobWorkingArea", $jobWorkingArea),
            ("JobToken", $jobToken),
            ("TimingStartIndex", $timingStartIndex)
        ) -ScriptBlock {
        param($JobName, $JobLabel, $JobBody, $JobParameters, $JobRestoresAppList, $JobWorkingArea, $JobToken, $TimingStartIndex)

        # Marca este runspace como o que faz o trabalho, para que uma pausa prenda aqui e não em
        # quem quer que o tenha pedido
        $global:WinUtilIsJobWorker = $true
        $global:WinUtilJobErrorCount = 0
        $global:WinUtilJobWarningCount = 0

        $jobClock = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            $body = [scriptblock]::Create($JobBody)

            # Os buffers de aviso, erro e saída de Write-Host de um worker ficam em um objeto PowerShell
            # que ninguém lê. Mesclá-lo ao fluxo de saída é o que o leva ao log.
            & $body @JobParameters 2>&1 3>&1 6>&1 | ForEach-Object {
                if ($_ -is [System.Management.Automation.WarningRecord]) {
                    $global:WinUtilJobWarningCount++
                }
                Write-WinUtilStreamRecord -Record $_ -Component $JobName
            }

            $jobClock.Stop()

            # Uma etapa pode falhar sem lançar exceção, por exemplo uma escrita no registro recusada por política.
            # O contador pertence a este runspace do worker, então erros alheios da interface não podem alterar
            # o resultado deste job enquanto ele está em execução.
            $newErrors = $global:WinUtilJobErrorCount
            $newWarnings = $global:WinUtilJobWarningCount
            if ($newErrors -gt 0) {
                Write-WinUtilLog -Level "WARN" -Component $JobName -Message "Job $JobName concluído em $($jobClock.ElapsedMilliseconds) ms com $newErrors erro(s)."
                Write-WinUtilJobBanner -Message "$JobLabel concluído com $newErrors erro(s), veja o log" -Level "ERROR"
                Step-WinUtilJob -Status "$JobName concluído com $newErrors erro(s)" -Percent 100 -State "Paused" -Overlay "warning"
            } elseif ($newWarnings -gt 0) {
                Write-WinUtilLog -Level "WARN" -Component $JobName -Message "Job $JobName concluído em $($jobClock.ElapsedMilliseconds) ms com $newWarnings aviso(s)."
                Write-WinUtilJobBanner -Message "$JobLabel concluído com $newWarnings aviso(s), veja o log"
                Step-WinUtilJob -Status "$JobName concluído com $newWarnings aviso(s)" -Percent 100 -State "Paused" -Overlay "warning"
            } else {
                Write-WinUtilLog -Component $JobName -Message "Job $JobName concluído em $($jobClock.ElapsedMilliseconds) ms."
                Write-WinUtilJobBanner -Message "$JobLabel concluído"
                Step-WinUtilJob -Status "$JobName concluído" -Percent 100 -State "None" -Overlay "checkmark"
            }
        } catch {
            $jobClock.Stop()
            # Uma folha que registra em log antes de relançar marca aquela exceção exata. Preserve o contexto
            # e a pilha externos sem contá-la duas vezes; erros anteriores alheios não contam.
            $errorAlreadyReported = $_.Exception.Data["WinUtilErrorReported"] -eq $true
            Write-WinUtilErrorRecord -ErrorRecord $_ -Component $JobName -Context "$JobName falhou após $($jobClock.ElapsedMilliseconds) ms" -DetailOnly:$errorAlreadyReported
            Write-WinUtilJobBanner -Message "$JobLabel falhou: $($_.Exception.Message)" -Level "ERROR"
            Step-WinUtilJob -Status "$JobName falhou" -Percent 100 -State "Error" -Overlay "warning"
        } finally {
            $jobResult = [pscustomobject]@{
                Token = $JobToken
                Errors = $global:WinUtilJobErrorCount
                Warnings = $global:WinUtilJobWarningCount
            }

            # Os runspaces do pool são reutilizados, então deixar isto definido faria a próxima parte de
            # trabalho em segundo plano neste runspace acreditar que é um worker de job
            $global:WinUtilIsJobWorker = $false
            $global:WinUtilJobErrorCount = 0
            $global:WinUtilJobWarningCount = 0

            Write-WinUtilTimingSummary -Scope $JobName -TotalMilliseconds $jobClock.ElapsedMilliseconds -StartIndex $TimingStartIndex

            # Um worker interrompido pelo watchdog pode chegar aqui depois que o próximo job tomou o slot,
            # e tudo abaixo libera o estado compartilhado.
            $stillOwns = $false
            [System.Threading.Monitor]::Enter($sync.SyncRoot)
            try {
                $stillOwns = $sync.ActiveJobToken -eq $JobToken
                if ($stillOwns) {
                    $sync.LastJobResult = $jobResult
                }
            } finally {
                [System.Threading.Monitor]::Exit($sync.SyncRoot)
            }

            if ($stillOwns) {
                # Cada restauração é tentada por conta própria: uma falha no dispatcher
                # ao reabilitar a lista de aplicativos não pode pular a ocultação da visualização
                # de trabalho, que de outro modo continuaria cobrindo a aba.
                try {
                    try {
                        if ($JobRestoresAppList -and (Test-WinUtilUIAlive)) {
                            Invoke-WPFUIThread -ScriptBlock {
                                if ($null -ne $sync.ItemsControl) { $sync.ItemsControl.IsEnabled = $true }
                            }
                        }
                    } catch {
                        Write-WinUtilLog -Level "WARN" -Component $JobName -Message "Não foi possível restaurar a lista de aplicativos após a conclusão de $($JobName): $($_.Exception.Message)"
                    }
                    try {
                        if ($JobWorkingArea) {
                            Set-WinUtilWorkingView -Area $JobWorkingArea -Working $false
                        }
                    } catch {
                        Write-WinUtilLog -Level "WARN" -Component $JobName -Message "Não foi possível ocultar a visualização de trabalho após a conclusão de $($JobName): $($_.Exception.Message)"
                    }
                } finally {
                    # O desligamento do dispatcher pode competir com a verificação de atividade e abortar a chamada de restauração.
                    # O worker terminou de qualquer forma, então seu slot sempre deve ser liberado.
                    $null = Clear-WinUtilActiveJob -Token $JobToken
                }
            } else {
                Write-WinUtilLog -Level "WARN" -Component $JobName -Message "$JobName foi desenrolado depois que outro job havia iniciado; seu estado foi deixado como estava."
            }
        }
        }
    } catch {
        $scheduleError = $_
        try {
            Write-WinUtilErrorRecord -ErrorRecord $scheduleError -Component $Name -Context "Não foi possível agendar $Name"
            $sync.LastJobResult = [pscustomobject]@{ Token = $jobToken; Errors = 1; Warnings = 0 }
            Write-WinUtilJobBanner -Message "$label não pôde ser iniciado" -Level "ERROR"
            Step-WinUtilJob -Status "$Name não pôde ser iniciado" -Percent 100 -State "Error" -Overlay "warning"
        } catch {
            Write-WinUtilLog -Level "WARN" -Component $Name -Message "Não foi possível relatar que $Name falhou ao iniciar: $($_.Exception.Message)"
        } finally {
            try {
                try {
                    if ($DisableAppList -and (Test-WinUtilUIAlive)) {
                        Invoke-WPFUIThread -ScriptBlock {
                            if ($null -ne $sync.ItemsControl) { $sync.ItemsControl.IsEnabled = $true }
                        }
                    }
                } catch {
                    Write-WinUtilLog -Level "WARN" -Component $Name -Message "Não foi possível restaurar a lista de aplicativos após a falha de $Name ao iniciar: $($_.Exception.Message)"
                }
                try {
                    if ($jobWorkingArea) {
                        Set-WinUtilWorkingView -Area $jobWorkingArea -Working $false
                    }
                } catch {
                    Write-WinUtilLog -Level "WARN" -Component $Name -Message "Não foi possível ocultar a visualização de trabalho após a falha de $Name ao iniciar: $($_.Exception.Message)"
                }
            } finally {
                $null = Clear-WinUtilActiveJob -Token $jobToken
            }
        }
    }
}

function Clear-WinUtilActiveJob {
    <#
        .SYNOPSIS
            Libera o slot do job ativo, limpando seu nome e seu token juntos

        .DESCRIPTION
            Um token deixado definido ainda corresponde a uma execução posterior e bloqueia novos trabalhos.

        .PARAMETER Token
            Libera somente se esta execução ainda for dona do slot. Omita para liberar incondicionalmente.
    #>
    param([string]$Token)

    $released = $false
    [System.Threading.Monitor]::Enter($sync.SyncRoot)
    try {
        if (-not $Token -or $sync.ActiveJobToken -eq $Token) {
            $sync.ActiveJobToken = $null
            $sync.ActiveJob = $null
            $released = $true
            # Entre aqui e a distribuição postada, o slot está livre, e uma nova ação não deve
            # tomá-lo à frente da fila
            if ($Token -and $sync.JobQueue.Count -gt 0 -and -not $sync.ShuttingDown -and -not $sync.FinishInConsole) {
                $sync.JobHandoff = $true
            }
        }
    } finally {
        [System.Threading.Monitor]::Exit($sync.SyncRoot)
    }

    # Um job que terminou, de qualquer forma, passa o slot para o próximo da fila. Uma liberação sem
    # token é uma redefinição forçada, que não deve iniciar nada.
    if ($released -and $Token) {
        try {
            Invoke-WPFUIThread -Async -ScriptBlock { Start-WinUtilNextQueuedJob }
        } catch {
            Reset-WinUtilJobHandoff
            Write-WinUtilLog -Level "WARN" -Component "UI" -Message "Não foi possível iniciar o próximo job enfileirado: $($_.Exception.Message)"
        }
    }
    return $released
}
