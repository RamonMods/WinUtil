#===========================================================================
# Testes - Fechamento enquanto algo está em execução

BeforeAll {
    $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
    $script:functionRoot = Join-Path $script:repoRoot "functions"

    . (Join-Path $script:functionRoot "private\Stop-WinUtilActiveWork.ps1")

    function Test-WinUtilUIAlive { $null -ne $sync.Form -and $null -ne $sync.Form.Dispatcher }

    . (Join-Path $script:functionRoot "private\Invoke-WinUtilCloseRequest.ps1")
    . (Join-Path $script:functionRoot "private\Start-WinUtilNextQueuedJob.ps1")

    function Write-WinUtilLog { param($Level, $Component, $Message, [switch]$Detail) }
    function Step-WinUtilJob { param($Status, $Percent, $State, $Overlay, [switch]$Hide) }
    function Show-WinUtilMessage { param($Message, $Title, $Button, $Icon) }
    function Complete-WinUtilConsoleProgress { }
}

Describe "Acompanhamento do que está em execução" {
    BeforeEach {
        $global:sync = [hashtable]::Synchronized(@{})
    }

    It "não relata nada para parar antes de qualquer execução" {
        # @($null) é um array de um elemento contendo nulo, então uma coleção ausente era lida como um
        # item em execução e o fechamento registrava trabalho que não existia
        Stop-WinUtilActiveWork | Should -BeTrue
    }

    It "cria a coleção no primeiro uso" {
        $shell = [powershell]::Create()
        try {
            Register-WinUtilActiveShell -PowerShell $shell
            @($sync.ActiveShells).Count | Should -Be 1
        } finally {
            $shell.Dispose()
        }
    }

    It "descarta instâncias que terminaram em vez de mantê-las durante a sessão" {
        $first = [powershell]::Create()
        $second = [powershell]::Create()
        try {
            Register-WinUtilActiveShell -PowerShell $first
            # a primeira está como NotStarted, então registrar outra deve removê-la
            Register-WinUtilActiveShell -PowerShell $second

            @($sync.ActiveShells).Count | Should -Be 1
            [object]::ReferenceEquals(@($sync.ActiveShells)[0], $second) | Should -BeTrue
        } finally {
            $first.Dispose(); $second.Dispose()
        }
    }

    It "sobrevive a uma instância que foi descartada enquanto era usada" {
        $shell = [powershell]::Create()
        Register-WinUtilActiveShell -PowerShell $shell
        $shell.Dispose()

        { Stop-WinUtilActiveWork -TimeoutSeconds 1 } | Should -Not -Throw
    }

    It "trata uma invocação em parada como ativa até atingir um estado terminal" {
        $shell = [pscustomobject]@{
            InvocationStateInfo = [pscustomobject]@{
                State = [System.Management.Automation.PSInvocationState]::Stopping
            }
        }

        Test-WinUtilShellRunning $shell | Should -BeTrue
    }

    It "para um trabalho que está realmente em execução" {
        $pool = [runspacefactory]::CreateRunspacePool(1, 2)
        $pool.Open()
        $shell = [powershell]::Create()
        $shell.RunspacePool = $pool
        $null = $shell.AddScript('Start-Sleep -Seconds 30')
        $null = $shell.BeginInvoke()

        Register-WinUtilActiveShell -PowerShell $shell
        try {
            $clock = [Diagnostics.Stopwatch]::StartNew()
            $stopped = Stop-WinUtilActiveWork -TimeoutSeconds 10
            $clock.Stop()

            $stopped | Should -BeTrue
            $clock.Elapsed.TotalSeconds | Should -BeLessThan 10
            $shell.InvocationStateInfo.State | Should -Not -Be ([System.Management.Automation.PSInvocationState]::Running)
        } finally {
            try { $shell.Dispose() } catch { }
            $pool.Close(); $pool.Dispose()
        }
    }

    It "desiste em vez de manter a janela aberta indefinidamente" {
        # um worker dentro de um comando que nunca retorna não pode ser parado e não deve impedir o
        # fechamento da janela
        $global:sync.ActiveShells = [System.Collections.ArrayList]::Synchronized([System.Collections.ArrayList]::new())
        $stubborn = [pscustomobject]@{
            InvocationStateInfo = [pscustomobject]@{ State = [System.Management.Automation.PSInvocationState]::Running }
        }
        $stubborn | Add-Member -MemberType ScriptMethod -Name BeginStop -Value { param($a, $b) $null }
        $null = $sync.ActiveShells.Add($stubborn)

        $clock = [Diagnostics.Stopwatch]::StartNew()
        $result = Stop-WinUtilActiveWork -TimeoutSeconds 1
        $clock.Stop()

        $result | Should -BeFalse
        $clock.Elapsed.TotalSeconds | Should -BeLessThan 5
    }
}

Describe "A pergunta de fechamento" {
    BeforeEach {
        $global:sync = [hashtable]::Synchronized(@{})
        $sync.ActiveJob = "Install"
        $sync.JobQueue = [System.Collections.Generic.List[object]]::new()
        Mock Write-WinUtilLog { }
        Mock Step-WinUtilJob { }
    }

    It "entrega o job ao console e fecha a janela quando solicitado a deixá-lo terminar" {
        Mock Show-WinUtilMessage { "Yes" }
        Mock Write-Host { }

        Invoke-WinUtilCloseRequest -RunningJob "Install"

        # a janela fecha agora; o job continua sem ela
        $sync.FinishInConsole | Should -BeTrue
        $sync.ForceClose | Should -BeTrue
    }

    It "mantém a janela aberta quando o fechamento é cancelado" {
        Mock Show-WinUtilMessage { "Cancel" }

        Invoke-WinUtilCloseRequest -RunningJob "Install"

        $sync.FinishInConsole | Should -Not -BeTrue
        $sync.ForceClose | Should -Not -BeTrue
    }

    It "fecha antes de a thread principal parar o pool de workers" {
        Mock Show-WinUtilMessage { "No" }
        Mock Request-WinUtilWindowClose { }

        Invoke-WinUtilCloseRequest -RunningJob "Install"

        $sync.ForceClose | Should -BeTrue
        Should -Invoke -CommandName Request-WinUtilWindowClose -Times 1 -Exactly
        (Get-Content (Join-Path $script:repoRoot "functions\private\Invoke-WinUtilCloseRequest.ps1") -Raw) |
            Should -Not -Match 'Request-WinUtilWindowClose\s+-Before'
    }

    It "nunca encerra o pool de workers no manipulador de fechamento da janela" {
        (Get-Content (Join-Path $script:repoRoot "functions\private\Start-WinUtilUserInterface.ps1") -Raw) |
            Should -Not -Match 'Close-WinUtilRunspacePool'
    }



    It "oferece as três opções" {
        Mock Show-WinUtilMessage { "Cancel" }

        Invoke-WinUtilCloseRequest -RunningJob "Install"

        Should -Invoke -CommandName Show-WinUtilMessage -Times 1 -Exactly -ParameterFilter {
            $Button -eq "YesNoCancel" -and $Message -like "*Install*" -and $Message -like "*console*"
        }
    }

    It "informa o limite de espera imposto pela transferência para o console" {
        # o aviso cita o padrão real antes de solicitar a parada
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            (Join-Path $script:repoRoot "functions\private\Invoke-WinUtilCloseRequest.ps1"), [ref]$tokens, [ref]$errors)
        $wait = $ast.Find({
                $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $args[0].Name -eq "Wait-WinUtilRemainingWork"
            }, $true)
        $limit = $wait.Body.ParamBlock.Parameters[0].DefaultValue.Extent.Text

        $script:closeMessage = $null
        Mock Show-WinUtilMessage { $script:closeMessage = $Message; "Cancel" }

        Invoke-WinUtilCloseRequest -RunningJob "Install"

        $script:closeMessage | Should -Match "até $limit"
    }
}

Describe "Espera por trabalho que sobreviveu à janela" {
    BeforeEach {
        $global:sync = [hashtable]::Synchronized(@{})
        Mock Write-WinUtilLog { }
        Mock Write-Host { }
    }

    It "retorna imediatamente quando nada ficou em execução" {
        $sync.FinishInConsole = $true
        $sync.ActiveJob = $null

        { Wait-WinUtilRemainingWork } | Should -Not -Throw
    }

    It "não espera quando a janela foi fechada normalmente" {
        # um job não pode estar ativo sem FinishInConsole, mas a proteção deve valer de qualquer forma
        $sync.FinishInConsole = $false
        $sync.ActiveJob = "Install"

        $clock = [Diagnostics.Stopwatch]::StartNew()
        Wait-WinUtilRemainingWork
        $clock.Elapsed.TotalSeconds | Should -BeLessThan 2
    }

    It "espera até que o job limpe a sinalização de ocupado" {
        $sync.FinishInConsole = $true
        $sync.ActiveJob = "Install"

        # outra coisa a limpa, como faz o finally de um worker
        $timer = New-Object System.Timers.Timer
        $timer.Interval = 700
        $timer.AutoReset = $false
        Register-ObjectEvent -InputObject $timer -EventName Elapsed -Action { $global:sync.ActiveJob = $null } | Out-Null
        $timer.Start()

        $clock = [Diagnostics.Stopwatch]::StartNew()
        Wait-WinUtilRemainingWork
        $clock.Stop()

        $sync.ActiveJob | Should -BeNullOrEmpty
        $clock.Elapsed.TotalMilliseconds | Should -BeGreaterThan 500
        $timer.Dispose()
        Get-EventSubscriber | Where-Object { $_.SourceObject -is [System.Timers.Timer] } | Unregister-Event
    }

    It "desiste em vez de manter o processo vivo indefinidamente" {
        $sync.FinishInConsole = $true
        $sync.ActiveJob = "Install"

        $clock = [Diagnostics.Stopwatch]::StartNew()
        Wait-WinUtilRemainingWork -TimeoutMinutes 0.02
        $clock.Stop()

        # esperou em vez de retornar imediatamente e desistiu em vez de esperar indefinidamente
        $clock.Elapsed.TotalSeconds | Should -BeGreaterThan 0.5
        $clock.Elapsed.TotalSeconds | Should -BeLessThan 10
        $sync.ActiveJob | Should -Be "Install"
    }
}
