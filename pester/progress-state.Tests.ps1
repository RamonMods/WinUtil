#===========================================================================
# Testes - A barra de progresso reflete como a execução terminou
#===========================================================================

BeforeAll {
    $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName WindowsBase

    . (Join-Path $script:repoRoot "functions\private\Step-WinUtilJob.ps1")
    . (Join-Path $script:repoRoot "functions\private\Set-WinUtilWorkingView.ps1")

    function Test-WinUtilUIAlive { return $true }
    function Write-WinUtilConsoleProgress { param([string]$Status, [int]$Percent) }
    function Write-WinUtilLog { param($Message, $Level, $Component) }
    function Set-WinUtilTaskbaritem { param($state, $overlay, $value) }
    function Invoke-WPFUIThread {
        param([scriptblock]$ScriptBlock, [hashtable]$Parameters, [switch]$Async, [switch]$PassThru)
        & $ScriptBlock @Parameters
    }

    function script:New-ProgressFixture {
        $bar = New-Object System.Windows.Controls.ProgressBar
        # os pincéis que a camada de trabalhos aponta para o preenchimento, resolvíveis pelo próprio controle
        $bar.Resources.Add("ProgressBarForegroundColor", [System.Windows.Media.Brushes]::LimeGreen)
        $bar.Resources.Add("ProgressBarErrorColor", [System.Windows.Media.Brushes]::Red)
        $bar.Resources.Add("ProgressBarWarningColor", [System.Windows.Media.Brushes]::Orange)

        $global:sync = [hashtable]::Synchronized(@{
            WPFTweaksProgressBar   = (New-Object System.Windows.Controls.Border)
            WPFTweaksProgressLabel = (New-Object System.Windows.Controls.TextBlock)
            WPFTweaksProgressValue = $bar
            Form = [pscustomobject]@{ TaskbarItemInfo = [pscustomobject]@{ ProgressValue = 0 } }
        })
        return $bar
    }
}

Describe "Cor de progresso de Step-WinUtilJob" {
    It "preenche de verde enquanto a execução ocorre normalmente" {
        $bar = New-ProgressFixture

        Step-WinUtilJob -Status "working" -Percent 40 -State "Normal"

        $bar.Foreground | Should -Be ([System.Windows.Media.Brushes]::LimeGreen)
    }

    It "fica vermelha quando a execução falha" {
        $bar = New-ProgressFixture

        Step-WinUtilJob -Status "Tweaks failed" -Percent 100 -State "Error"

        $bar.Foreground | Should -Be ([System.Windows.Media.Brushes]::Red)
    }

    It "avisa em vez de informar sucesso quando a execução termina com erros" {
        $bar = New-ProgressFixture

        # este é o caso que parecia uma conclusão limpa: barra cheia, cor normal
        Step-WinUtilJob -Status "Tweaks finished with 2 error(s)" -Percent 100 -State "Paused"

        $bar.Foreground | Should -Be ([System.Windows.Media.Brushes]::Orange)
        $bar.Foreground | Should -Not -Be ([System.Windows.Media.Brushes]::LimeGreen)
    }

    It "volta à cor normal quando a próxima execução começa" {
        $bar = New-ProgressFixture

        Step-WinUtilJob -Status "Tweaks failed" -Percent 100 -State "Error"
        Step-WinUtilJob -Status "starting" -Percent 0 -State "Normal"

        $bar.Foreground | Should -Be ([System.Windows.Media.Brushes]::LimeGreen)
    }

    It "espelha o status em cada rótulo de trabalho visível" {
        $null = New-ProgressFixture
        $global:sync["WPFInstallWorkingPanel"] = New-Object System.Windows.Controls.Grid
        $global:sync["WPFInstallWorkingLabel"] = New-Object System.Windows.Controls.TextBlock
        $global:sync["WPFTweaksWorkingPanel"] = New-Object System.Windows.Controls.Grid
        $global:sync["WPFTweaksWorkingLabel"] = New-Object System.Windows.Controls.TextBlock
        $global:sync["WPFInstallWorkingPanel"].Visibility = [System.Windows.Visibility]::Visible
        $global:sync["WPFTweaksWorkingPanel"].Visibility = [System.Windows.Visibility]::Visible

        Step-WinUtilJob -Status "Installing vlc (2/7)" -Percent 20

        $global:sync["WPFInstallWorkingLabel"].Text | Should -Be "Installing vlc (2/7)"
        $global:sync["WPFTweaksWorkingLabel"].Text | Should -Be "Installing vlc (2/7)"
    }

    It "não altera rótulos de trabalho ocultos" {
        $null = New-ProgressFixture
        $global:sync["WPFInstallWorkingPanel"] = New-Object System.Windows.Controls.Grid
        $global:sync["WPFInstallWorkingLabel"] = New-Object System.Windows.Controls.TextBlock
        $global:sync["WPFTweaksWorkingPanel"] = New-Object System.Windows.Controls.Grid
        $global:sync["WPFTweaksWorkingLabel"] = New-Object System.Windows.Controls.TextBlock
        $global:sync["WPFInstallWorkingPanel"].Visibility = [System.Windows.Visibility]::Collapsed
        $global:sync["WPFTweaksWorkingPanel"].Visibility = [System.Windows.Visibility]::Collapsed
        $global:sync["WPFInstallWorkingLabel"].Text = "Installing..."
        $global:sync["WPFTweaksWorkingLabel"].Text = "Applying tweaks..."

        Step-WinUtilJob -Status "Installing vlc (2/7)" -Percent 20

        $global:sync["WPFInstallWorkingLabel"].Text | Should -Be "Installing..."
        $global:sync["WPFTweaksWorkingLabel"].Text | Should -Be "Applying tweaks..."
    }

    It "troca a lista de aplicativos pela visualização de trabalho e volta" {
        $null = New-ProgressFixture
        $global:sync["WPFInstallWorkingPanel"] = New-Object System.Windows.Controls.Grid
        $global:sync["WPFInstallContentGrid"] = New-Object System.Windows.Controls.Grid
        $global:sync["WPFSearchChips"] = New-Object System.Windows.Controls.WrapPanel
        $global:sync["WPFInstallWorkingLabel"] = New-Object System.Windows.Controls.TextBlock
        $global:sync["WPFInstallWorkingPanel"].Visibility = [System.Windows.Visibility]::Collapsed

        Set-WinUtilWorkingView -Area "Install" -Working $true -Label "Installing apps..."

        $global:sync["WPFInstallWorkingPanel"].Visibility | Should -Be ([System.Windows.Visibility]::Visible)
        $global:sync["WPFInstallContentGrid"].Visibility | Should -Be ([System.Windows.Visibility]::Collapsed)
        $global:sync["WPFSearchChips"].Visibility | Should -Be ([System.Windows.Visibility]::Collapsed)
        $global:sync["WPFInstallWorkingLabel"].Text | Should -Be "Installing apps..."

        Set-WinUtilWorkingView -Area "Install" -Working $false

        $global:sync["WPFInstallWorkingPanel"].Visibility | Should -Be ([System.Windows.Visibility]::Collapsed)
        $global:sync["WPFInstallContentGrid"].Visibility | Should -Be ([System.Windows.Visibility]::Visible)
        $global:sync["WPFSearchChips"].Visibility | Should -Be ([System.Windows.Visibility]::Visible)
    }

    It "troca a lista de ajustes e a barra de ações pela visualização de trabalho e volta" {
        $null = New-ProgressFixture
        $global:sync["WPFTweaksWorkingPanel"] = New-Object System.Windows.Controls.Grid
        $global:sync["WPFTweaksContentScroll"] = New-Object System.Windows.Controls.ScrollViewer
        $global:sync["WPFTweaksActionBar"] = New-Object System.Windows.Controls.Border
        $global:sync["WPFTweaksWorkingLabel"] = New-Object System.Windows.Controls.TextBlock
        $global:sync["WPFTweaksWorkingPanel"].Visibility = [System.Windows.Visibility]::Collapsed

        Set-WinUtilWorkingView -Area "Tweaks" -Working $true -Label "Applying tweaks..."

        $global:sync["WPFTweaksWorkingPanel"].Visibility | Should -Be ([System.Windows.Visibility]::Visible)
        $global:sync["WPFTweaksContentScroll"].Visibility | Should -Be ([System.Windows.Visibility]::Collapsed)
        $global:sync["WPFTweaksActionBar"].Visibility | Should -Be ([System.Windows.Visibility]::Collapsed)
        $global:sync["WPFTweaksWorkingLabel"].Text | Should -Be "Applying tweaks..."

        Set-WinUtilWorkingView -Area "Tweaks" -Working $false

        $global:sync["WPFTweaksWorkingPanel"].Visibility | Should -Be ([System.Windows.Visibility]::Collapsed)
        $global:sync["WPFTweaksContentScroll"].Visibility | Should -Be ([System.Windows.Visibility]::Visible)
        $global:sync["WPFTweaksActionBar"].Visibility | Should -Be ([System.Windows.Visibility]::Visible)
    }
}
