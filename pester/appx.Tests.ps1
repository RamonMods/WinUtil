#===========================================================================
# Testes - Gerenciamento de AppX
#===========================================================================

BeforeAll {
    $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
    . (Join-Path $script:repoRoot "functions\private\Get-WinUtilInstalledAPPX.ps1")
    . (Join-Path $script:repoRoot "functions\private\Install-WinUtilAPPX.ps1")
    . (Join-Path $script:repoRoot "functions\private\Complete-WinUtilPackageRun.ps1")
    . (Join-Path $script:repoRoot "functions\private\Remove-WinUtilAPPX.ps1")
    . (Join-Path $script:repoRoot "functions\private\Remove-WinUtilProvisionedAPPX.ps1")
    . (Join-Path $script:repoRoot "functions\public\Invoke-WPFAppxInstall.ps1")
    . (Join-Path $script:repoRoot "functions\public\Invoke-WPFAppxRemoval.ps1")
    . (Join-Path $script:repoRoot "functions\public\Invoke-WPFButton.ps1")

    $tokens = $null
    $parseErrors = $null
    $provisionedSourcePath = Join-Path $script:repoRoot "functions\private\Remove-WinUtilProvisionedAPPX.ps1"
    $provisionedSourceAst = [System.Management.Automation.Language.Parser]::ParseFile($provisionedSourcePath, [ref]$tokens, [ref]$parseErrors)
    $ps5CommandAssignment = $provisionedSourceAst.Find({
        param($node)
        $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
            $node.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
            $node.Left.VariablePath.UserPath -eq "ps5Command"
    }, $true)
    $script:provisionedRemovalScriptBlock = $ps5CommandAssignment.Right.Expression.ScriptBlock.GetScriptBlock()

    $installSourcePath = Join-Path $script:repoRoot "functions\private\Install-WinUtilAPPX.ps1"
    $installSourceAst = [System.Management.Automation.Language.Parser]::ParseFile($installSourcePath, [ref]$tokens, [ref]$parseErrors)
    $installCommandAssignment = $installSourceAst.Find({
        param($node)
        $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
            $node.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
            $node.Left.VariablePath.UserPath -eq "ps5Command"
    }, $true)
    $script:appxInstallScriptBlock = $installCommandAssignment.Right.Expression.ScriptBlock.GetScriptBlock()

    function Write-WinUtilLog {
        param($Message, $Level, $Component)
    }
    function Start-WinUtilJob {
        param([string]$Name, [scriptblock]$ScriptBlock, [hashtable]$Parameters, [string]$Description, [switch]$DisableAppList)
    }
    function Step-WinUtilJob {
        param([string]$Status, [int]$Percent, [string]$State, [string]$Overlay)
    }
    function Show-WinUtilMessage {
        param($Message, $Title, $Button, $Icon)
    }
    function Invoke-WPFRunspace {
        param($ArgumentList, $ParameterList, [scriptblock]$ScriptBlock)
    }
    function Invoke-WPFUIThread {
        param([scriptblock]$ScriptBlock, [hashtable]$Parameters, [switch]$Async)
    }
    function powershell.exe { }
    function Get-AppxPackage {
        param($Name, [switch]$AllUsers, $ErrorAction)
    }
    function Add-AppxPackage {
        param($Register, [switch]$DisableDevelopmentMode, $ErrorAction)
    }
    function Install-WinUtilWinget { }
    function Install-WinUtilProgramWinget {
        param($Action, $Programs)
    }
    function Remove-AppxPackage {
        param(
            [Parameter(ValueFromPipeline = $true)]
            $InputObject,
            $Package,
            [switch]$AllUsers,
            $ErrorAction
        )
        process { }
    }
    function Remove-WinUtilProvisionedAPPX {
        param($PackageList)
    }
    function Get-AppxProvisionedPackage {
        param([switch]$Online, $ErrorAction)
    }
    function Remove-AppxProvisionedPackage {
        param(
            [Parameter(ValueFromPipeline = $true)]
            $InputObject,
            [switch]$Online,
            $PackageName,
            $ErrorAction
        )
        process { }
    }
    function Get-Package {
        [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidOverwritingBuiltInCmdlets', '', Justification='Test shim is intentionally mocked by Pester.')]
        param($Name, $ErrorAction)
    }
    function Uninstall-Package {
        [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidOverwritingBuiltInCmdlets', '', Justification='Test shim is intentionally mocked by Pester.')]
        param(
            [Parameter(ValueFromPipeline = $true)]
            $InputObject,
            [switch]$Force
        )
        process { }
    }
}

Describe "Get-WinUtilInstalledAPPX" {
    BeforeEach {
        Mock Write-WinUtilLog { }
        Mock powershell.exe {
            $global:LASTEXITCODE = 0
            @("Example.One", "Example.Two")
        }
    }

    It "consulta os nomes dos pacotes instalados por meio do Windows PowerShell" {
        $result = Get-WinUtilInstalledAPPX

        $result | Should -Be @("Example.One", "Example.Two")
        Should -Invoke -CommandName powershell.exe -Times 1 -Exactly
        Should -Invoke -CommandName Write-WinUtilLog -Times 0 -Exactly
    }

    It "registra falhas de consulta e não retorna nomes de pacotes" {
        Mock powershell.exe {
            $global:LASTEXITCODE = 1
            "AppX query failed"
        }

        $result = @(Get-WinUtilInstalledAPPX)

        $result | Should -HaveCount 0
        Should -Invoke -CommandName Write-WinUtilLog -Times 1 -Exactly -ParameterFilter {
            $Level -eq "ERROR" -and
                $Component -eq "AppX" -and
                $Message -eq "Falha ao obter os pacotes AppX instalados: AppX query failed"
        }
    }
}

Describe "Install-WinUtilAPPX" {
    BeforeEach {
        Mock Write-WinUtilLog { }
        Mock Install-WinUtilWinget { }
        Mock Install-WinUtilProgramWinget { }
        Mock powershell.exe {
            $global:LASTEXITCODE = 0
            "C:\Program Files\WindowsApps\Example.Package\AppxManifest.xml"
        }
    }

    It "usa um manifesto local sem contatar a Microsoft Store" {
        $result = Install-WinUtilAPPX -Name "Example.Package" -StoreId "9EXAMPLE1234"

        $result.Outcome | Should -Be "Succeeded"
        $result.Manager | Should -Be "appx"
        Should -Invoke -CommandName Install-WinUtilWinget -Times 0 -Exactly
        Should -Invoke -CommandName Install-WinUtilProgramWinget -Times 0 -Exactly
        Should -Invoke -CommandName Write-WinUtilLog -Times 1 -Exactly -ParameterFilter {
            $Component -eq "AppX" -and
                $Message -like "Manifesto AppX local registrado para Example.Package:*"
        }
    }

    It "recorre à Microsoft Store quando não há manifesto local disponível" {
        Mock powershell.exe { $global:LASTEXITCODE = 0 }

        Install-WinUtilAPPX -Name "Example.Package" -StoreId "9EXAMPLE1234"

        Should -Invoke -CommandName Install-WinUtilWinget -Times 1 -Exactly
        Should -Invoke -CommandName Install-WinUtilProgramWinget -Times 1 -Exactly -ParameterFilter {
            $Action -eq "Install" -and $Programs.Count -eq 1 -and $Programs[0] -eq "msstore:9EXAMPLE1234"
        }
    }

    It "não retorna a saída de inicialização do WinGet como resultado de pacote" {
        Mock powershell.exe { $global:LASTEXITCODE = 0 }
        Mock Install-WinUtilWinget { [pscustomobject]@{ Provider = "NuGet" } }
        Mock Install-WinUtilProgramWinget {
            [pscustomobject]@{ Package = "msstore:9EXAMPLE1234"; Outcome = "Skipped" }
        }

        $result = @(Install-WinUtilAPPX -Name "Example.Package" -StoreId "9EXAMPLE1234")

        $result.Count | Should -Be 1
        $result[0].Package | Should -Be "msstore:9EXAMPLE1234"
        $result[0].Outcome | Should -Be "Skipped"
    }

    It "registra falhas de registro local antes de usar a Microsoft Store" {
        Mock powershell.exe {
            $global:LASTEXITCODE = 1
            "Registration failed"
        }

        Install-WinUtilAPPX -Name "Example.Package" -StoreId "9EXAMPLE1234"

        Should -Invoke -CommandName Write-WinUtilLog -Times 1 -Exactly -ParameterFilter {
            $Level -eq "WARN" -and
                $Component -eq "AppX" -and
                $Message -eq "Falha no registro do AppX local para Example.Package: Registration failed"
        }
        Should -Invoke -CommandName Install-WinUtilProgramWinget -Times 1 -Exactly
    }

    It "retorna um resultado de falha quando nenhum método de instalação está disponível" {
        Mock powershell.exe { $global:LASTEXITCODE = 0 }

        $result = @(Install-WinUtilAPPX -Name "Example.Package")

        $result.Count | Should -Be 1
        $result[0].Outcome | Should -Be "Failed"
        $result[0].Manager | Should -Be "appx"
        $result[0].Detail | Should -Be "Não foi possível instalar Example.Package porque não há manifesto local nem ID da Microsoft Store disponível."
        Should -Invoke -CommandName Install-WinUtilProgramWinget -Times 0 -Exactly
        Should -Invoke -CommandName Write-WinUtilLog -Times 1 -Exactly -ParameterFilter {
            $Level -eq "ERROR" -and
                $Component -eq "AppX" -and
                $Message -eq "Não foi possível instalar Example.Package porque não há manifesto local nem ID da Microsoft Store disponível."
        }
    }

    It "registra o manifesto de um pacote instalado por meio do Windows PowerShell" {
        Mock Get-AppxPackage {
            [pscustomobject]@{
                InstallLocation = "C:\Program Files\WindowsApps\Example.Package"
                Version = [version]"2.0.0.0"
            }
        }
        Mock Get-AppxProvisionedPackage { }
        Mock Test-Path { $LiteralPath -eq "C:\Program Files\WindowsApps\Example.Package\AppxManifest.xml" }
        Mock Add-AppxPackage { }

        $result = & $script:appxInstallScriptBlock "Example.Package"

        $result | Should -Be "C:\Program Files\WindowsApps\Example.Package\AppxManifest.xml"
        Should -Invoke -CommandName Get-AppxPackage -Times 1 -Exactly
        Should -Invoke -CommandName Add-AppxPackage -Times 1 -Exactly
    }
}

Describe "Seleção de pacotes AppX instalados" {
    BeforeEach {
        $script:sync = [Hashtable]::Synchronized(@{
            ActiveJob = $null
            configs = @{
                feature = @{}
                appxHashtable = @{
                    WPFAppxExample = [pscustomobject]@{ PackageId = "Example.Package" }
                    WPFAppxMissing = [pscustomobject]@{ PackageId = "Missing.Package" }
                }
            }
            WPFAppxExample = [pscustomobject]@{ IsChecked = $false }
            WPFAppxMissing = [pscustomobject]@{ IsChecked = $false }
        })

        Mock Get-WinUtilInstalledAPPX { @("Example.Package") }
        Mock Invoke-WPFAppxInstall { }
        Mock Step-WinUtilJob { }
        Mock Invoke-WPFUIThread { $uiParameters = $Parameters; & $ScriptBlock @uiParameters }
        Mock Start-WinUtilJob {
            $jobParameters = $Parameters
            & $ScriptBlock @jobParameters
        }
    }

    AfterEach {
        Remove-Variable -Name sync -Scope Script -ErrorAction SilentlyContinue
    }

    It "seleciona os pacotes configurados retornados pela consulta compatível com segurança" {
        Invoke-WPFButton -Button "WPFGetInstalledAppx"

        Should -Invoke -CommandName Start-WinUtilJob -Times 1 -Exactly -ParameterFilter {
            $Name -eq "GetInstalledAppx"
        }
        Should -Invoke -CommandName Get-WinUtilInstalledAPPX -Times 1 -Exactly
        $script:sync.WPFAppxExample.IsChecked | Should -BeTrue
        $script:sync.WPFAppxMissing.IsChecked | Should -BeFalse
    }

    It "roteia o botão de instalação para o fluxo de instalação de AppX" {
        Invoke-WPFButton -Button "WPFInstallSelectedAppx"

        Should -Invoke -CommandName Invoke-WPFAppxInstall -Times 1 -Exactly
    }
}

Describe "Remove-WinUtilAPPX" {
    BeforeEach {
        Mock Write-Host { }
        Mock Write-WinUtilLog { }
        Mock Get-AppxPackage {
            @(
                [pscustomobject]@{
                    Name = $Name
                    PackageFullName = "$Name.FullName"
                }
                [pscustomobject]@{
                    Name = $Name
                    PackageFullName = "$Name.FullName"
                }
            )
        }
        Mock Remove-AppxPackage { }
    }

    It "remove os pacotes AppX instalados correspondentes" {
        Remove-WinUtilAPPX -Name "Microsoft.Xbox*"

        Should -Invoke -CommandName Get-AppxPackage -Times 1 -Exactly -ParameterFilter {
            $Name -eq "*Microsoft.Xbox**" -and $AllUsers -eq $true
        }
        Should -Invoke -CommandName Remove-AppxPackage -Times 1 -Exactly -ParameterFilter {
            $Package -eq "*Microsoft.Xbox**.FullName" -and
                $AllUsers -eq $true -and
                $ErrorAction -eq "Stop"
        }
    }

    It "registra falhas na remoção de pacotes AppX instalados" {
        Mock Remove-AppxPackage { throw "Removal failed" }

        { Remove-WinUtilAPPX -Name "Example.Package" } | Should -Not -Throw

        Should -Invoke -CommandName Write-WinUtilLog -Times 1 -Exactly -ParameterFilter {
            $Level -eq "ERROR" -and
                $Component -eq "AppX" -and
                $Message -eq "Falha ao remover o pacote AppX *Example.Package*.FullName: Removal failed"
        }
    }
}

Describe "Remove-WinUtilProvisionedAPPX" {
    BeforeEach {
        Mock Get-AppxProvisionedPackage {
            @(
                [pscustomobject]@{ DisplayName = "Example.One"; PackageName = "Example.One_1.0" }
                [pscustomobject]@{ DisplayName = "Example.Two"; PackageName = "Example.Two_1.0" }
            )
        }
        Mock Remove-AppxProvisionedPackage { }
    }

    It "consulta os pacotes provisionados uma vez para todos os nomes de pacotes selecionados" {
        & $script:provisionedRemovalScriptBlock "Example.One" "Example.Two"

        Should -Invoke -CommandName Get-AppxProvisionedPackage -Times 1 -Exactly -ParameterFilter {
            $Online -eq $true
        }
        Should -Invoke -CommandName Remove-AppxProvisionedPackage -Times 1 -Exactly -ParameterFilter {
            $PackageName -eq "Example.One_1.0" -and $Online -eq $true
        }
        Should -Invoke -CommandName Remove-AppxProvisionedPackage -Times 1 -Exactly -ParameterFilter {
            $PackageName -eq "Example.Two_1.0" -and $Online -eq $true
        }
    }

    It "expõe falhas de remoção de pacotes provisionados do processo filho" {
        Mock Remove-AppxProvisionedPackage { throw "DISM failed" }

        { & $script:provisionedRemovalScriptBlock "Example.One" } |
            Should -Throw "*Falha ao remover o pacote AppX provisionado Example.One_1.0: DISM failed*"
        Should -Invoke -CommandName Remove-AppxProvisionedPackage -Times 1 -Exactly -ParameterFilter {
            $PackageName -eq "Example.One_1.0" -and
                $Online -eq $true -and
                $ErrorAction -eq "Stop"
        }
    }

    It "lança exceção após registrar falhas do processo filho" {
        $source = Get-Content -Path $provisionedSourcePath -Raw

        $source | Should -Match '\$removalOutput = powershell\.exe .* 2>&1'
        $source | Should -Match 'Write-WinUtilLog -Level "ERROR" -Component "AppX" -Message \$errorMessage'
        $source | Should -Match '(?s)A remoção do pacote AppX provisionado falhou:.*WinUtilErrorReported.*throw \$exception.*Remoção de pacote AppX provisionado concluída\.'
    }
}

Describe "Invoke-WPFAppxInstall" {
    BeforeEach {
        $script:sync = [Hashtable]::Synchronized(@{
            ActiveJob = $null
            Form = [pscustomobject]@{ Dispatcher = [pscustomobject]@{} }
            selectedAppx = [System.Collections.Generic.List[string]]::new()
            configs = @{
                appxHashtable = @{
                    WPFAppxExample = [pscustomobject]@{
                        Content = "Example App"
                        PackageId = "Example.Package"
                        StoreId = "9EXAMPLE1234"
                    }
                }
            }
        })
        $script:capturedAppxInstallScriptBlock = $null
        $script:capturedAppxInstallParameterList = $null

        Mock Show-WinUtilMessage { "OK" }
        Mock Write-Host { }
        Mock Write-WinUtilLog { }
        Mock Invoke-WPFUIThread { }
        Mock Install-WinUtilAPPX { }
        Mock Complete-WinUtilPackageRun { }
        Mock Step-WinUtilJob { }
        Mock Start-WinUtilJob {
            $script:capturedAppxInstallScriptBlock = $ScriptBlock
            $script:capturedAppxInstallParameters = $Parameters
        }
    }

    AfterEach {
        Remove-Variable -Name sync -Scope Script -ErrorAction SilentlyContinue
        Remove-Variable -Name capturedAppxInstallScriptBlock -Scope Script -ErrorAction SilentlyContinue
        Remove-Variable -Name capturedAppxInstallParameterList -Scope Script -ErrorAction SilentlyContinue
    }

    It "exibe aviso e sai quando nenhum pacote AppX foi selecionado para instalação" {
        Invoke-WPFAppxInstall

        Should -Invoke -CommandName Show-WinUtilMessage -Times 1 -Exactly -ParameterFilter {
            $Message -eq "Nenhum pacote AppX selecionado" -and
                $Title -eq "Erro" -and
                $Button -eq "OK" -and
                $Icon -eq "Error"
        }
        Should -Invoke -CommandName Start-WinUtilJob -Times 0 -Exactly
    }

    It "enfileira um job de instalação para os pacotes AppX selecionados" {
        $script:sync.selectedAppx.Add("WPFAppxExample")

        Invoke-WPFAppxInstall

        Should -Invoke -CommandName Start-WinUtilJob -Times 1 -Exactly -ParameterFilter {
            $Name -eq "AppX install"
        }
        $script:capturedAppxInstallParameters.Selected[0] | Should -Be "WPFAppxExample"
    }

    It "instala os pacotes AppX selecionados com seus IDs da Store" {
        $script:sync.selectedAppx.Add("WPFAppxExample")

        Invoke-WPFAppxInstall
        $jobParameters = $script:capturedAppxInstallParameters
        & $script:capturedAppxInstallScriptBlock @jobParameters

        Should -Invoke -CommandName Install-WinUtilAPPX -Times 1 -Exactly -ParameterFilter {
            $Name -eq "Example.Package" -and $StoreId -eq "9EXAMPLE1234"
        }
        Should -Invoke -CommandName Step-WinUtilJob -Times 1 -Exactly -ParameterFilter {
            $Status -eq "Instalando Example App (1/1)" -and $Percent -eq 0
        }
        Should -Invoke -CommandName Step-WinUtilJob -Times 1 -Exactly -ParameterFilter {
            $Status -eq "Installed Example App (1/1)" -and $Percent -eq 100
        }
    }

    It "permite que uma falha de instalação apareça para que a camada de job possa tratá-la" {
        $script:sync.selectedAppx.Add("WPFAppxExample")
        Mock Install-WinUtilAPPX { throw "Install failed" }

        Invoke-WPFAppxInstall
        $jobParameters = $script:capturedAppxInstallParameters

        { & $script:capturedAppxInstallScriptBlock @jobParameters } | Should -Throw "Install failed"
    }

    It "continua instalando os demais pacotes quando um retorna resultado de falha" {
        $script:sync.selectedAppx.Add("WPFAppxExample")
        $script:sync.configs.appxHashtable.WPFAppxNoSource = [pscustomobject]@{
            Content = "No Source App"
            PackageId = "No.Source.Package"
        }
        $script:sync.selectedAppx.Add("WPFAppxNoSource")
        Mock Install-WinUtilAPPX {
            if ($Name -eq "No.Source.Package") {
                [pscustomobject]@{
                    Package = $Name
                    Manager = "appx"
                    Action = "Install"
                    ExitCode = 1
                    Outcome = "Failed"
                    Detail = "no install source"
                }
            } else {
                [pscustomobject]@{
                    Package = $Name
                    Manager = "appx"
                    Action = "Install"
                    ExitCode = 0
                    Outcome = "Succeeded"
                    Detail = "exit code 0"
                }
            }
        }

        Invoke-WPFAppxInstall
        $jobParameters = $script:capturedAppxInstallParameters
        & $script:capturedAppxInstallScriptBlock @jobParameters

        Should -Invoke -CommandName Install-WinUtilAPPX -Times 2 -Exactly
        Should -Invoke Complete-WinUtilPackageRun -Times 1 -Exactly -ParameterFilter {
            $Action -eq "Install" -and $Results.Count -eq 2 -and
                @($Results | Where-Object Outcome -EQ "Failed").Count -eq 1 -and
                @($Results | Where-Object Outcome -EQ "Succeeded").Count -eq 1
        }
    }

    It "repassa um resultado ignorado da Store à conclusão do pacote e o reporta como ignorado" {
        $script:sync.selectedAppx.Add("WPFAppxExample")
        Mock Install-WinUtilAPPX {
            [pscustomobject]@{
                Package = "9EXAMPLE1234"
                Manager = "winget"
                Action = "Install"
                ExitCode = -1978335107
                Outcome = "Skipped"
                Detail = "elevated context"
            }
        }

        Invoke-WPFAppxInstall
        $jobParameters = $script:capturedAppxInstallParameters
        & $script:capturedAppxInstallScriptBlock @jobParameters

        Should -Invoke Complete-WinUtilPackageRun -Times 1 -Exactly -ParameterFilter {
            $Action -eq "Install" -and $Results.Count -eq 1 -and $Results[0].Outcome -eq "Skipped"
        }
        Should -Invoke Step-WinUtilJob -Times 1 -Exactly -ParameterFilter {
            $Status -eq "Skipped Example App (1/1)" -and $Percent -eq 100
        }
    }

}
Describe "Invoke-WPFAppxRemoval" {
    BeforeEach {
        $script:sync = [Hashtable]::Synchronized(@{
            ActiveJob = $null
            Form = [pscustomobject]@{ Dispatcher = [pscustomobject]@{} }
            selectedAppx = [System.Collections.Generic.List[string]]::new()
            configs = @{
                appxHashtable = @{}
            }
        })
        $script:capturedAppxRemovalScriptBlock = $null
        $script:capturedAppxRemovalParameters = $null
        $script:apps = @{
            WPFAppxExample = [pscustomobject]@{
                Content = "Example App"
                PackageId = "Example.Package"
            }
            WPFAppxMicrosoft_XboxGamingOverlay = [pscustomobject]@{
                Content = "Xbox Gaming Overlay"
                PackageId = "Microsoft.XboxGamingOverlay"
            }
            WPFAppxMicrosoft_WindowsNotepad = [pscustomobject]@{
                Content = "Notepad"
                PackageId = "Microsoft.WindowsNotepad"
            }
            WPFAppxMSTeams = [pscustomobject]@{
                Content = "Microsoft Teams"
                PackageId = "MSTeams"
            }
        }

        Mock Show-WinUtilMessage { "OK" }
        Mock Write-Host { }
        Mock Write-WinUtilLog { }
        Mock Step-WinUtilJob { }
        Mock Stop-Process { }
        Mock Set-ItemProperty { }
        Mock Get-AppxPackage {
            [pscustomobject]@{
                Name = $Name
                PackageFullName = "$Name.FullName"
            }
        }
        Mock Remove-AppxPackage { }
        Mock Remove-WinUtilProvisionedAPPX { }
        Mock Get-Package {
            [pscustomobject]@{
                Name = "Microsoft Teams Meeting Add-in"
            }
        }
        Mock Uninstall-Package { }
        Mock Start-WinUtilJob {
            $script:capturedAppxRemovalScriptBlock = $ScriptBlock
            $script:capturedAppxRemovalParameters = $Parameters
        }
    }

    AfterEach {
        Remove-Variable -Name sync -Scope Script -ErrorAction SilentlyContinue
        Remove-Variable -Name capturedAppxRemovalScriptBlock -Scope Script -ErrorAction SilentlyContinue
        Remove-Variable -Name capturedAppxRemovalParameters -Scope Script -ErrorAction SilentlyContinue
        Remove-Variable -Name apps -Scope Script -ErrorAction SilentlyContinue
    }

    It "exibe aviso e sai quando nenhum pacote AppX foi selecionado" {
        Invoke-WPFAppxRemoval

        Should -Invoke -CommandName Show-WinUtilMessage -Times 1 -Exactly -ParameterFilter {
            $Message -eq "Nenhum pacote AppX selecionado" -and
                $Title -eq "Erro" -and
                $Button -eq "OK" -and
                $Icon -eq "Error"
        }
        Should -Invoke -CommandName Start-WinUtilJob -Times 0 -Exactly
    }

    It "enfileira um job de remoção com um instantâneo da seleção e dos metadados dos aplicativos" {
        $script:sync.selectedAppx.Add("WPFAppxExample")
        $script:sync.configs.appxHashtable = $script:apps

        Invoke-WPFAppxRemoval
        $script:sync.selectedAppx.Add("WPFAppxChangedAfterLaunch")

        Should -Invoke -CommandName Start-WinUtilJob -Times 1 -Exactly -ParameterFilter {
            $Name -eq "AppX" -and $ScriptBlock -is [scriptblock]
        }
        Should -Invoke -CommandName Show-WinUtilMessage -Times 0 -Exactly
        $script:capturedAppxRemovalParameters.Selected | Should -HaveCount 1
        $script:capturedAppxRemovalParameters.Selected[0] | Should -Be "WPFAppxExample"
        $script:capturedAppxRemovalParameters.Apps["WPFAppxExample"].PackageId | Should -Be "Example.Package"
    }

    It "remove os pacotes selecionados e reporta o progresso de cada um" {
        $script:sync.selectedAppx.Add("WPFAppxExample")
        $script:sync.configs.appxHashtable = $script:apps

        Invoke-WPFAppxRemoval
        $jobParameters = $script:capturedAppxRemovalParameters
        & $script:capturedAppxRemovalScriptBlock @jobParameters

        Should -Invoke -CommandName Get-AppxPackage -Times 1 -Exactly -ParameterFilter {
            $Name -eq "*Example.Package*" -and $AllUsers -eq $true
        }
        Should -Invoke -CommandName Remove-AppxPackage -Times 1 -Exactly -ParameterFilter {
            $Package -eq "*Example.Package*.FullName"
        }
        Should -Invoke -CommandName Remove-WinUtilProvisionedAPPX -Times 1 -Exactly -ParameterFilter {
            $PackageList.Count -eq 1 -and $PackageList[0] -eq "Example.Package"
        }
        Should -Invoke -CommandName Step-WinUtilJob -Times 1 -Exactly -ParameterFilter {
            $Status -eq "Removendo Example App (1/1)" -and $Percent -eq 0
        }
        Should -Invoke -CommandName Step-WinUtilJob -Times 1 -Exactly -ParameterFilter {
            $Status -eq "Removido Example App (1/1)" -and $Percent -eq 90
        }
        Should -Invoke -CommandName Step-WinUtilJob -Times 1 -Exactly -ParameterFilter {
            $Status -eq "Removendo pacotes AppX provisionados" -and $Percent -eq 90
        }
    }

    It "permite que uma falha de remoção apareça para que a camada de job possa tratá-la" {
        $script:sync.selectedAppx.Add("WPFAppxExample")
        $script:sync.configs.appxHashtable = $script:apps
        Mock Remove-WinUtilAPPX { throw "Removal failed" }

        Invoke-WPFAppxRemoval
        $jobParameters = $script:capturedAppxRemovalParameters

        { & $script:capturedAppxRemovalScriptBlock @jobParameters } | Should -Throw "Removal failed"
        Should -Invoke -CommandName Remove-WinUtilProvisionedAPPX -Times 0 -Exactly
    }

    It "permite que uma falha de remoção provisionada apareça para que a camada de job possa tratá-la" {
        $script:sync.selectedAppx.Add("WPFAppxExample")
        $script:sync.configs.appxHashtable = $script:apps
        Mock Remove-WinUtilProvisionedAPPX { throw "Provisioned removal failed" }

        Invoke-WPFAppxRemoval
        $jobParameters = $script:capturedAppxRemovalParameters

        { & $script:capturedAppxRemovalScriptBlock @jobParameters } | Should -Throw "Provisioned removal failed"
    }

    It "aplica limpeza especial para seleções de Xbox overlay, Notepad e Teams" {
        foreach ($key in @("WPFAppxMicrosoft_XboxGamingOverlay", "WPFAppxMicrosoft_WindowsNotepad", "WPFAppxMSTeams")) {
            $script:sync.selectedAppx.Add($key)
        }
        $script:sync.configs.appxHashtable = $script:apps

        Invoke-WPFAppxRemoval
        $jobParameters = $script:capturedAppxRemovalParameters
        & $script:capturedAppxRemovalScriptBlock @jobParameters

        Should -Invoke -CommandName Stop-Process -Times 1 -Exactly -ParameterFilter {
            $Name -eq "GameBarFTServer" -and
                $Force -eq $true -and
                $Confirm -eq $false -and
                $ErrorAction -eq "SilentlyContinue"
        }
        Should -Invoke -CommandName Set-ItemProperty -Times 1 -Exactly -ParameterFilter {
            $Path -eq "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR" -and
                $Name -eq "AppCaptureEnabled" -and
                $Value -eq 0
        }
        Should -Invoke -CommandName Stop-Process -Times 1 -Exactly -ParameterFilter {
            $Name -eq "dllhost" -and
                $Force -eq $true -and
                $Confirm -eq $false -and
                $ErrorAction -eq "SilentlyContinue"
        }
        Should -Invoke -CommandName Get-Package -Times 1 -Exactly -ParameterFilter {
            $Name -eq "Microsoft Teams*"
        }
        Should -Invoke -CommandName Uninstall-Package -Times 1 -Exactly -ParameterFilter {
            $InputObject.Name -eq "Microsoft Teams Meeting Add-in" -and $Force -eq $true
        }
        Should -Invoke -CommandName Remove-AppxPackage -Times 3 -Exactly
        Should -Invoke -CommandName Remove-WinUtilProvisionedAPPX -Times 1 -Exactly -ParameterFilter {
            $PackageList.Count -eq 3 -and
            $PackageList[0] -eq "Microsoft.XboxGamingOverlay" -and
            $PackageList[1] -eq "Microsoft.WindowsNotepad" -and
            $PackageList[2] -eq "MSTeams"
        }
    }
}
