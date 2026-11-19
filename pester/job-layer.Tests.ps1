#===========================================================================
# Testes - Camada de jobs

BeforeAll {
    $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
    . (Join-Path $script:repoRoot "functions\private\Measure-WinUtilStep.ps1")
    . (Join-Path $script:repoRoot "functions\private\Write-WinUtilLog.ps1")
    . (Join-Path $script:repoRoot "functions\private\Write-WinUtilErrorRecord.ps1")
    . (Join-Path $script:repoRoot "functions\private\Complete-WinUtilPackageRun.ps1")
    . (Join-Path $script:repoRoot "functions\private\Start-WinUtilJob.ps1")
    . (Join-Path $script:repoRoot "functions\private\Start-WinUtilNextQueuedJob.ps1")
    . (Join-Path $script:repoRoot "functions\private\Set-WinUtilWorkingView.ps1")
    . (Join-Path $script:repoRoot "functions\private\Invoke-WinUtilCloseRequest.ps1")
    . (Join-Path $script:repoRoot "functions\public\Invoke-WPFUIThread.ps1")

    function Invoke-WPFRunspace {
        param($ArgumentList, $ParameterList, [scriptblock]$ScriptBlock)
    }
    function Write-WinUtilJobBanner {
        param([string]$Message, [string]$Level)
    }
    function Write-WinUtilLog {
        param($Message, $Level, $Component, [switch]$Detail, [switch]$FileOnly)
    }
    function Step-WinUtilJob {
        param([string]$Status, [int]$Percent, [string]$State, [string]$Overlay, [switch]$Hide)
    }
    function Show-WinUtilMessage {
        param($Message, $Title, $Button, $Icon)
    }

    function script:Get-WinUtilJobRunspaceBody {
        param([hashtable]$ParameterList)

        $named = @{}
        foreach ($parameter in $ParameterList) {
            $named[$parameter[0]] = $parameter[1]
        }
        return $named
    }
}

Describe "Despacho na thread da interface" {
    # O trabalho entregue à thread da interface deve chegar como texto do corpo mais parâmetros. Um scriptblock
    # encaminhado de um runspace de worker mantém o estado de sessão daquele runspace, então todo comando que
    # ele invoca é resolvido de volta pelo runspace de origem. Medido em 400 invocações:
    # 5354 ms encaminhado contra 3 ms reconstruído a partir de texto.

    It "passa valores adiados como parâmetros em vez de capturá-los" {
        foreach ($path in @(
            "functions\private\Step-WinUtilJob.ps1",
            "functions\private\Invoke-WinUtilISO.ps1"
        )) {
            $source = Get-Content -Path (Join-Path $script:repoRoot $path) -Raw

            $source | Should -Match ([regex]::Escape('Invoke-WPFUIThread -Async -Parameters @{'))
            $source | Should -Not -Match ([regex]::Escape('GetNewClosure'))
        }
    }
}

Describe "Saída de Invoke-WPFUIThread" {
    BeforeEach {
        $dispatcher = [pscustomobject]@{ HasShutdownStarted = $false }
        $dispatcher | Add-Member -MemberType ScriptMethod -Name CheckAccess -Value { $true }
        $script:sync = [Hashtable]::Synchronized(@{
            Form = [pscustomobject]@{ Dispatcher = $dispatcher }
        })
    }

    AfterEach {
        Remove-Variable -Name sync -Scope Script -ErrorAction SilentlyContinue
    }

    # A saída do corpo não deve se juntar ao valor de retorno do chamador: um chamador que só
    # queria atualizar um controle retornaria um array e toda leitura de índice sairia errada.
    It "descarta a saída do corpo por padrão" {
        @(Invoke-WPFUIThread -ScriptBlock { "stray" }).Count | Should -Be 0
    }

    It "retorna a saída do corpo quando solicitado" {
        Invoke-WPFUIThread -PassThru -ScriptBlock { "wanted" } | Should -Be "wanted"
    }

    It "passa valores em vez de depender do escopo do chamador" {
        Invoke-WPFUIThread -PassThru -Parameters @{ Value = 7 } -ScriptBlock {
            param($Value)
            $Value * 2
        } | Should -Be 14
    }

    It "ignora um despacho síncrono cancelado pelo fechamento da janela" {
        $dispatcher = [pscustomobject]@{ HasShutdownStarted = $false }
        $dispatcher | Add-Member -MemberType ScriptMethod -Name CheckAccess -Value { $false }
        $dispatcher | Add-Member -MemberType ScriptMethod -Name Invoke -Value {
            param($Executor, $Work)
            $null = $Executor, $Work
            $this.HasShutdownStarted = $true
            throw [System.OperationCanceledException]::new("dispatcher stopped")
        }
        $script:sync = [Hashtable]::Synchronized(@{
            Form = [pscustomobject]@{ Dispatcher = $dispatcher }
            UIDispatchDelegate = [System.Func[object, object]]{ param($Work) $Work }
        })

        { Invoke-WPFUIThread -ScriptBlock { } } | Should -Not -Throw
    }

    It "não oculta uma falha de despacho enquanto a janela ainda está ativa" {
        $dispatcher = [pscustomobject]@{ HasShutdownStarted = $false }
        $dispatcher | Add-Member -MemberType ScriptMethod -Name CheckAccess -Value { $false }
        $dispatcher | Add-Member -MemberType ScriptMethod -Name Invoke -Value {
            throw [System.InvalidOperationException]::new("not a shutdown")
        }
        $script:sync = [Hashtable]::Synchronized(@{
            Form = [pscustomobject]@{ Dispatcher = $dispatcher }
            UIDispatchDelegate = [System.Func[object, object]]{ param($Work) $Work }
        })

        { Invoke-WPFUIThread -ScriptBlock { } } | Should -Throw "*not a shutdown*"
    }

    It "relança falhas síncronas de callback para que o chamador em espera as registre" {
        $tokens = $null
        $errors = $null
        $uiAst = [System.Management.Automation.Language.Parser]::ParseFile(
            (Join-Path $script:repoRoot "functions\private\Start-WinUtilUserInterface.ps1"),
            [ref]$tokens,
            [ref]$errors
        )
        $delegateAssignment = $uiAst.Find({
            param($node)
            $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                $node.Left.Extent.Text -eq '$sync.UIDispatchDelegate'
        }, $true)
        $delegateBody = $delegateAssignment.Right.Expression.Child.ScriptBlock.GetScriptBlock()
        $delegate = [System.Func[object, object]]$delegateBody
        Mock Write-WinUtilErrorRecord { }

        { $delegate.Invoke(@{ Body = 'throw "callback failed"'; Parameters = @{}; PropagateErrors = $true }) } |
            Should -Throw "*callback failed*"
        Should -Invoke Write-WinUtilErrorRecord -Times 0 -Exactly
    }

    It "registra falhas assíncronas de callback sem lançar exceção no dispatcher" {
        $tokens = $null
        $errors = $null
        $uiAst = [System.Management.Automation.Language.Parser]::ParseFile(
            (Join-Path $script:repoRoot "functions\private\Start-WinUtilUserInterface.ps1"),
            [ref]$tokens,
            [ref]$errors
        )
        $delegateAssignment = $uiAst.Find({
            param($node)
            $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                $node.Left.Extent.Text -eq '$sync.UIDispatchDelegate'
        }, $true)
        $delegateBody = $delegateAssignment.Right.Expression.Child.ScriptBlock.GetScriptBlock()
        $delegate = [System.Func[object, object]]$delegateBody
        Mock Write-WinUtilErrorRecord { }

        { $delegate.Invoke(@{ Body = 'throw "callback failed"'; Parameters = @{}; PropagateErrors = $false }) } |
            Should -Not -Throw
        Should -Invoke Write-WinUtilErrorRecord -Times 1 -Exactly
    }
}

Describe "Start-WinUtilJob" {
    BeforeEach {
        $script:sync = [Hashtable]::Synchronized(@{
            ActiveJob = $null
            Form = [pscustomobject]@{ Dispatcher = [pscustomobject]@{} }
            ItemsControl = [pscustomobject]@{ IsEnabled = $true }
        })
        $script:capturedRunspaceBody = $null
        $script:capturedRunspaceArgs = $null
        $script:activeJobAtQueueTime = $null

        Mock Show-WinUtilMessage { "OK" }
        Mock Write-WinUtilLog { }
        Mock Step-WinUtilJob { }
        Mock Invoke-WPFUIThread { & $ScriptBlock }
        Mock Invoke-WPFRunspace {
            $script:activeJobAtQueueTime = $script:sync.ActiveJob
            $script:capturedRunspaceBody = $ScriptBlock
            $script:capturedRunspaceArgs = @{}
            foreach ($parameter in $ParameterList) {
                $script:capturedRunspaceArgs[$parameter[0]] = $parameter[1]
            }
            [pscustomobject]@{ MockHandle = $true }
        }
    }

    AfterEach {
        Remove-Variable -Name sync -Scope Script -ErrorAction SilentlyContinue
        Remove-Variable -Name capturedRunspaceBody -Scope Script -ErrorAction SilentlyContinue
        Remove-Variable -Name capturedRunspaceArgs -Scope Script -ErrorAction SilentlyContinue
        Remove-Variable -Name activeJobAtQueueTime -Scope Script -ErrorAction SilentlyContinue
    }

    It "assume o estado ocupado antes de o trabalho ser enfileirado" {
        Start-WinUtilJob -Name "Example" -ScriptBlock { } | Out-Null

        $script:activeJobAtQueueTime | Should -Be "Example"
        Should -Invoke -CommandName Invoke-WPFRunspace -Times 1 -Exactly
        Should -Invoke -CommandName Write-WinUtilLog -Times 1 -Exactly -ParameterFilter {
            $Component -eq "Example" -and $Message -eq "Job Example iniciado."
        }
        Should -Invoke -CommandName Step-WinUtilJob -Times 1 -Exactly -ParameterFilter {
            $Status -eq "Example..." -and $Percent -eq 0
        }
    }

    It "usa a descrição para o texto inicial de progresso" {
        Start-WinUtilJob -Name "Example" -Description "Doing the thing" -ScriptBlock { } | Out-Null

        Should -Invoke -CommandName Step-WinUtilJob -Times 1 -Exactly -ParameterFilter {
            $Status -eq "Doing the thing..." -and $Percent -eq 0 -and $State -eq "Normal" -and $Overlay -eq "logo"
        }
    }

    It "recusa um segundo job enquanto um está em execução" {
        $script:sync.ActiveJob = "Install"

        $result = Start-WinUtilJob -Name "Tweaks" -ScriptBlock { }

        $result | Should -BeNullOrEmpty
        Should -Invoke -CommandName Invoke-WPFRunspace -Times 0 -Exactly
        Should -Invoke -CommandName Show-WinUtilMessage -Times 1 -Exactly -ParameterFilter {
            $Message -like "Install ainda está em execução*"
        }
        $script:sync.ActiveJob | Should -Be "Install"
    }

    It "assume a vaga com um token que identifica a execução, não apenas seu nome" {
        Start-WinUtilJob -Name "Install" -ScriptBlock { } | Out-Null
        $first = $script:sync.ActiveJobToken

        $first | Should -Not -BeNullOrEmpty
        $script:capturedRunspaceArgs["JobToken"] | Should -Be $first

        # uma segunda execução com o mesmo nome recebe seu próprio token, para que um worker tardio não possa liberá-lo
        $script:sync.ActiveJob = $null
        $script:sync.ActiveJobToken = $null
        Start-WinUtilJob -Name "Install" -ScriptBlock { } | Out-Null

        $script:sync.ActiveJobToken | Should -Not -Be $first
    }

    It "passa o texto do corpo e seus parâmetros ao worker" {
        Start-WinUtilJob -Name "Example" -Parameters @{ Value = 42 } -ScriptBlock { param($Value) $Value } | Out-Null

        $script:capturedRunspaceArgs["JobName"] | Should -Be "Example"
        $script:capturedRunspaceArgs["JobBody"] | Should -BeOfType [string]
        $script:capturedRunspaceArgs["JobBody"] | Should -Match 'param\(\$Value\)'
        $script:capturedRunspaceArgs["JobParameters"].Value | Should -Be 42
        $script:capturedRunspaceArgs["JobRestoresAppList"] | Should -BeFalse
    }

    It "mostra a visão de trabalho do Install enquanto um job Install executa" {
        Mock Set-WinUtilWorkingView { }

        Start-WinUtilJob -Name "Install" -Description "Installing apps" -ScriptBlock { } | Out-Null

        Should -Invoke -CommandName Set-WinUtilWorkingView -Times 1 -Exactly -ParameterFilter {
            $Area -eq "Install" -and $Working -eq $true -and $Label -eq "Installing apps..."
        }
    }

    It "mostra a visão de trabalho do Install enquanto um job Uninstall executa" {
        Mock Set-WinUtilWorkingView { }

        Start-WinUtilJob -Name "Uninstall" -ScriptBlock { } | Out-Null

        Should -Invoke -CommandName Set-WinUtilWorkingView -Times 1 -Exactly -ParameterFilter {
            $Area -eq "Install" -and $Working -eq $true
        }
    }

    It "mostra a visão de trabalho do Install para o job do botão Upgrade All" {
        Mock Set-WinUtilWorkingView { }

        Start-WinUtilJob -Name "Upgrade all Applications" -ScriptBlock { } | Out-Null

        $script:capturedRunspaceArgs["JobWorkingArea"] | Should -Be "Install"
        Should -Invoke Set-WinUtilWorkingView -Times 1 -Exactly -ParameterFilter {
            $Area -eq "Install" -and $Working -eq $true
        }
    }

    It "não permite que um worker Upgrade obsoleto oculte uma visão de trabalho do Install mais recente" {
        Mock Set-WinUtilWorkingView { }
        Start-WinUtilJob -Name "Upgrade all Applications" -ScriptBlock { } | Out-Null
        $oldToken = $script:capturedRunspaceArgs["JobToken"]
        $script:sync.ActiveJob = "Install"
        $script:sync.ActiveJobToken = "current-token"

        & $script:capturedRunspaceBody `
            -JobName "Upgrade all Applications" `
            -JobLabel "Upgrade all Applications" `
            -JobBody '$null = $true' `
            -JobParameters @{} `
            -JobWorkingArea "Install" `
            -JobToken $oldToken

        Should -Not -Invoke Set-WinUtilWorkingView -ParameterFilter { $Working -eq $false }
        $script:sync.ActiveJobToken | Should -Be "current-token"
    }
    It "mostra a visão de trabalho de Ajustes enquanto um job Tweaks executa" {
        Mock Set-WinUtilWorkingView { }

        Start-WinUtilJob -Name "Tweaks" -Description "Applying tweaks" -ScriptBlock { } | Out-Null

        Should -Invoke -CommandName Set-WinUtilWorkingView -Times 1 -Exactly -ParameterFilter {
            $Area -eq "Tweaks" -and $Working -eq $true -and $Label -eq "Applying tweaks..."
        }
    }

    It "mostra a visão de trabalho de Ajustes enquanto um job Undo executa" {
        Mock Set-WinUtilWorkingView { }

        Start-WinUtilJob -Name "Undo tweaks" -ScriptBlock { } | Out-Null

        Should -Invoke -CommandName Set-WinUtilWorkingView -Times 1 -Exactly -ParameterFilter {
            $Area -eq "Tweaks" -and $Working -eq $true
        }
    }

    It "não mostra visão de trabalho para outros jobs" {
        Mock Set-WinUtilWorkingView { }

        Start-WinUtilJob -Name "OOSU" -ScriptBlock { } | Out-Null

        Should -Invoke -CommandName Set-WinUtilWorkingView -Times 0 -Exactly
    }

    It "oculta a visão de trabalho quando o worker termina" {
        Mock Set-WinUtilWorkingView { }

        Start-WinUtilJob -Name "Tweaks" -ScriptBlock { } | Out-Null

        & $script:capturedRunspaceBody `
            -JobName "Tweaks" `
            -JobLabel "Applying tweaks" `
            -JobBody '$null = $true' `
            -JobParameters @{} `
            -JobRestoresAppList $false `
            -JobWorkingArea "Tweaks" `
            -JobToken $script:capturedRunspaceArgs["JobToken"]

        Should -Invoke -CommandName Set-WinUtilWorkingView -Times 1 -Exactly -ParameterFilter {
            $Area -eq "Tweaks" -and $Working -eq $false
        }
        $script:sync.ActiveJob | Should -BeNullOrEmpty
    }

    It "ainda libera o job quando ocultar a visão de trabalho falha" {
        Mock Set-WinUtilWorkingView { if ($Working -eq $false) { throw "dispatcher stopped" } }

        Start-WinUtilJob -Name "Install" -ScriptBlock { } | Out-Null

        {
            & $script:capturedRunspaceBody `
                -JobName "Install" `
                -JobLabel "Installing apps" `
                -JobBody '$null = $true' `
                -JobParameters @{} `
                -JobRestoresAppList $false `
                -JobWorkingArea "Install" `
                -JobToken $script:capturedRunspaceArgs["JobToken"]
        } | Should -Not -Throw

        $script:sync.ActiveJob | Should -BeNullOrEmpty
        $script:sync.ActiveJobToken | Should -BeNullOrEmpty
        Should -Invoke -CommandName Write-WinUtilLog -Times 1 -Exactly -ParameterFilter {
            $Level -eq "WARN" -and $Message -like "Não foi possível ocultar a visualização de trabalho*"
        }
    }

    It "deixa a lista de aplicativos cinza apenas quando solicitado" {
        Start-WinUtilJob -Name "Install" -DisableAppList -ScriptBlock { } | Out-Null

        $script:sync.ItemsControl.IsEnabled | Should -BeFalse
        $script:capturedRunspaceArgs["JobRestoresAppList"] | Should -BeTrue
    }

    It "libera o job e restaura a lista de aplicativos quando o agendamento falha" {
        Mock Invoke-WPFRunspace { throw "pool failed" }
        Mock Write-Host { }

        { Start-WinUtilJob -Name "Install" -DisableAppList -ScriptBlock { } } | Should -Not -Throw

        $script:sync.ActiveJob | Should -BeNullOrEmpty
        $script:sync.ItemsControl.IsEnabled | Should -BeTrue
    }

    It "libera o job quando a configuração de progresso e o relatório de falha lançam exceção" {
        Mock Step-WinUtilJob { throw "progress unavailable" }
        Mock Write-Host { }

        { Start-WinUtilJob -Name "Install" -DisableAppList -ScriptBlock { } } | Should -Not -Throw

        $script:sync.ActiveJob | Should -BeNullOrEmpty
        $script:sync.ActiveJobToken | Should -BeNullOrEmpty
        $script:sync.ItemsControl.IsEnabled | Should -BeTrue
        Should -Invoke -CommandName Invoke-WPFRunspace -Times 0 -Exactly
    }

    It "relata a conclusão e libera o estado ocupado quando o corpo tem sucesso" {
        Start-WinUtilJob -Name "Example" -ScriptBlock { } | Out-Null

        & $script:capturedRunspaceBody `
            -JobName "Example" `
            -JobBody '$null = $true' `
            -JobParameters @{} `
            -JobRestoresAppList $false `
            -JobToken $script:capturedRunspaceArgs["JobToken"]

        Should -Invoke -CommandName Write-WinUtilLog -Times 1 -Exactly -ParameterFilter {
            $Component -eq "Example" -and $Message -like "Job Example concluído em * ms."
        }
        Should -Invoke -CommandName Step-WinUtilJob -Times 1 -Exactly -ParameterFilter {
            $Status -eq "Example concluído" -and $Percent -eq 100 -and $State -eq "None" -and $Overlay -eq "checkmark"
        }
        $script:sync.ActiveJob | Should -BeNullOrEmpty
    }

    It "não permite que um worker obsoleto substitua o resultado do job atual" {
        Start-WinUtilJob -Name "Old" -ScriptBlock { } | Out-Null
        $oldToken = $script:capturedRunspaceArgs["JobToken"]
        $script:sync.ActiveJob = "Current"
        $script:sync.ActiveJobToken = "current-token"
        $script:sync.LastJobResult = [pscustomobject]@{ Token = "current-token"; Errors = 0; Warnings = 0 }

        & $script:capturedRunspaceBody `
            -JobName "Old" `
            -JobLabel "Old" `
            -JobBody '$global:WinUtilJobErrorCount = 1' `
            -JobParameters @{} `
            -JobRestoresAppList $false `
            -JobToken $oldToken

        $script:sync.LastJobResult.Token | Should -Be "current-token"
        $script:sync.ActiveJob | Should -Be "Current"
        $script:sync.ActiveJobToken | Should -Be "current-token"
    }

    It "registra a falha e libera o estado ocupado quando o corpo lança exceção" {
        Start-WinUtilJob -Name "Example" -ScriptBlock { } | Out-Null
        $script:sync.ActiveJob = "Example"
        Mock Write-Host { }

        {
            & $script:capturedRunspaceBody `
                -JobName "Example" `
                -JobBody 'throw "boom"' `
                -JobParameters @{} `
                -JobRestoresAppList $false `
            -JobToken $script:capturedRunspaceArgs["JobToken"]
        } | Should -Not -Throw

        Should -Invoke -CommandName Write-WinUtilLog -Times 1 -Exactly -ParameterFilter {
            $Level -eq "ERROR" -and $Component -eq "Example" -and $Message -like "*falhou após * ms : boom"
        }
        Should -Invoke -CommandName Step-WinUtilJob -Times 1 -Exactly -ParameterFilter {
            $Status -eq "Example falhou" -and $State -eq "Error" -and $Overlay -eq "warning"
        }
        $script:sync.ActiveJob | Should -BeNullOrEmpty
    }

    It "não conta um erro novamente quando o corpo o registra antes de lançar exceção" {
        Start-WinUtilJob -Name "Example" -ScriptBlock { } | Out-Null

        & $script:capturedRunspaceBody `
            -JobName "Example" `
            -JobLabel "Example" `
            -JobBody 'Write-WinUtilLog -Level "ERROR" -Component "Example" -Message "operation failed"; $exception = [System.InvalidOperationException]::new("operation failed"); $exception.Data["WinUtilErrorReported"] = $true; throw $exception' `
            -JobParameters @{} `
            -JobRestoresAppList $false `
            -JobToken $script:capturedRunspaceArgs["JobToken"]

        Should -Invoke Write-WinUtilLog -Times 1 -Exactly -ParameterFilter {
            $Level -eq "ERROR" -and -not $Detail
        }
    }

    It "conta um erro terminal distinto após um erro relatado anteriormente" {
        Start-WinUtilJob -Name "Example" -ScriptBlock { } | Out-Null

        & $script:capturedRunspaceBody `
            -JobName "Example" `
            -JobLabel "Example" `
            -JobBody 'Write-WinUtilLog -Level "ERROR" -Component "Example" -Message "first failure"; throw "second failure"' `
            -JobParameters @{} `
            -JobRestoresAppList $false `
            -JobToken $script:capturedRunspaceArgs["JobToken"]

        Should -Invoke Write-WinUtilLog -Times 2 -Exactly -ParameterFilter {
            $Level -eq "ERROR" -and -not $Detail
        }
    }

    It "relata um job que registrou erros sem lançar exceção" {
        Start-WinUtilJob -Name "Example" -ScriptBlock { } | Out-Null

        & $script:capturedRunspaceBody `
            -JobName "Example" `
            -JobLabel "Example" `
            -JobBody '$global:WinUtilJobErrorCount = 1' `
            -JobParameters @{} `
            -JobRestoresAppList $false `
            -JobToken $script:capturedRunspaceArgs["JobToken"]

        Should -Invoke -CommandName Step-WinUtilJob -Times 1 -Exactly -ParameterFilter {
            $Status -eq "Example concluído com 1 erro(s)" -and $State -eq "Paused" -and $Overlay -eq "warning"
        }
        $script:sync.ActiveJob | Should -BeNullOrEmpty
    }

    It "ignora erros registrados fora do worker do job ativo" {
        $script:sync.LoggedErrors = [System.Collections.ArrayList]::Synchronized([System.Collections.ArrayList]::new())
        $null = $script:sync.LoggedErrors.Add("[UI] unrelated rendering failure")
        Start-WinUtilJob -Name "Example" -ScriptBlock { } | Out-Null

        & $script:capturedRunspaceBody `
            -JobName "Example" `
            -JobLabel "Example" `
            -JobBody '$null = $sync.LoggedErrors.Add("[UI] another unrelated failure")' `
            -JobParameters @{} `
            -JobRestoresAppList $false `
            -JobToken $script:capturedRunspaceArgs["JobToken"]

        Should -Invoke -CommandName Step-WinUtilJob -Times 1 -Exactly -ParameterFilter {
            $Status -eq "Example concluído" -and $State -eq "None" -and $Overlay -eq "checkmark"
        }
    }

    It "mostra avisos e erros não terminais levantados pelo corpo" {
        $script:sync.LoggedErrors = [System.Collections.ArrayList]::Synchronized([System.Collections.ArrayList]::new())
        Start-WinUtilJob -Name "Example" -ScriptBlock { } | Out-Null

        & $script:capturedRunspaceBody `
            -JobName "Example" `
            -JobLabel "Example" `
            -JobBody 'Write-Warning "a warning"' `
            -JobParameters @{} `
            -JobRestoresAppList $false `
            -JobToken $script:capturedRunspaceArgs["JobToken"]

        Should -Invoke -CommandName Write-WinUtilLog -Times 1 -Exactly -ParameterFilter {
            $Level -eq "WARN" -and $Message -eq "a warning"
        }
        Should -Invoke -CommandName Step-WinUtilJob -Times 1 -Exactly -ParameterFilter {
            $Status -eq "Example concluído com 1 aviso(s)" -and $State -eq "Paused" -and $Overlay -eq "warning"
        }
        $script:sync.LastJobResult.Warnings | Should -Be 1
        $script:sync.LastJobResult.Errors | Should -Be 0
    }

    It "registra a saída de Write-Host do corpo e dos auxiliares que ele chama" {
        Mock Write-WinUtilHost { }
        Start-WinUtilJob -Name "Tweaks" -ScriptBlock { } | Out-Null

        & $script:capturedRunspaceBody `
            -JobName "Tweaks" `
            -JobLabel "Running tweaks" `
            -JobBody 'function Set-Example { Write-Host "Set HKLM:\Example to 1" -ForegroundColor Green }; Write-Host "Running Script for WPFTweaksExample"; Set-Example' `
            -JobParameters @{} `
            -JobRestoresAppList $false `
            -JobToken $script:capturedRunspaceArgs["JobToken"]

        Should -Invoke -CommandName Write-WinUtilLog -Times 1 -Exactly -ParameterFilter {
            $Component -eq "Tweaks" -and $Message -eq "Running Script for WPFTweaksExample" -and $FileOnly
        }
        Should -Invoke -CommandName Write-WinUtilLog -Times 1 -Exactly -ParameterFilter {
            $Component -eq "Tweaks" -and $Message -eq "Set HKLM:\Example to 1" -and $FileOnly
        }
        Should -Invoke -CommandName Write-WinUtilHost -Times 1 -Exactly -ParameterFilter {
            $Object -eq "Set HKLM:\Example to 1" -and $ForegroundColor -eq "Green"
        }
        $script:sync.LastJobResult.Warnings | Should -Be 0
    }

    It "termina com um aviso quando a instalação elevada omite um pacote no escopo do usuário" {
        Start-WinUtilJob -Name "Install" -ScriptBlock { } | Out-Null

        & $script:capturedRunspaceBody `
            -JobName "Install" `
            -JobLabel "Installing apps" `
            -JobBody 'Complete-WinUtilPackageRun -Action "Install" -Results @([pscustomobject]@{ Package = "Microsoft.Sysinternals.ProcessExplorer"; Action = "Install"; ExitCode = -1978335107; Outcome = "Skipped"; Detail = "already installed for the current user; elevated WinUtil cannot update it" })' `
            -JobParameters @{} `
            -JobRestoresAppList $false `
            -JobToken $script:capturedRunspaceArgs["JobToken"]

        Should -Invoke -CommandName Step-WinUtilJob -Times 1 -Exactly -ParameterFilter {
            $Status -eq "Install concluído com 1 aviso(s)" -and $State -eq "Paused" -and $Overlay -eq "warning"
        }
    }

    It "restaura a lista de aplicativos após um job com falha que a desativou" {
        Start-WinUtilJob -Name "Install" -DisableAppList -ScriptBlock { } | Out-Null
        $script:sync.ActiveJob = "Install"
        Mock Write-Host { }

        & $script:capturedRunspaceBody `
            -JobName "Install" `
            -JobBody 'throw "boom"' `
            -JobParameters @{} `
            -JobRestoresAppList $true `
            -JobToken $script:capturedRunspaceArgs["JobToken"]

        $script:sync.ItemsControl.IsEnabled | Should -BeTrue
        $script:sync.ActiveJob | Should -BeNullOrEmpty
    }

    It "libera o job quando o desligamento do dispatcher aborta a restauração da lista de aplicativos" {
        $script:dispatchCount = 0
        Mock Invoke-WPFUIThread {
            $script:dispatchCount++
            # Atualização da fila, exibição da visão de trabalho e desativação da lista de aplicativos precedem a restauração do worker.
            if ($script:dispatchCount -gt 3) {
                throw [System.Threading.Tasks.TaskCanceledException]::new("dispatcher stopped")
            }
            & $ScriptBlock
        }

        Start-WinUtilJob -Name "Install" -DisableAppList -ScriptBlock { } | Out-Null

        {
            & $script:capturedRunspaceBody `
                -JobName "Install" `
                -JobBody '$null = $true' `
                -JobParameters @{} `
                -JobRestoresAppList $true `
                -JobToken $script:capturedRunspaceArgs["JobToken"]
        } | Should -Not -Throw

        $script:sync.ActiveJob | Should -BeNullOrEmpty
        $script:sync.ActiveJobToken | Should -BeNullOrEmpty
        Should -Invoke Write-WinUtilLog -Times 1 -Exactly -ParameterFilter {
            $Level -eq "WARN" -and $Message -like "Não foi possível restaurar a lista de aplicativos*"
        }
    }
}

Describe "Resumos de tempo dos jobs" {
    BeforeEach {
        $script:sync = [Hashtable]::Synchronized(@{
            StepTimings = [System.Collections.ArrayList]::Synchronized([System.Collections.ArrayList]::new())
        })
        $null = $sync.StepTimings.Add([pscustomobject]@{ Scope = "Install"; Step = "old"; Milliseconds = 100 })
        $null = $sync.StepTimings.Add([pscustomobject]@{ Scope = "Install"; Step = "current"; Milliseconds = 25 })
        Mock Write-WinUtilLog { }
    }

    It "exclui entradas registradas antes da execução atual" {
        Write-WinUtilTimingSummary -Scope "Install" -TotalMilliseconds 30 -StartIndex 1

        Should -Invoke -CommandName Write-WinUtilLog -Times 1 -Exactly -ParameterFilter {
            $Message -eq "timing summary: 1 etapa(s), 25 ms medidos de 30 ms no total"
        }
    }
}

Describe "Fila de jobs" {
    BeforeEach {
        $script:sync = [Hashtable]::Synchronized(@{
            ActiveJob = $null
            JobQueue = [System.Collections.Generic.List[object]]::new()
            Form = [pscustomobject]@{ Dispatcher = [pscustomobject]@{} }
        })
        $script:started = [System.Collections.Generic.List[object]]::new()

        Mock Show-WinUtilMessage { "OK" }
        Mock Write-WinUtilLog { }
        Mock Step-WinUtilJob { }
        Mock Update-WinUtilJobQueueUI { }
        Mock Invoke-WPFUIThread { & $ScriptBlock }
        Mock Invoke-WPFRunspace {
            $runArgs = @{}
            foreach ($parameter in $ParameterList) { $runArgs[$parameter[0]] = $parameter[1] }
            $script:started.Add([pscustomobject]@{ Body = $ScriptBlock; Args = $runArgs })
        }
    }

    AfterEach {
        Remove-Variable -Name sync, started -Scope Script -ErrorAction SilentlyContinue
    }

    # Executa o corpo do worker como o pool faria, o que libera a vaga e posta o próximo job
    function script:Complete-TestJob {
        param($Run, [string]$Body = '$null = $true')

        & $Run.Body -JobName $Run.Args["JobName"] -JobLabel $Run.Args["JobLabel"] -JobBody $Body `
            -JobParameters @{} -JobRestoresAppList $false -JobToken $Run.Args["JobToken"]
    }

    It "enfileira em vez de recusar quando solicitado e a vaga está ocupada" {
        $script:sync.ActiveJob = "Install"

        $result = Start-WinUtilJob -Name "Tweaks" -Description "Applying tweaks" -DisableAppList -QueueIfBusy -Parameters @{ Tweaks = @("A", "B") } -ScriptBlock { param($Tweaks) $Tweaks }

        $result | Should -BeNullOrEmpty
        $script:sync.JobQueue.Count | Should -Be 1
        $item = $script:sync.JobQueue[0]
        $item.Name | Should -Be "Tweaks"
        $item.Description | Should -Be "Applying tweaks"
        $item.DisableAppList | Should -BeTrue
        $item.Parameters.Tweaks | Should -Be @("A", "B")
        $item.ScriptBlock | Should -Match 'param\(\$Tweaks\)'
        [guid]::Parse($item.Id) | Should -Not -BeNullOrEmpty
        Should -Invoke -CommandName Show-WinUtilMessage -Times 0 -Exactly
        $script:started.Count | Should -Be 0
        Should -Invoke -CommandName Write-WinUtilLog -Times 1 -Exactly -ParameterFilter {
            $Component -eq "Tweaks" -and $Message -like "*enfileirado atrás de Install*posição 1*"
        }
    }

    It "inicia imediatamente com a opção quando a vaga está livre" {
        Start-WinUtilJob -Name "Tweaks" -QueueIfBusy -ScriptBlock { } | Out-Null

        $script:sync.JobQueue.Count | Should -Be 0
        $script:sync.ActiveJob | Should -Be "Tweaks"
        $script:started.Count | Should -Be 1
    }

    It "ainda recusa com uma mensagem e não mexe na fila sem a opção" {
        $script:sync.ActiveJob = "Install"

        Start-WinUtilJob -Name "ISO mount" -ScriptBlock { } | Out-Null

        $script:sync.JobQueue.Count | Should -Be 0
        Should -Invoke -CommandName Show-WinUtilMessage -Times 1 -Exactly -ParameterFilter {
            $Message -like "Install ainda está em execução*"
        }
    }

    It "não enfileira um job aninhado, que executa inline" {
        $script:sync.ActiveJob = "Install"
        $global:WinUtilIsJobWorker = $true
        try {
            Start-WinUtilJob -Name "Inner" -QueueIfBusy -Parameters @{ Value = 7 } -ScriptBlock { param($Value) $script:innerRan = $Value } | Out-Null
        } finally {
            $global:WinUtilIsJobWorker = $false
        }

        $script:innerRan | Should -Be 7
        $script:sync.JobQueue.Count | Should -Be 0
    }

    It "não enfileira enquanto o WinUtil está fechando" {
        $script:sync.ActiveJob = "Install"
        $script:sync.ShuttingDown = $true

        Start-WinUtilJob -Name "Tweaks" -QueueIfBusy -ScriptBlock { } | Out-Null

        $script:sync.JobQueue.Count | Should -Be 0
    }

    It "recusa trabalho quando o fechamento vence antes do bloqueio da fila (<Flag>, <Running>)" -TestCases @(
        @{ Flag = "ShuttingDown"; Running = "Install" }
        @{ Flag = "ShuttingDown"; Running = $null }
        @{ Flag = "FinishInConsole"; Running = "Install" }
        @{ Flag = "FinishInConsole"; Running = $null }
    ) {
        param($Flag, $Running)
        $script:sync.ActiveJob = $Running
        Mock ConvertTo-Json { $script:sync[$Flag] = $true; '{}' }

        Start-WinUtilJob -Name "Late" -QueueIfBusy -Parameters @{ Value = 1 } -ScriptBlock { } | Out-Null

        $script:sync.ActiveJob | Should -Be $Running
        $script:sync.JobQueue.Count | Should -Be 0
        $script:started.Count | Should -Be 0
    }

    It "executa os jobs enfileirados em ordem de chegada e continua após um falhar" {
        Start-WinUtilJob -Name "First" -QueueIfBusy -ScriptBlock { } | Out-Null
        Start-WinUtilJob -Name "Second" -QueueIfBusy -Parameters @{ Value = 2 } -ScriptBlock { } | Out-Null
        Start-WinUtilJob -Name "Third" -QueueIfBusy -DisableAppList -ScriptBlock { } | Out-Null
        $script:sync.JobQueue.Count | Should -Be 2

        Complete-TestJob -Run $script:started[0] -Body 'throw "boom"'

        $script:started.Count | Should -Be 2
        $script:started[1].Args["JobName"] | Should -Be "Second"
        $script:started[1].Args["JobParameters"].Value | Should -Be 2
        $script:sync.ActiveJob | Should -Be "Second"
        $script:sync.JobQueue.Count | Should -Be 1

        Complete-TestJob -Run $script:started[1]

        $script:started.Count | Should -Be 3
        $script:started[2].Args["JobName"] | Should -Be "Third"
        $script:started[2].Args["JobRestoresAppList"] | Should -BeTrue
        $script:sync.JobQueue.Count | Should -Be 0

        Complete-TestJob -Run $script:started[2]

        $script:started.Count | Should -Be 3
        $script:sync.ActiveJob | Should -BeNullOrEmpty
        Should -Invoke -CommandName Write-WinUtilLog -Times 1 -Exactly -ParameterFilter {
            $Component -eq "Second" -and $Message -eq "Iniciando o job enfileirado Second."
        }
    }

    It "inicia o próximo job quando o agendamento do atual falha" {
        $script:sync.ActiveJob = "Install"
        Start-WinUtilJob -Name "Queued" -QueueIfBusy -ScriptBlock { } | Out-Null
        $script:sync.ActiveJob = $null
        Mock Invoke-WPFRunspace {
            $script:started.Add($null)
            if ($script:started.Count -eq 1) { throw "pool is gone" }
        }

        Start-WinUtilJob -Name "Broken" -QueueIfBusy -ScriptBlock { } | Out-Null

        # Broken falhou ao agendar, liberou a vaga e o job enfileirado a ocupou
        $script:started.Count | Should -Be 2
        $script:sync.JobQueue.Count | Should -Be 0
    }

    It "não inicia nada enquanto a vaga está ocupada" {
        $script:sync.ActiveJob = "Install"
        Start-WinUtilJob -Name "Queued" -QueueIfBusy -ScriptBlock { } | Out-Null

        Start-WinUtilNextQueuedJob

        $script:sync.JobQueue.Count | Should -Be 1
        $script:started.Count | Should -Be 0
    }

    It "não inicia a fila quando o WinUtil está fechando" {
        foreach ($flag in @("ShuttingDown", "FinishInConsole")) {
            $script:sync.Remove("ShuttingDown")
            $script:sync.Remove("FinishInConsole")
            $script:sync.JobQueue.Clear()
            $script:sync.ActiveJob = "Install"
            Start-WinUtilJob -Name "Queued" -QueueIfBusy -ScriptBlock { } | Out-Null
            $script:sync.ActiveJobToken = "t"
            $script:sync[$flag] = $true

            $null = Clear-WinUtilActiveJob -Token "t"

            $script:sync.ActiveJob | Should -BeNullOrEmpty
            $script:sync.JobQueue.Count | Should -Be 1
            $script:started.Count | Should -Be 0
        }
    }

    It "não inicia a fila quando a vaga é redefinida sem um token" {
        $script:sync.ActiveJob = "Install"
        Start-WinUtilJob -Name "Queued" -QueueIfBusy -ScriptBlock { } | Out-Null

        $null = Clear-WinUtilActiveJob

        $script:sync.JobQueue.Count | Should -Be 1
        $script:started.Count | Should -Be 0
    }

    It "move um job para cima e para baixo e não mexe nas extremidades" {
        $script:sync.ActiveJob = "Install"
        foreach ($name in "A", "B", "C") {
            Start-WinUtilJob -Name $name -QueueIfBusy -ScriptBlock { } | Out-Null
        }
        $ids = @($script:sync.JobQueue | ForEach-Object Id)
        $order = { (@($script:sync.JobQueue | ForEach-Object Name)) -join "" }

        Move-WinUtilQueuedJob -Id $ids[0] -Direction Up
        & $order | Should -Be "ABC"
        Move-WinUtilQueuedJob -Id $ids[2] -Direction Down
        & $order | Should -Be "ABC"
        Move-WinUtilQueuedJob -Id $ids[1] -Direction Up
        & $order | Should -Be "BAC"
        Move-WinUtilQueuedJob -Id $ids[1] -Direction Down
        & $order | Should -Be "ABC"
        Move-WinUtilQueuedJob -Id $ids[0] -Direction Down
        & $order | Should -Be "BAC"
        Move-WinUtilQueuedJob -Id "not-an-id" -Direction Up
        & $order | Should -Be "BAC"

        Should -Invoke -CommandName Write-WinUtilLog -Times 1 -Exactly -ParameterFilter {
            $Component -eq "B" -and $Message -eq "Movido o job enfileirado B up."
        }
    }

    It "cancela um job enfileirado e ignora um que já começou" {
        $script:sync.ActiveJob = "Install"
        foreach ($name in "A", "B") {
            Start-WinUtilJob -Name $name -QueueIfBusy -ScriptBlock { } | Out-Null
        }
        $ids = @($script:sync.JobQueue | ForEach-Object Id)

        Remove-WinUtilQueuedJob -Id $ids[0]
        Remove-WinUtilQueuedJob -Id $ids[0]

        @($script:sync.JobQueue | ForEach-Object Name) | Should -Be @("B")
        Should -Invoke -CommandName Write-WinUtilLog -Times 1 -Exactly -ParameterFilter {
            $Component -eq "A" -and $Message -eq "Cancelado o job enfileirado A."
        }

        # B começa, então cancelá-lo agora não encontra nada na fila e deixa o job em execução como está
        $script:sync.ActiveJob = $null
        Start-WinUtilNextQueuedJob
        Remove-WinUtilQueuedJob -Id $ids[1]
        $script:sync.ActiveJob | Should -Be "B"
        $script:started.Count | Should -Be 1
    }

    It "mantém os parâmetros de um job enfileirado como estavam quando o usuário clicou" {
        $script:sync.ActiveJob = "Install"
        $selection = [System.Collections.Generic.List[string]]::new()
        $selection.Add("WPFTweaksOne")

        Start-WinUtilJob -Name "Tweaks" -QueueIfBusy -Parameters @{ Tweaks = @($selection) } -ScriptBlock { } | Out-Null
        $selection.Add("WPFTweaksTwo")

        $script:sync.JobQueue[0].Parameters.Tweaks | Should -Be @("WPFTweaksOne")
    }

    It "faz uma cópia da seleção em cada chamador que enfileira" {
        . (Join-Path $script:repoRoot "functions\public\Invoke-WPFtweaksbutton.ps1")
        . (Join-Path $script:repoRoot "functions\public\Invoke-WPFFeatureInstall.ps1")
        . (Join-Path $script:repoRoot "functions\public\Invoke-WPFAppxInstall.ps1")
        . (Join-Path $script:repoRoot "functions\public\Invoke-WPFAppxRemoval.ps1")
        . (Join-Path $script:repoRoot "functions\public\Invoke-WPFundoall.ps1")
        $script:captured = @{}
        Mock Start-WinUtilJob { $script:captured[$Name] = @{ Queue = [bool]$QueueIfBusy; Parameters = $Parameters } }

        $newSelection = { $l = [System.Collections.Generic.List[string]]::new(); $l.Add("One"); , $l }
        $script:sync["WPFchangedns"] = [pscustomobject]@{ text = "Default" }
        $script:sync.configs = @{ appxHashtable = @{} }
        $script:sync.selectedTweaks = & $newSelection
        $script:sync.selectedFeatures = & $newSelection
        $script:sync.selectedAppx = & $newSelection

        Invoke-WPFtweaksbutton
        Invoke-WPFundoall
        Invoke-WPFFeatureInstall
        Invoke-WPFAppxInstall
        Invoke-WPFAppxRemoval
        $script:sync.selectedTweaks.Add("Two")
        $script:sync.selectedFeatures.Add("Two")
        $script:sync.selectedAppx.Add("Two")

        foreach ($name in "Tweaks", "Undo tweaks", "Features", "AppX install", "AppX") {
            $script:captured[$name].Queue | Should -BeTrue -Because $name
        }
        $script:captured["Tweaks"].Parameters.Tweaks | Should -Be @("One")
        $script:captured["Undo tweaks"].Parameters.Tweaks | Should -Be @("One")
        $script:captured["Features"].Parameters.Features | Should -Be @("One")
        $script:captured["AppX install"].Parameters.Selected | Should -Be @("One")
        $script:captured["AppX"].Parameters.Selected | Should -Be @("One")
    }

    It "mantém atualizações enfileiradas de diferentes gerenciadores de pacotes distintas e usa a solicitada" {
        . (Join-Path $script:repoRoot 'functions/public/Invoke-WPFButton.ps1')
        . (Join-Path $script:repoRoot 'functions/public/Invoke-WPFInstallUpgrade.ps1')
        $script:sync.ActiveJob = 'Held'
        $script:sync.configs = @{ feature = @{} }
        $script:sync.preferences = @{ packagemanager = 'Choco' }
        Mock Invoke-WPFInstallUpgrade {}

        Invoke-WPFButton -Button WPFInstallUpgrade
        $script:sync.preferences.packagemanager = 'Winget'
        Invoke-WPFButton -Button WPFInstallUpgrade

        $script:sync.JobQueue.Count | Should -Be 2
        $script:sync.JobQueue[0].Parameters.ManagerPreference | Should -Be 'Choco'
        $script:sync.JobQueue[1].Parameters.ManagerPreference | Should -Be 'Winget'
        $queued = $script:sync.JobQueue[0]
        $parameters = $queued.Parameters
        & ([scriptblock]::Create($queued.ScriptBlock)) @parameters
        Should -Invoke Invoke-WPFInstallUpgrade -Times 1 -Exactly -ParameterFilter { $ManagerPreference -eq 'Choco' }
    }

    It "atualiza com o gerenciador explícito em vez de uma preferência posterior (<Manager>)" -TestCases @(
        @{ Manager = 'Choco'; Later = 'Winget' }
        @{ Manager = 'Winget'; Later = 'Choco' }
    ) {
        param($Manager, $Later)
        . (Join-Path $script:repoRoot 'functions/public/Invoke-WPFInstallUpgrade.ps1')
        function Install-WinUtilWinget {}
        function Install-WinUtilChoco {}
        function Install-WinUtilProgramWinget { param($Action, $Programs) }
        function Install-WinUtilProgramChoco { param($Action, $Programs) }
        Mock Install-WinUtilWinget {}
        Mock Install-WinUtilChoco {}
        Mock Install-WinUtilProgramWinget {}
        Mock Install-WinUtilProgramChoco {}
        Mock Measure-WinUtilStep { & $ScriptBlock }
        Mock Complete-WinUtilPackageRun {}
        $script:sync.preferences = @{ packagemanager = $Later }

        Invoke-WPFInstallUpgrade -ManagerPreference $Manager

        $expectedChoco = [int]($Manager -eq 'Choco')
        Should -Invoke Install-WinUtilProgramChoco -Times $expectedChoco -Exactly -ParameterFilter { $Action -eq 'Upgrade' -and $Programs[0] -eq 'all' }
        Should -Invoke Install-WinUtilProgramWinget -Times (1 - $expectedChoco) -Exactly -ParameterFilter { $Action -eq 'Upgrade' -and $Programs[0] -eq 'all' }
    }

    It "enfileira uma nova ação atrás da cabeça enquanto a vaga está reservada para a fila" {
        $script:sync.JobQueue.Add([pscustomobject]@{ Id = "1"; Name = "Head"; Description = ""; ScriptBlock = ""; Parameters = @{}; DisableAppList = $false })
        $script:sync.JobHandoff = $true

        Start-WinUtilJob -Name "New" -QueueIfBusy -ScriptBlock { } | Out-Null

        @($script:sync.JobQueue | ForEach-Object Name) | Should -Be @("Head", "New")
        $script:sync.ActiveJob | Should -BeNullOrEmpty
        $script:started.Count | Should -Be 0
        Should -Invoke -CommandName Write-WinUtilLog -Times 1 -Exactly -ParameterFilter {
            $Message -like "*enfileirado atrás de Operações na fila, posição 2*"
        }
    }

    It "recusa uma ação sem a opção enquanto a vaga está reservada para a fila" {
        $script:sync.JobQueue.Add([pscustomobject]@{ Id = "1"; Name = "Head" })
        $script:sync.JobHandoff = $true

        Start-WinUtilJob -Name "ISO mount" -ScriptBlock { } | Out-Null

        $script:sync.JobQueue.Count | Should -Be 1
        $script:started.Count | Should -Be 0
        Should -Invoke -CommandName Show-WinUtilMessage -Times 1 -Exactly -ParameterFilter {
            $Message -like "Operações na fila ainda está em execução*"
        }
    }

    It "mantém a vaga para a fila após um job terminar e a entrega à cabeça" {
        Mock Invoke-WPFUIThread { }
        Start-WinUtilJob -Name "First" -QueueIfBusy -ScriptBlock { } | Out-Null
        Start-WinUtilJob -Name "Head" -QueueIfBusy -Parameters @{ Value = 1 } -ScriptBlock { } | Out-Null

        Complete-TestJob -Run $script:started[0]

        $script:sync.ActiveJob | Should -BeNullOrEmpty
        $script:sync.JobHandoff | Should -BeTrue
        Start-WinUtilJob -Name "Late" -QueueIfBusy -ScriptBlock { } | Out-Null
        @($script:sync.JobQueue | ForEach-Object Name) | Should -Be @("Head", "Late")
        $script:started.Count | Should -Be 1

        Start-WinUtilNextQueuedJob

        $script:started.Count | Should -Be 2
        $script:started[1].Args["JobName"] | Should -Be "Head"
        $script:started[1].Args["JobParameters"].Value | Should -Be 1
        $script:sync.ActiveJob | Should -Be "Head"
        $script:sync.JobHandoff | Should -BeFalse
        @($script:sync.JobQueue | ForEach-Object Name) | Should -Be @("Late")
    }

    It "não mantém a vaga quando nada está enfileirado ou o WinUtil está fechando" {
        $script:sync.ActiveJob = "A"
        $script:sync.ActiveJobToken = "t"
        $null = Clear-WinUtilActiveJob -Token "t"
        $script:sync.JobHandoff | Should -BeFalse

        $script:sync.JobQueue.Add([pscustomobject]@{ Id = "1"; Name = "Head" })
        $script:sync.ShuttingDown = $true
        $script:sync.ActiveJob = "A"
        $script:sync.ActiveJobToken = "t"
        $null = Clear-WinUtilActiveJob -Token "t"
        $script:sync.JobHandoff | Should -BeFalse
    }

    It "limpa a transferência em todas as saídas do despacho" {
        $queued = [pscustomobject]@{ Id = "1"; Name = "Head"; Description = ""; ScriptBlock = ""; Parameters = @{}; DisableAppList = $false }

        # fechando
        $script:sync.JobHandoff = $true
        $script:sync.ShuttingDown = $true
        Start-WinUtilNextQueuedJob
        $script:sync.JobHandoff | Should -BeFalse
        $script:sync.Remove("ShuttingDown")

        # fila vazia
        $script:sync.JobHandoff = $true
        Start-WinUtilNextQueuedJob
        $script:sync.JobHandoff | Should -BeFalse

        # vaga ocupada, a fila é mantida
        $script:sync.JobQueue.Add($queued)
        $script:sync.ActiveJob = "Other"
        $script:sync.JobHandoff = $true
        Start-WinUtilNextQueuedJob
        $script:sync.JobHandoff | Should -BeFalse
        $script:sync.JobQueue.Count | Should -Be 1

        # o job se recusa a iniciar porque o WinUtil começou a fechar após a remoção da fila
        $script:sync.ActiveJob = $null
        $script:sync.JobHandoff = $true
        $script:sync.ShuttingDown = $true
        Start-WinUtilJob -Name "Head" -FromQueue -ScriptBlock { } | Out-Null
        $script:sync.JobHandoff | Should -BeFalse
        $script:sync.ActiveJob | Should -BeNullOrEmpty
    }

    It "limpa a transferência quando o despacho não pode ser postado" {
        Mock Invoke-WPFUIThread { throw "dispatcher is gone" }
        $script:sync.JobQueue.Add([pscustomobject]@{ Id = "1"; Name = "Head" })
        $script:sync.ActiveJob = "A"
        $script:sync.ActiveJobToken = "t"

        $null = Clear-WinUtilActiveJob -Token "t"

        $script:sync.JobHandoff | Should -BeFalse
    }

    It "preserva escolhas de atualização separadas por outra ação (<Sequence>)" -TestCases @(
        @{ Sequence = @('WPFUpdatesdefault', 'WPFUpdatesdisable', 'WPFUpdatesdefault', 'WPFUpdatesdefault'); Expected = @('Default', 'Disable', 'Default') }
        @{ Sequence = @('WPFUpdatesdefault', 'WPFUpdatesdefault'); Expected = @('Default') }
    ) {
        param($Sequence, $Expected)
        . (Join-Path $script:repoRoot 'functions/public/Invoke-WPFButton.ps1')
        . (Join-Path $script:repoRoot 'functions/public/Invoke-WPFUpdatesdefault.ps1')
        . (Join-Path $script:repoRoot 'functions/public/Invoke-WPFUpdatesdisable.ps1')
        $script:sync.ActiveJob = 'Held'
        $script:sync.configs = @{ feature = @{} }
        $script:updateChoices = [System.Collections.Generic.List[string]]::new()
        Mock Confirm-WPFUpdatesdisable { $true }
        Mock Invoke-WPFUpdatesdefault { $script:updateChoices.Add('Default') }
        Mock Invoke-WPFUpdatesdisable { $script:updateChoices.Add('Disable') } -ParameterFilter { $Confirmed }

        foreach ($button in $Sequence) { Invoke-WPFButton -Button $button }

        $script:sync.JobQueue.Count | Should -Be $Expected.Count
        foreach ($queued in $script:sync.JobQueue) {
            $parameters = $queued.Parameters
            & ([scriptblock]::Create($queued.ScriptBlock)) @parameters
        }
        @($script:updateChoices) | Should -Be $Expected
        $script:updateChoices[$script:updateChoices.Count - 1] | Should -Be 'Default'
    }
    It "enfileira trabalho idêntico uma vez e ignora cliques repetidos" {
        $script:sync.ActiveJob = "Install"

        foreach ($click in 1..4) {
            Start-WinUtilJob -Name "Tweaks" -QueueIfBusy -Parameters @{ Tweaks = @("A", "B"); DnsProvider = "Default" } -ScriptBlock { } | Out-Null
        }

        $script:sync.JobQueue.Count | Should -Be 1
        Should -Invoke -CommandName Write-WinUtilLog -Times 3 -Exactly -ParameterFilter {
            $Component -eq "Tweaks" -and $Message -eq "Tweaks já está na fila, ignorado."
        }
        Should -Invoke -CommandName Show-WinUtilMessage -Times 0 -Exactly
    }

    It "trata os mesmos parâmetros dados em ordem de chave diferente como idênticos" {
        $script:sync.ActiveJob = "Install"

        Start-WinUtilJob -Name "Tweaks" -QueueIfBusy -Parameters ([ordered]@{ A = 1; B = 2 }) -ScriptBlock { } | Out-Null
        Start-WinUtilJob -Name "Tweaks" -QueueIfBusy -Parameters ([ordered]@{ B = 2; A = 1 }) -ScriptBlock { } | Out-Null

        $script:sync.JobQueue.Count | Should -Be 1
    }

    It "enfileira o mesmo nome novamente quando a seleção difere" {
        $script:sync.ActiveJob = "Install"

        Start-WinUtilJob -Name "Tweaks" -QueueIfBusy -Parameters @{ Tweaks = @("A") } -ScriptBlock { } | Out-Null
        Start-WinUtilJob -Name "Tweaks" -QueueIfBusy -Parameters @{ Tweaks = @("A", "B") } -ScriptBlock { } | Out-Null
        Start-WinUtilJob -Name "Undo tweaks" -QueueIfBusy -Parameters @{ Tweaks = @("A") } -ScriptBlock { } | Out-Null

        $script:sync.JobQueue.Count | Should -Be 3
    }

    It "não compara com o job em execução" {
        Start-WinUtilJob -Name "Tweaks" -QueueIfBusy -Parameters @{ Tweaks = @("A") } -ScriptBlock { } | Out-Null
        $script:sync.ActiveJob | Should -Be "Tweaks"

        Start-WinUtilJob -Name "Tweaks" -QueueIfBusy -Parameters @{ Tweaks = @("A") } -ScriptBlock { } | Out-Null
        Start-WinUtilJob -Name "Tweaks" -QueueIfBusy -Parameters @{ Tweaks = @("A") } -ScriptBlock { } | Out-Null

        $script:sync.JobQueue.Count | Should -Be 1
    }

    It "enfileira sem a verificação de duplicata quando os parâmetros não podem ser serializados" {
        Mock ConvertTo-Json { throw "cannot serialise" }
        $script:sync.ActiveJob = "Install"

        Start-WinUtilJob -Name "Tweaks" -QueueIfBusy -Parameters @{ Tweaks = @("A") } -ScriptBlock { } | Out-Null
        Start-WinUtilJob -Name "Tweaks" -QueueIfBusy -Parameters @{ Tweaks = @("A") } -ScriptBlock { } | Out-Null

        $script:sync.JobQueue.Count | Should -Be 2
        Should -Invoke -CommandName Write-WinUtilLog -Times 2 -Exactly -ParameterFilter {
            $Level -eq "WARN" -and $Message -like "Não foi possível comparar Tweaks*"
        }
    }

    It "faz as ações do usuário aderirem e mantém os jobs ISO e USB recusando" {
        foreach ($path in @(
            "functions\public\Invoke-WPFInstall.ps1", "functions\public\Invoke-WPFUnInstall.ps1",
            "functions\public\Invoke-WPFAppxInstall.ps1", "functions\public\Invoke-WPFAppxRemoval.ps1",
            "functions\public\Invoke-WPFtweaksbutton.ps1", "functions\public\Invoke-WPFundoall.ps1",
            "functions\public\Invoke-WPFFeatureInstall.ps1", "functions\public\Invoke-WPFButton.ps1"
        )) {
            (Get-Content -Path (Join-Path $script:repoRoot $path) -Raw) | Should -Match 'Start-WinUtilJob [^\r\n]*-QueueIfBusy' -Because $path
        }
        foreach ($path in @("functions\private\Invoke-WinUtilISO.ps1", "functions\private\Invoke-WinUtilISOUSB.ps1")) {
            (Get-Content -Path (Join-Path $script:repoRoot $path) -Raw) | Should -Not -Match 'QueueIfBusy' -Because $path
        }
    }
}

Describe "Fechamento com jobs enfileirados" {
    BeforeEach {
        $script:sync = [Hashtable]::Synchronized(@{
            ActiveJob = "Install"
            JobQueue = [System.Collections.Generic.List[object]]::new()
        })
        Mock Write-WinUtilLog { }
    }

    AfterEach {
        Remove-Variable -Name sync -Scope Script -ErrorAction SilentlyContinue
    }

    It "mantém o trabalho enfileirado durante o prompt de fechamento com job em execução e aplica <Answer> antes de retomar" -TestCases @(
        @{ Answer = 'Cancel'; ExpectedStarts = 1 }
        @{ Answer = 'No'; ExpectedStarts = 0 }
        @{ Answer = 'Yes'; ExpectedStarts = 0 }
    ) {
        param($Answer, $ExpectedStarts)
        $script:postedHandoffs = [Collections.Generic.List[scriptblock]]::new()
        $script:sync.ActiveJobToken = 'running'
        $script:sync.JobQueue.Add([pscustomobject]@{ Id = 'next'; Name = 'Next'; ScriptBlock = ''; Parameters = @{}; DisableAppList = $false })
        Mock Start-WinUtilJob {}
        Mock Request-WinUtilWindowClose {}
        Mock Write-Host {}
        Mock Invoke-WPFUIThread { $script:postedHandoffs.Add($ScriptBlock) }
        Mock Show-WinUtilMessage {
            $script:sync.JobClosePromptOpen | Should -BeTrue
            # Uma pergunta modal real bombeia o dispatcher enquanto o worker termina.
            $script:sync.ActiveJob = $null
            $script:sync.ActiveJobToken = $null
            $script:sync.JobHandoff = $true
            Start-WinUtilNextQueuedJob
            $script:sync.JobQueue.Count | Should -Be 1
            $script:sync.JobHandoff | Should -BeTrue
            return $Answer
        }

        Invoke-WinUtilCloseRequest -RunningJob 'Install' -QueuedCount 1

        $script:sync.JobClosePromptOpen | Should -BeFalse
        Should -Invoke Start-WinUtilJob -Times 0 -Exactly
        $script:postedHandoffs.Count | Should -Be 1
        foreach ($post in $script:postedHandoffs) { & $post }
        Should -Invoke Start-WinUtilJob -Times $ExpectedStarts -Exactly
    }

    It "informa ao usuário quantas operações enfileiradas serão descartadas" {
        Mock Show-WinUtilMessage { "Cancel" }

        Invoke-WinUtilCloseRequest -RunningJob "Install" -QueuedCount 2

        Should -Invoke -CommandName Show-WinUtilMessage -Times 1 -Exactly -ParameterFilter {
            $Message -like "*2 operação(ões) na fila serão descartadas*"
        }
    }

    It "não diz nada sobre a fila quando ela está vazia" {
        Mock Show-WinUtilMessage { "Cancel" }

        Invoke-WinUtilCloseRequest -RunningJob "Install"

        Should -Invoke -CommandName Show-WinUtilMessage -Times 1 -Exactly -ParameterFilter {
            $Message -notlike "*queued*"
        }
    }

    It "esvazia a fila e informa quantos itens descartou" {
        $script:sync.JobQueue.Add([pscustomobject]@{ Id = "1"; Name = "A" })
        $script:sync.JobQueue.Add([pscustomobject]@{ Id = "2"; Name = "B" })

        Clear-WinUtilJobQueue | Should -Be 2

        $script:sync.JobQueue.Count | Should -Be 0
        Should -Invoke -CommandName Write-WinUtilLog -Times 1 -Exactly -ParameterFilter {
            $Message -like "Descartados 2 job(s) enfileirado(s)*"
        }
    }

    It "faz o manipulador de fechamento da janela passar a contagem e limpar a fila após o prompt" {
        $source = Get-Content (Join-Path $script:repoRoot "functions\private\Start-WinUtilUserInterface.ps1") -Raw

        $source | Should -Match 'Invoke-WinUtilCloseRequest -RunningJob \$runningJob -QueuedCount \$sync\.JobQueue\.Count'
        $source.IndexOf('Clear-WinUtilJobQueue') | Should -BeGreaterThan $source.IndexOf('Invoke-WinUtilCloseRequest -RunningJob')
    }

    It "pergunta apenas se deseja descartar quando nada está em execução e fecha ao responder sim" {
        $script:sync.ActiveJob = $null
        Mock Show-WinUtilMessage { "Yes" }
        Mock Request-WinUtilWindowClose { }

        Invoke-WinUtilCloseRequest -RunningJob "Queued operations" -QueuedCount 2

        Should -Invoke -CommandName Show-WinUtilMessage -Times 1 -Exactly -ParameterFilter {
            $Button -eq "YesNo" -and $Message -like "Nada está em execução. 2 operação(ões) na fila serão descartadas*"
        }
        $script:sync.ForceClose | Should -BeTrue
        $script:sync.FinishInConsole | Should -Not -BeTrue
        Should -Invoke -CommandName Request-WinUtilWindowClose -Times 1 -Exactly
    }

    It "desliga a fila antes de postar o fechamento aceito de apenas enfileirados" {
        $script:sync.ActiveJob = $null
        $script:sync.JobHandoff = $true
        $script:sync.JobQueue.Add([pscustomobject]@{ Id = "1"; Name = "Head" })
        $script:sync.JobQueue.Add([pscustomobject]@{ Id = "2"; Name = "Next" })
        Mock Show-WinUtilMessage { "Yes" }
        $script:atClose = $null
        Mock Request-WinUtilWindowClose {
            $script:atClose = @{ Shutting = $script:sync.ShuttingDown; Queued = $script:sync.JobQueue.Count; Handoff = $script:sync.JobHandoff }
        }

        Invoke-WinUtilCloseRequest -RunningJob "Queued operations" -QueuedCount 2

        $script:atClose.Shutting | Should -BeTrue
        $script:atClose.Queued | Should -Be 0
        $script:atClose.Handoff | Should -BeFalse
    }

    It "recusa um job que tenta iniciar após o fechamento de apenas enfileirados ser aceito" {
        Mock Show-WinUtilMessage { "Yes" }
        Mock Request-WinUtilWindowClose { }
        $script:sync.ActiveJob = $null
        Invoke-WinUtilCloseRequest -RunningJob "Queued operations" -QueuedCount 1
        Mock Invoke-WPFRunspace { }
        Mock Step-WinUtilJob { }
        Mock Invoke-WPFUIThread { }

        Start-WinUtilJob -Name "Late" -QueueIfBusy -ScriptBlock { } | Out-Null

        $script:sync.ActiveJob | Should -BeNullOrEmpty
        $script:sync.JobQueue.Count | Should -Be 0
        Should -Invoke -CommandName Invoke-WPFRunspace -Times 0 -Exactly
    }

    It "mantém a janela aberta e a fila quando o fechamento de apenas enfileirados é recusado" {
        $script:sync.ActiveJob = $null
        Mock Show-WinUtilMessage { "No" }
        Mock Request-WinUtilWindowClose { }

        Invoke-WinUtilCloseRequest -RunningJob "Queued operations" -QueuedCount 2

        $script:sync.ForceClose | Should -Not -BeTrue
        Should -Invoke -CommandName Request-WinUtilWindowClose -Times 0 -Exactly
    }

    It "desliga a fila antes de postar o fechamento de parar o job, e nada inicia depois disso" {
        $script:sync.JobHandoff = $true
        $script:sync.JobQueue.Add([pscustomobject]@{ Id = "1"; Name = "Head"; Description = ""; ScriptBlock = ""; Parameters = @{}; DisableAppList = $false })
        Mock Show-WinUtilMessage { "No" }
        Mock Step-WinUtilJob { }
        Mock Update-WinUtilJobQueueUI { }
        Mock Start-WinUtilJob { }
        $script:atClose = $null
        Mock Request-WinUtilWindowClose {
            $script:atClose = @{ Shutting = $script:sync.ShuttingDown; Queued = $script:sync.JobQueue.Count; Handoff = $script:sync.JobHandoff }
        }

        Invoke-WinUtilCloseRequest -RunningJob "Install" -QueuedCount 1

        $script:atClose.Shutting | Should -BeTrue
        $script:atClose.Queued | Should -Be 0
        $script:atClose.Handoff | Should -BeFalse
        $script:sync.ForceClose | Should -BeTrue

        # o job em execução termina após a resposta e sua transferência não encontra nada para iniciar
        $script:sync.ActiveJob = $null
        Start-WinUtilNextQueuedJob
        Should -Invoke -CommandName Start-WinUtilJob -Times 0 -Exactly
    }

    It "não mexe na fila nem nas flags quando o fechamento é cancelado ou entrega o job ao console" {
        $script:sync.JobHandoff = $true
        $script:sync.JobQueue.Add([pscustomobject]@{ Id = "1"; Name = "Head" })
        Mock Request-WinUtilWindowClose { }
        Mock Write-Host { }

        Mock Show-WinUtilMessage { "Cancel" }
        Invoke-WinUtilCloseRequest -RunningJob "Install" -QueuedCount 1
        Mock Show-WinUtilMessage { "Yes" }
        Invoke-WinUtilCloseRequest -RunningJob "Install" -QueuedCount 1

        $script:sync.ShuttingDown | Should -Not -BeTrue
        $script:sync.JobQueue.Count | Should -Be 1
        $script:sync.JobHandoff | Should -BeTrue
    }

    It "pergunta novamente sobre o job em execução quando um job enfileirado iniciou durante o prompt" {
        $script:sync.ActiveJob = $null
        $script:sync.JobQueue.Add([pscustomobject]@{ Id = "1"; Name = "Head" })
        $script:asked = 0
        Mock Show-WinUtilMessage {
            $script:asked++
            if ($script:asked -eq 1) { $script:sync.ActiveJob = "Head"; return "Yes" }
            return "Cancel"
        }
        Mock Request-WinUtilWindowClose { }

        Invoke-WinUtilCloseRequest -RunningJob "Queued operations" -QueuedCount 2

        Should -Invoke -CommandName Show-WinUtilMessage -Times 2 -Exactly
        Should -Invoke -CommandName Show-WinUtilMessage -Times 1 -Exactly -ParameterFilter { $Title -eq "Head ainda está em execução" }
        $script:sync.ForceClose | Should -Not -BeTrue
        $script:sync.ShuttingDown | Should -Not -BeTrue
        $script:sync.JobQueue.Count | Should -Be 1
        Should -Invoke -CommandName Request-WinUtilWindowClose -Times 0 -Exactly
    }

    It "faz o manipulador de fechamento perguntar sobre trabalho enfileirado mesmo sem nada em execução" {
        $source = Get-Content (Join-Path $script:repoRoot "functions\private\Start-WinUtilUserInterface.ps1") -Raw

        $source | Should -Match '\(\$sync\.ActiveJob -or \$sync\.JobQueue\.Count -gt 0\) -and -not \$sync\.ForceClose'
    }
}
