function Invoke-WinUtilAutoRun {
    <#

    .SYNOPSIS
        Executa cada ação selecionada até o fim sem janela

    .DESCRIPTION
        O caminho sem interface. Cada ação é o mesmo trabalho que o botão iniciaria, executado
        uma por vez porque a camada de jobs permite apenas um por vez, e aguardado até que o
        worker limpe o sinalizador de ocupado.

        Retorna um resumo do que foi executado para que quem chamou possa decidir o código de
        saída. Nada aqui toca a interface, então o comportamento é o mesmo com ou sem janela.

    .PARAMETER StopTimeoutSeconds
        Quanto tempo uma etapa que estourou o tempo recebe para parar antes de a execução
        desistir do restante.

    .PARAMETER StepTimeoutSeconds
        Quanto tempo uma única ação pode levar antes de a execução desistir dela. Sem um teto,
        um instalador esperando por algo que nunca vai chegar trava a execução de vez.

    #>
    param(
        [int]$StepTimeoutSeconds = 3600,

        [int]$StopTimeoutSeconds = 30
    )

    $steps = @(
        [pscustomobject]@{ Name = "Ajustes";          Count = @($sync.selectedTweaks).Count;   Action = { Invoke-WPFtweaksbutton } }
        [pscustomobject]@{ Name = "Interruptores";         Count = @($sync.selectedToggles).Count;  Action = { Invoke-WPFToggleSelections } }
        [pscustomobject]@{ Name = "Recursos";        Count = @($sync.selectedFeatures).Count; Action = { Invoke-WPFFeatureInstall } }
        [pscustomobject]@{ Name = "Aplicativos";    Count = @($sync.selectedApps).Count;     Action = { Invoke-WPFInstall } }
        [pscustomobject]@{ Name = "Remoção de AppX";    Count = @($sync.selectedAppx).Count;     Action = { Invoke-WPFAppxRemoval } }
    )

    $planned = @($steps | Where-Object { $_.Count -gt 0 })
    if ($planned.Count -eq 0) {
        Write-WinUtilLog -Level "WARN" -Component "AutoRun" -Message "Nada foi selecionado, então não há nada a fazer."
        return [pscustomobject]@{ Steps = @(); Failed = 0; TimedOut = 0; Errors = 0; Warnings = 0 }
    }

    Write-WinUtilLog -Component "AutoRun" -Message "Iniciando execução sem interface: $(($planned | ForEach-Object { "$($_.Name) ($($_.Count))" }) -join ', ')"

    $results = New-Object System.Collections.ArrayList
    $runClock = [System.Diagnostics.Stopwatch]::StartNew()

    foreach ($step in $planned) {
        $errorsBefore = if ($sync.LoggedErrors) { $sync.LoggedErrors.Count } else { 0 }
        $sync.LastJobResult = $null
        $stepClock = [System.Diagnostics.Stopwatch]::StartNew()
        $timedOut = $false

        Write-WinUtilLog -Component "AutoRun" -Message "$($step.Name): iniciando $($step.Count) item(ns)."

        try {
            & $step.Action
        } catch {
            Write-WinUtilErrorRecord -ErrorRecord $_ -Component "AutoRun" -Context "Iniciando $($step.Name)"
        }

        # A ação inicia um job e retorna; a execução termina quando o worker limpa o sinalizador
        while ($sync.ActiveJob) {
            if ($stepClock.Elapsed.TotalSeconds -ge $StepTimeoutSeconds) {
                $timedOut = $true
                Write-WinUtilLog -Level "ERROR" -Component "AutoRun" -Message "$($step.Name) não terminou em $StepTimeoutSeconds segundos, seguindo adiante."
                break
            }
            Start-Sleep -Milliseconds 200
        }

        $stepClock.Stop()
        $newErrors = if ($sync.LoggedErrors) { $sync.LoggedErrors.Count - $errorsBefore } else { 0 }
        $newWarnings = if ($null -ne $sync.LastJobResult) { [int]$sync.LastJobResult.Warnings } else { 0 }

        $null = $results.Add([pscustomobject]@{
            Name = $step.Name
            Items = $step.Count
            Seconds = [int]$stepClock.Elapsed.TotalSeconds
            Errors = $newErrors
            Warnings = $newWarnings
            TimedOut = $timedOut
        })

        $outcome = if ($timedOut) { "tempo esgotado" } elseif ($newErrors -gt 0) { "concluído com $newErrors erro(s)" } elseif ($newWarnings -gt 0) { "concluído com $newWarnings aviso(s)" } else { "concluído" }
        Write-WinUtilLog -Component "AutoRun" -Message "$($step.Name): $outcome após $([int]$stepClock.Elapsed.TotalSeconds)s."

        if ($timedOut) {
            # O worker ainda está no pool. Limpar a vaga por conta própria permitiria que a próxima
            # etapa começasse ao lado dele, fazendo com que duas execuções alterassem a máquina ao mesmo tempo.
            Stop-WinUtilActiveWork -NoWait | Out-Null

            $stopDeadline = (Get-Date).AddSeconds($StopTimeoutSeconds)
            while ((Test-WinUtilActiveWorkRunning) -and (Get-Date) -lt $stopDeadline) {
                Start-Sleep -Milliseconds 200
            }

            # Um job que nunca limpou o sinalizador faria com que todas as etapas seguintes se recusassem a iniciar
            $null = Clear-WinUtilActiveJob

            if (Test-WinUtilActiveWorkRunning) {
                Write-WinUtilLog -Level "ERROR" -Component "AutoRun" -Message "$($step.Name) não pôde ser interrompido, então as etapas restantes foram abandonadas em vez de executadas ao lado dele."
                break
            }
        }
    }

    $runClock.Stop()
    Write-WinUtilTimingSummary -Scope "AutoRun" -TotalMilliseconds $runClock.ElapsedMilliseconds

    return [pscustomobject]@{
        Steps = @($results)
        Failed = @($results | Where-Object { $_.Errors -gt 0 }).Count
        TimedOut = @($results | Where-Object { $_.TimedOut }).Count
        Errors = (@($results | Measure-Object -Property Errors -Sum).Sum)
        Warnings = (@($results | Measure-Object -Property Warnings -Sum).Sum)
    }
}

function Write-WinUtilAutoRunSummary {
    <#
        .SYNOPSIS
            Mostra o que uma execução sem interface fez e retorna o código de saída com que deve terminar
    #>
    param(
        [Parameter(Mandatory)]
        $Summary
    )

    Write-Host ""
    Write-Host "=== Execução sem interface do WinUtil ===" -ForegroundColor Cyan

    foreach ($step in @($Summary.Steps)) {
        $state = if ($step.TimedOut) { "TEMPO ESGOTADO" } elseif ($step.Errors -gt 0) { "$($step.Errors) erro(s)" } elseif ($step.Warnings -gt 0) { "$($step.Warnings) aviso(s)" } else { "ok" }
        $colour = if ($step.TimedOut -or $step.Errors -gt 0 -or $step.Warnings -gt 0) { "Yellow" } else { "Green" }
        Write-Host ("  {0,-14} {1,3} item(ns)  {2,5}s  {3}" -f $step.Name, $step.Items, $step.Seconds, $state) -ForegroundColor $colour
    }

    if (@($Summary.Steps).Count -eq 0) {
        Write-Host "  nada foi selecionado" -ForegroundColor Yellow
        Write-Host ""
        return 2
    }

    if ($Summary.TimedOut -gt 0 -or $Summary.Failed -gt 0) {
        Write-Host ""
        Write-Host "Concluído com problemas. Veja $($sync.logPath)" -ForegroundColor Yellow
        Write-Host ""
        return 1
    }

    if ($Summary.Warnings -gt 0) {
        Write-Host ""
        Write-Host "Concluído com avisos. Veja $($sync.logPath)" -ForegroundColor Yellow
        Write-Host ""
        return 0
    }

    Write-Host ""
    Write-Host "Todas as etapas foram concluídas. Log: $($sync.logPath)" -ForegroundColor Green
    Write-Host ""
    return 0
}
