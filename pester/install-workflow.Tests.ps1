#===========================================================================
# Testes - Fluxos de instalação e desinstalação
#===========================================================================

BeforeAll {
    $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
    . (Join-Path $script:repoRoot "functions\private\Measure-WinUtilStep.ps1")

    . (Join-Path $script:repoRoot "functions\private\Get-WinUtilPackageLogSummary.ps1")
    . (Join-Path $script:repoRoot "functions\public\Invoke-WPFInstall.ps1")
    . (Join-Path $script:repoRoot "functions\public\Invoke-WPFUnInstall.ps1")

    function Show-WinUtilMessage {
        param($Message, $Title, $Button, $Icon)
    }
    function Start-WinUtilJob {
        param(
            [string]$Name,
            [scriptblock]$ScriptBlock,
            [hashtable]$Parameters,
            [string]$Description,
            [switch]$DisableAppList
        )
    }
    function Step-WinUtilJob {
        param([string]$Status, [int]$Percent, [string]$State, [string]$Overlay)
    }
    function Invoke-WPFRunspace {
        param($ArgumentList, $ParameterList, [scriptblock]$ScriptBlock)
    }
    function Get-WinUtilSelectedPackages {
        param($PackageList, [string]$Preference, [string]$Action)
    }
    function Install-WinUtilWinget { }
    function Install-WinUtilChoco { }
    function Install-WinUtilProgramWinget {
        param($Action, $Programs)
    }
    function Install-WinUtilProgramChoco {
        param($Action, $Programs)
    }
    function Complete-WinUtilPackageRun {
        param([string]$Action, [object[]]$Results)
    }
    function Invoke-WPFUIThread {
        param([scriptblock]$ScriptBlock, [hashtable]$Parameters, [switch]$Async)
    }
    function Write-WinUtilLog {
        param($Message, $Level, $Component)
    }

    function script:New-WinUtilPackage {
        param(
            [string]$Name = "Git",
            [string]$Winget = "Git.Git",
            [string]$Choco = "git"
        )

        [pscustomobject]@{
            Name = $Name
            Description = "$Name package"
            winget = $Winget
            choco = $Choco
        }
    }

    function script:New-WinUtilInstallTestContext {
        param(
            [bool]$ProcessRunning = $false,
            [object[]]$Packages = @()
        )

        $applications = @{}
        $selectedApps = [System.Collections.Generic.List[string]]::new()

        for ($i = 0; $i -lt $Packages.Count; $i++) {
            $key = "WPFInstallTest$i"
            $applications[$key] = $Packages[$i]
            $selectedApps.Add($key)
        }

        $script:sync = [Hashtable]::Synchronized(@{
            ProcessRunning = $ProcessRunning
            selectedApps = $selectedApps
            preferences = [pscustomobject]@{
                packagemanager = "Winget"
            }
            Form = [pscustomobject]@{
                Dispatcher = [pscustomobject]@{}
            }
            configs = @{
                applicationsHashtable = $applications
            }
        })
    }

    function script:New-WinUtilPackageSplit {
        param(
            [string[]]$Winget = @(),
            [string[]]$Choco = @()
        )

        $packages = @{}
        $packages["Winget"] = [System.Collections.Generic.List[string]]::new()
        $packages["Choco"] = [System.Collections.Generic.List[string]]::new()

        foreach ($package in $Winget) {
            $null = $packages["Winget"].Add($package)
        }

        foreach ($package in $Choco) {
            $null = $packages["Choco"].Add($package)
        }

        $packages
    }
}

Describe "Ponto de entrada de Invoke-WPFInstall" {
    BeforeEach {
        $script:package = New-WinUtilPackage
        New-WinUtilInstallTestContext -Packages @($script:package)
        $script:capturedInstallJob = $null

        Mock Show-WinUtilMessage { "OK" }
        Mock Start-WinUtilJob {
            $script:capturedInstallJob = [pscustomobject]@{
                Name = $Name
                ScriptBlock = $ScriptBlock
                Parameters = $Parameters
                Description = $Description
                DisableAppList = [bool]$DisableAppList
            }
        }
        Mock Write-WinUtilLog { }
    }

    AfterEach {
        Remove-Variable -Name sync -Scope Script -ErrorAction SilentlyContinue
        Remove-Variable -Name capturedInstallJob -Scope Script -ErrorAction SilentlyContinue
    }

    It "enfileira um job de instalação com a preferência de gerenciador de pacotes configurada" {
        Invoke-WPFInstall

        Should -Invoke -CommandName Start-WinUtilJob -Times 1 -Exactly -ParameterFilter {
            $Name -eq "Install" -and
                $ScriptBlock -is [scriptblock] -and
                $DisableAppList -and
                @($Parameters.PackagesToInstall).Count -eq 1 -and
                @($Parameters.PackagesToInstall)[0].winget -eq "Git.Git" -and
                $Parameters.ManagerPreference -eq "Winget"
        }
        Should -Invoke -CommandName Show-WinUtilMessage -Times 0 -Exactly
    }

    It "registra as identidades dos pacotes antes de enfileirar o job" {
        Invoke-WPFInstall

        Should -Invoke -CommandName Write-WinUtilLog -Times 1 -Exactly -ParameterFilter {
            $Component -eq "Install" -and
                $Message -eq "Install selected package(s): Git (winget: Git.Git)"
        }
    }

    It "enfileira o pacote explícito do popup de aplicativo antes dos aplicativos selecionados" {
        $explicitPackage = New-WinUtilPackage -Name "VLC" -Winget "VideoLAN.VLC" -Choco "vlc"

        Invoke-WPFInstall -PackagesToInstall $explicitPackage

        Should -Invoke -CommandName Start-WinUtilJob -Times 1 -Exactly -ParameterFilter {
            @($Parameters.PackagesToInstall).Count -eq 1 -and
                @($Parameters.PackagesToInstall)[0].winget -eq "VideoLAN.VLC"
        }
        Should -Invoke -CommandName Show-WinUtilMessage -Times 0 -Exactly
    }

    It "pergunta e sai quando nenhum pacote está selecionado" {
        New-WinUtilInstallTestContext

        Invoke-WPFInstall

        Should -Invoke -CommandName Show-WinUtilMessage -Times 1 -Exactly -ParameterFilter {
            $Message -eq "Please select the program(s) to install or upgrade." -and
                $Title -eq "WinUtil" -and
                $Button -eq "OK" -and
                $Icon -eq "Warning"
        }
        Should -Invoke -CommandName Start-WinUtilJob -Times 0 -Exactly
    }
}

Describe "Corpo do job de Invoke-WPFInstall" {
    BeforeEach {
        $script:package = New-WinUtilPackage
        New-WinUtilInstallTestContext -Packages @($script:package)
        $script:capturedInstallJob = $null

        Mock Show-WinUtilMessage { "OK" }
        Mock Start-WinUtilJob {
            $script:capturedInstallJob = [pscustomobject]@{
                ScriptBlock = $ScriptBlock
                Parameters = $Parameters
            }
        }
        Mock Get-WinUtilSelectedPackages {
            New-WinUtilPackageSplit -Winget @("Git.Git") -Choco @("vlc")
        }
        Mock Step-WinUtilJob { }
        Mock Install-WinUtilWinget { }
        Mock Install-WinUtilChoco { }
        Mock Install-WinUtilProgramWinget { }
        Mock Install-WinUtilProgramChoco { }
        Mock Write-WinUtilLog { }
        Mock Write-Host { }
    }

    AfterEach {
        Remove-Variable -Name sync -Scope Script -ErrorAction SilentlyContinue
        Remove-Variable -Name capturedInstallJob -Scope Script -ErrorAction SilentlyContinue
    }

    It "instala pacotes divididos entre winget e choco e relata o progresso" {
        Invoke-WPFInstall

        $jobParameters = $script:capturedInstallJob.Parameters
        & $script:capturedInstallJob.ScriptBlock @jobParameters

        Should -Invoke -CommandName Get-WinUtilSelectedPackages -Times 1 -Exactly -ParameterFilter {
            @($PackageList).Count -eq 1 -and $Preference -eq "Winget"
        }
        Should -Invoke -CommandName Install-WinUtilWinget -Times 1 -Exactly
        Should -Invoke -CommandName Install-WinUtilProgramWinget -Times 1 -Exactly -ParameterFilter {
            $Action -eq "Install" -and @($Programs)[0] -eq "Git.Git"
        }
        Should -Invoke -CommandName Install-WinUtilChoco -Times 1 -Exactly
        Should -Invoke -CommandName Install-WinUtilProgramChoco -Times 1 -Exactly -ParameterFilter {
            $Action -eq "Install" -and @($Programs)[0] -eq "vlc"
        }
        Should -Invoke -CommandName Step-WinUtilJob -Times 1 -Exactly -ParameterFilter {
            $Status -eq "Installed Git.Git (1/2)" -and $Percent -eq 50
        }
        Should -Invoke -CommandName Step-WinUtilJob -Times 1 -Exactly -ParameterFilter {
            $Status -eq "Installed Chocolatey packages (2/2)" -and $Percent -eq 100
        }
    }

    It "permite que uma falha apareça para que a camada de jobs possa tratá-la" {
        Mock Install-WinUtilProgramWinget { throw "winget failed" }

        Invoke-WPFInstall

        { $jobParameters = $script:capturedInstallJob.Parameters
        & $script:capturedInstallJob.ScriptBlock @jobParameters } |
            Should -Throw "winget failed"
    }
}

Describe "Ponto de entrada de Invoke-WPFUnInstall" {
    BeforeEach {
        $script:package = New-WinUtilPackage
        New-WinUtilInstallTestContext -Packages @($script:package)
        $script:capturedUninstallJob = $null

        Mock Show-WinUtilMessage { "Yes" }
        Mock Start-WinUtilJob {
            $script:capturedUninstallJob = [pscustomobject]@{
                Name = $Name
                ScriptBlock = $ScriptBlock
                Parameters = $Parameters
                DisableAppList = [bool]$DisableAppList
            }
        }
        Mock Write-WinUtilLog { }
    }

    AfterEach {
        Remove-Variable -Name sync -Scope Script -ErrorAction SilentlyContinue
        Remove-Variable -Name capturedUninstallJob -Scope Script -ErrorAction SilentlyContinue
    }

    It "confirma e enfileira um job de desinstalação com a preferência de gerenciador de pacotes configurada" {
        Invoke-WPFUnInstall

        Should -Invoke -CommandName Show-WinUtilMessage -Times 1 -Exactly -ParameterFilter {
            $Title -eq "Are you sure?" -and $Button -eq "YesNo"
        }
        Should -Invoke -CommandName Start-WinUtilJob -Times 1 -Exactly -ParameterFilter {
            $Name -eq "Uninstall" -and
                $ScriptBlock -is [scriptblock] -and
                $DisableAppList -and
                @($Parameters.PackagesToUninstall).Count -eq 1 -and
                @($Parameters.PackagesToUninstall)[0].winget -eq "Git.Git" -and
                $Parameters.ManagerPreference -eq "Winget"
        }
    }

    It "registra as identidades dos pacotes antes de enfileirar o job de desinstalação" {
        Invoke-WPFUnInstall

        Should -Invoke -CommandName Write-WinUtilLog -Times 1 -Exactly -ParameterFilter {
            $Component -eq "Uninstall" -and
                $Message -eq "Uninstall selected package(s): Git (winget: Git.Git)"
        }
    }

    It "pergunta e sai quando nenhum pacote está selecionado" {
        New-WinUtilInstallTestContext

        Invoke-WPFUnInstall

        Should -Invoke -CommandName Show-WinUtilMessage -Times 1 -Exactly -ParameterFilter {
            $Message -eq "Please select the program(s) to uninstall"
        }
        Should -Invoke -CommandName Start-WinUtilJob -Times 0 -Exactly
    }

    It "sai sem enfileirar a desinstalação quando a confirmação é recusada" {
        Mock Show-WinUtilMessage { "No" }

        Invoke-WPFUnInstall

        Should -Invoke -CommandName Start-WinUtilJob -Times 0 -Exactly
    }
}

Describe "Corpo do job de Invoke-WPFUnInstall" {
    BeforeEach {
        $script:package = New-WinUtilPackage
        New-WinUtilInstallTestContext -Packages @($script:package)
        $script:capturedUninstallJob = $null

        Mock Show-WinUtilMessage { "Yes" }
        Mock Start-WinUtilJob {
            $script:capturedUninstallJob = [pscustomobject]@{
                ScriptBlock = $ScriptBlock
                Parameters = $Parameters
            }
        }
        Mock Get-WinUtilSelectedPackages {
            New-WinUtilPackageSplit -Winget @("Git.Git") -Choco @("vlc")
        }
        Mock Step-WinUtilJob { }
        Mock Install-WinUtilProgramWinget { }
        Mock Install-WinUtilProgramChoco { }
        Mock Write-WinUtilLog { }
        Mock Write-Host { }
    }

    AfterEach {
        Remove-Variable -Name sync -Scope Script -ErrorAction SilentlyContinue
        Remove-Variable -Name capturedUninstallJob -Scope Script -ErrorAction SilentlyContinue
    }

    It "desinstala pacotes divididos entre winget e choco e relata o progresso" {
        Invoke-WPFUnInstall

        $jobParameters = $script:capturedUninstallJob.Parameters
        & $script:capturedUninstallJob.ScriptBlock @jobParameters

        Should -Invoke Get-WinUtilSelectedPackages -Times 1 -Exactly -ParameterFilter { $Action -eq "Uninstall" }

        Should -Invoke -CommandName Install-WinUtilProgramWinget -Times 1 -Exactly -ParameterFilter {
            $Action -eq "Uninstall" -and @($Programs)[0] -eq "Git.Git"
        }
        Should -Invoke -CommandName Install-WinUtilProgramChoco -Times 1 -Exactly -ParameterFilter {
            $Action -eq "Uninstall" -and @($Programs)[0] -eq "vlc"
        }
        Should -Invoke -CommandName Step-WinUtilJob -Times 1 -Exactly -ParameterFilter {
            $Status -eq "Uninstalled Git.Git (1/2)" -and $Percent -eq 50
        }
        Should -Invoke -CommandName Step-WinUtilJob -Times 1 -Exactly -ParameterFilter {
            $Status -eq "Uninstalled Chocolatey packages (2/2)" -and $Percent -eq 100
        }
    }

    It "permite que uma falha apareça para que a camada de jobs possa tratá-la" {
        Mock Install-WinUtilProgramWinget { throw "winget failed" }

        Invoke-WPFUnInstall

        $jobParameters = $script:capturedUninstallJob.Parameters
        { & $script:capturedUninstallJob.ScriptBlock @jobParameters } | Should -Throw "winget failed"
    }
}
