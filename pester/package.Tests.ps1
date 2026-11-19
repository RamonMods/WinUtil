#===========================================================================
# Testes - Seleção de pacotes e gerenciadores de pacotes
#===========================================================================

BeforeAll {
    $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

    . (Join-Path $script:repoRoot "functions\private\Get-WinUtilSelectedPackages.ps1")
    . (Join-Path $script:repoRoot "functions\private\Test-WinUtilPackageManager.ps1")
    . (Join-Path $script:repoRoot "functions\private\Install-WinUtilProgramWinget.ps1")
    . (Join-Path $script:repoRoot "functions\private\Install-WinUtilProgramChoco.ps1")

    function Invoke-WPFUIThread { }
    function Write-WinUtilJobBanner {
        param([string]$Message, [string]$Level)
    }
    # Estes testes cobrem o caminho da CLI; o caminho do módulo é verificado com o winget real
    function Step-WinUtilJob { param([string]$Status, [int]$Percent, [string]$State, [string]$Overlay, [switch]$Hide) }
    function Write-WinUtilLog { }
}

Describe "Get-WinUtilSelectedPackages" {
    BeforeEach {
        Mock Invoke-WPFUIThread { }
    }

    It "usa IDs do winget quando o winget é preferido" {
        $packages = @(
            [pscustomobject]@{ winget = "Git.Git"; choco = "git" }
            [pscustomobject]@{ winget = "VideoLAN.VLC"; choco = "vlc" }
        )

        $result = Get-WinUtilSelectedPackages -PackageList $packages -Preference "Winget"

        (@($result["Winget"]) -join "|") | Should -Be "Git.Git|VideoLAN.VLC"
        @($result["Choco"]).Count | Should -Be 0
    }

    It "usa IDs do choco e recorre ao winget para IDs choco na ou ausentes" {
        $packages = @(
            [pscustomobject]@{ winget = "Git.Git"; choco = "git" }
            [pscustomobject]@{ winget = "VideoLAN.VLC"; choco = "na" }
            [pscustomobject]@{ winget = "Mozilla.Firefox" }
        )

        $result = Get-WinUtilSelectedPackages -PackageList $packages -Preference "Choco"

        (@($result["Choco"]) -join "|") | Should -Be "git"
        (@($result["Winget"]) -join "|") | Should -Be "VideoLAN.VLC|Mozilla.Firefox"
    }

    It "divide valores com vários IDs por ';' para que cada ID seja instalado" {
        $packages = @(
            [pscustomobject]@{ winget = "GitHub.GitHubDesktop"; choco = "git;github-desktop" }
        )

        $result = Get-WinUtilSelectedPackages -PackageList $packages -Preference "Choco"

        (@($result["Choco"]) -join "|") | Should -Be "git|github-desktop"
    }

    It "não desinstala uma dependência de aplicativo a menos que ela tenha sido selecionada separadamente" {
        $desktop = [pscustomobject]@{ winget = "GitHub.GitHubDesktop"; choco = "git;github-desktop" }
        $git = [pscustomobject]@{ winget = "Git.Git"; choco = "git" }

        $desktopOnly = Get-WinUtilSelectedPackages -PackageList @($desktop) -Preference Choco -Action Uninstall
        @($desktopOnly.Choco) | Should -Be @('github-desktop')

        $both = Get-WinUtilSelectedPackages -PackageList @($desktop, $git) -Preference Choco -Action Uninstall
        @($both.Choco) | Should -Be @('github-desktop', 'git')
    }

    It "ignora IDs de pacote em branco, na e ausentes" {
        $packages = @(
            [pscustomobject]@{ winget = ""; choco = "" }
            [pscustomobject]@{ winget = "na"; choco = "na" }
            [pscustomobject]@{ choco = "only-choco" }
            [pscustomobject]@{ winget = "   " }
        )

        $result = Get-WinUtilSelectedPackages -PackageList $packages -Preference "Winget"

        @($result["Winget"]).Count | Should -Be 0
        @($result["Choco"]).Count | Should -Be 0
    }

    It "remove IDs de pacote duplicados" {
        $packages = @(
            [pscustomobject]@{ winget = "Git.Git"; choco = "git" }
            [pscustomobject]@{ winget = "Git.Git"; choco = "git" }
            [pscustomobject]@{ winget = "VideoLAN.VLC"; choco = "vlc" }
        )

        $result = Get-WinUtilSelectedPackages -PackageList $packages -Preference "Choco"

        (@($result["Choco"]) -join "|") | Should -Be "git|vlc"
        @($result["Winget"]).Count | Should -Be 0
    }

    It "retorna exatamente um objeto para que o chamador possa indexar a divisão" {
        # Um valor estranho no fluxo de saída tornaria isso uma matriz, e toda lista de pacotes
        # seria lida de volta vazia.
        $result = @(Get-WinUtilSelectedPackages -PackageList @([pscustomobject]@{ winget = "Git.Git" }) -Preference "Winget")

        $result.Count | Should -Be 1
        (@($result[0]["Winget"]) -join "|") | Should -Be "Git.Git"
    }

    It "retorna listas de pacotes vazias para uma seleção vazia" {
        $result = Get-WinUtilSelectedPackages -PackageList @() -Preference "Winget"

        @($result["Winget"]).Count | Should -Be 0
        @($result["Choco"]).Count | Should -Be 0
    }
}

Describe "Test-WinUtilPackageManager" {
    BeforeEach {
        Mock Write-WinUtilJobBanner { }
        Mock Write-Host { }
    }

    It "informa winget instalado quando o comando existe" {
        Mock Get-Command {
            [pscustomobject]@{ Name = "winget" }
        } -ParameterFilter { $Name -eq "winget" -and $ErrorAction -eq "SilentlyContinue" }

        Test-WinUtilPackageManager -winget | Should -Be "installed"

        Should -Invoke -CommandName Get-Command -Times 1 -Exactly -ParameterFilter {
            $Name -eq "winget" -and $ErrorAction -eq "SilentlyContinue"
        }
        Should -Invoke -CommandName Write-WinUtilJobBanner -Times 0 -Exactly
        Should -Invoke -CommandName Write-Host -Times 0 -Exactly
    }

    It "informa choco não instalado quando o comando está ausente" {
        Mock Get-Command {
            $null
        } -ParameterFilter { $Name -eq "choco" -and $ErrorAction -eq "SilentlyContinue" }

        Test-WinUtilPackageManager -choco | Should -Be "not-installed"

        Should -Invoke -CommandName Get-Command -Times 1 -Exactly -ParameterFilter {
            $Name -eq "choco" -and $ErrorAction -eq "SilentlyContinue"
        }
        Should -Invoke -CommandName Write-WinUtilJobBanner -Times 0 -Exactly
    }

    It "exige que ambos os gerenciadores solicitados estejam instalados" -TestCases @(
        @{ WingetPresent = $true; ChocoPresent = $true; Expected = "installed" }
        @{ WingetPresent = $false; ChocoPresent = $true; Expected = "not-installed" }
        @{ WingetPresent = $true; ChocoPresent = $false; Expected = "not-installed" }
    ) {
        param($WingetPresent, $ChocoPresent, $Expected)
        Mock Get-Command { if ($WingetPresent) { [pscustomobject]@{ Name = "winget" } } } -ParameterFilter { $Name -eq "winget" }
        Mock Get-Command { if ($ChocoPresent) { [pscustomobject]@{ Name = "choco" } } } -ParameterFilter { $Name -eq "choco" }

        Test-WinUtilPackageManager -winget -choco | Should -Be $Expected
        Should -Invoke -CommandName Write-Host -Times 0 -Exactly
    }

    It "informa não instalado quando nenhum gerenciador é solicitado" {
        Test-WinUtilPackageManager | Should -Be "not-installed"
    }
}

Describe "Install-WinUtilProgramWinget" {
    BeforeEach {
        Mock Update-WinUtilPowerShellMSI { [pscustomobject]@{ Outcome = "NotInstalled" } }
        Mock Write-WinUtilLog { }
        Mock Start-Process { [pscustomobject]@{ ExitCode = 0 } }
    }

    It "inicia o winget com argumentos de instalação" {
        Install-WinUtilProgramWinget -Action Install -Programs @("Git.Git")

        Should -Invoke -CommandName Start-Process -Times 1 -Exactly -ParameterFilter {
            $FilePath -eq "winget" -and
                (@($ArgumentList) -join "|") -eq "install|--id|Git.Git|--accept-package-agreements|--accept-source-agreements|--source|winget|--silent" -and
                $NoNewWindow -eq $true -and
                $Wait -eq $true -and
                $PassThru -eq $true
        }
    }

    It "inicia o winget com argumentos de desinstalação e fonte msstore quando solicitado" {
        Install-WinUtilProgramWinget -Action Uninstall -Programs @("msstore:9NBLGGH4NNS1")

        Should -Invoke -CommandName Start-Process -Times 1 -Exactly -ParameterFilter {
            $FilePath -eq "winget" -and
                (@($ArgumentList) -join "|") -eq "uninstall|--id|9NBLGGH4NNS1|--source|msstore|--silent"
        }
    }

    It "atualiza cada pacote pela fonte configurada sem analisar a tabela de saída" {
        Install-WinUtilProgramWinget -Action Upgrade -Programs @("all")

        Should -Invoke -CommandName Start-Process -Times 1 -Exactly -ParameterFilter {
            $FilePath -eq "winget" -and
                (@($ArgumentList) -join "|") -eq "upgrade|--all|--accept-package-agreements|--accept-source-agreements|--include-unknown|--silent"
        }
    }

    It "ignora IDs de pacote em branco e na" {
        Install-WinUtilProgramWinget -Action Install -Programs @(" ", "na")

        Should -Invoke -CommandName Start-Process -Times 0 -Exactly
    }
}

Describe "Install-WinUtilProgramChoco" {
    BeforeAll {
        # choco é um comando nativo, então precisa de uma função para substituí-lo
        function choco { $global:LASTEXITCODE = 0 }
    }

    BeforeEach {
        Mock Write-WinUtilLog { }
        Mock Step-WinUtilJob { }
        Mock choco { $global:LASTEXITCODE = 0 }
    }

    It "chama o choco uma vez por pacote para que uma falha identifique qual pacote falhou" {
        $results = @(Install-WinUtilProgramChoco -Action Install -Programs @("git", "vlc"))

        $results.Count | Should -Be 2
        $results[0].Package | Should -Be "git"
        $results[1].Package | Should -Be "vlc"
        Should -Invoke -CommandName choco -Times 2 -Exactly
    }

    It "passa o verbo de instalação e suprime o redesenho de progresso próprio do choco" {
        Install-WinUtilProgramChoco -Action Install -Programs @("git")

        Should -Invoke -CommandName choco -Times 1 -Exactly -ParameterFilter {
            $args -contains "install" -and $args -contains "git" -and
                $args -contains "-y" -and $args -contains "--no-progress"
        }
    }

    It "passa o verbo de desinstalação" {
        Install-WinUtilProgramChoco -Action Uninstall -Programs @("git")

        Should -Invoke -CommandName choco -Times 1 -Exactly -ParameterFilter {
            $args -contains "uninstall" -and $args -contains "git"
        }
    }

    It "atualiza em vez de instalar quando solicitado a atualizar" {
        # choco install all -y procuraria um pacote chamado "all"
        Install-WinUtilProgramChoco -Action Upgrade -Programs @("all")

        Should -Invoke -CommandName choco -Times 1 -Exactly -ParameterFilter {
            $args -contains "upgrade" -and $args -contains "all"
        }
    }

    It "move a barra de progresso pela lista" {
        Install-WinUtilProgramChoco -Action Install -Programs @("git", "vlc") -ProgressBase 0 -ProgressSpan 100

        Should -Invoke -CommandName Step-WinUtilJob -ParameterFilter { $Status -like "*git (1/2)*" }
        Should -Invoke -CommandName Step-WinUtilJob -ParameterFilter { $Status -like "*vlc (2/2)*" }
    }
}
