#===========================================================================
# Testes - Trabalho especulativo dá lugar ao usuário

BeforeAll {
    $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
    $script:functionRoot = Join-Path $script:repoRoot "functions"

    . (Join-Path $script:functionRoot "private\Test-WinUtilDeferBackgroundWork.ps1")

    function Test-WinUtilUIAlive { $null -ne $sync.Form -and $null -ne $sync.Form.Dispatcher }

}

Describe "Test-WinUtilDeferBackgroundWork" {
    BeforeEach {
        $global:sync = [hashtable]::Synchronized(@{})
        $sync.currentTab = "Install"
        $sync.LastInputAt = [datetime]::MinValue
    }

    It "executa o trabalho quando o usuário está ocioso e a aba é a que está sendo desenhada" {
        Test-WinUtilDeferBackgroundWork -RequiresTab "Install" | Should -BeFalse
    }

    It "aguarda enquanto o usuário está interagindo" {
        # a prioridade em segundo plano coloca o trabalho atrás da entrada de dados na fila, mas não torna a parte
        # já em execução interrompível
        $sync.LastInputAt = [datetime]::Now

        Test-WinUtilDeferBackgroundWork | Should -BeTrue
    }

    It "executa novamente após a interação ter passado" {
        $sync.LastInputAt = [datetime]::Now.AddSeconds(-2)

        Test-WinUtilDeferBackgroundWork | Should -BeFalse
    }

    It "aguarda quando o trabalho é para uma aba que não está na tela" {
        $sync.currentTab = "Tweaks"

        Test-WinUtilDeferBackgroundWork -RequiresTab "Install" | Should -BeTrue
    }

    It "não se importa com qual aba está aberta para trabalho que não pertence a nenhuma aba" {
        $sync.currentTab = "Tweaks"

        Test-WinUtilDeferBackgroundWork | Should -BeFalse
    }

    It "lida com o carimbo de data/hora nunca ter sido definido" {
        $sync.Remove("LastInputAt")

        { Test-WinUtilDeferBackgroundWork } | Should -Not -Throw
        Test-WinUtilDeferBackgroundWork | Should -BeFalse
    }
}

Describe "Invoke-WinUtilWhenIdle" {
    BeforeEach {
        Add-Type -AssemblyName WindowsBase
        $global:sync = [hashtable]::Synchronized(@{})
        $global:sync.Form = [pscustomobject]@{ Dispatcher = [System.Windows.Threading.Dispatcher]::CurrentDispatcher }
    }

    It "realmente executa o callback" {
        # uma nova tentativa que nunca dispara abandona o que foi adiado, e nada reporta isso
        $global:ranCount = 0
        Invoke-WinUtilWhenIdle -Callback { $global:ranCount++ } -DelayMilliseconds 20

        $frame = New-Object System.Windows.Threading.DispatcherFrame
        $guard = New-Object System.Windows.Threading.DispatcherTimer
        $guard.Interval = [timespan]::FromMilliseconds(20)
        $guard.Tag = @{ Frame = $frame; Clock = [Diagnostics.Stopwatch]::StartNew() }
        $guard.Add_Tick({
            param($eventSender)
            $t = [System.Windows.Threading.DispatcherTimer]$eventSender
            if ($global:ranCount -gt 0 -or $t.Tag.Clock.Elapsed.TotalSeconds -gt 3) {
                $t.Stop()
                $t.Tag.Frame.Continue = $false
            }
        })
        $guard.Start()
        [System.Windows.Threading.Dispatcher]::PushFrame($frame)

        $global:ranCount | Should -Be 1
    }

    It "executa o callback exatamente uma vez, não a cada tick" {
        $global:ranCount = 0
        Invoke-WinUtilWhenIdle -Callback { $global:ranCount++ } -DelayMilliseconds 20

        $frame = New-Object System.Windows.Threading.DispatcherFrame
        $stop = New-Object System.Windows.Threading.DispatcherTimer
        $stop.Interval = [timespan]::FromMilliseconds(300)
        $stop.Tag = $frame
        $stop.Add_Tick({
            param($eventSender)
            $t = [System.Windows.Threading.DispatcherTimer]$eventSender
            $t.Stop()
            $t.Tag.Continue = $false
        })
        $stop.Start()
        [System.Windows.Threading.Dispatcher]::PushFrame($frame)

        $global:ranCount | Should -Be 1
    }

    It "não faz nada quando a janela se foi" {
        $global:sync.Form = $null

        { Invoke-WinUtilWhenIdle -Callback { throw "should not run" } } | Should -Not -Throw
    }
}
