#===========================================================================
# Testes - Funções auxiliares do sistema
#===========================================================================

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

BeforeAll {
    $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
    . (Join-Path $script:repoRoot "functions\private\Invoke-WinUtilCurrentSystem.ps1")
    . (Join-Path $script:repoRoot "functions\private\Test-WinUtilPackageManager.ps1")
    . (Join-Path $script:repoRoot "functions\private\Set-WinUtilRegistry.ps1")
    . (Join-Path $script:repoRoot "functions\private\Set-WinUtilService.ps1")
    . (Join-Path $script:repoRoot "functions\public\Invoke-WPFPanelAutologin.ps1")
    . (Join-Path $script:repoRoot "functions\private\Invoke-WinUtilInstallPSProfile.ps1")

    function winget {
        param([Parameter(ValueFromRemainingArguments = $true)]$Arguments)
    }
    function choco {
        param([Parameter(ValueFromRemainingArguments = $true)]$Arguments)
    }
    # O caminho da CLI é o que estes testes cobrem; o caminho do módulo é verificado com o winget real
    function Step-WinUtilJob { param([string]$Status, [int]$Percent, [string]$State, [string]$Overlay, [switch]$Hide) }
    function Write-WinUtilLog { param($Message, $Level, $Component, [switch]$Detail) }
}

Describe "Invoke-WPFPanelAutologin" {
    BeforeEach {
        $script:sync = [Hashtable]::Synchronized(@{ winutildir = $TestDrive })
        Mock Invoke-WebRequest { }
        Mock Start-Process { }
    }

    It "usa o diretório de dados compartilhado do WinUtil em um runspace de worker" {
        Invoke-WPFPanelAutologin

        $expectedPath = Join-Path $TestDrive "autologin.exe"
        Should -Invoke -CommandName Invoke-WebRequest -Times 1 -Exactly -ParameterFilter { $OutFile -eq $expectedPath }
        Should -Invoke -CommandName Start-Process -Times 1 -Exactly -ParameterFilter { $FilePath -eq $expectedPath }
    }
}

Describe "Get-WinUtilPowerShell7Path" {
    It "encontra uma instalação padrão nova mesmo antes de a PATH do processo atual ser atualizada" {
        $expectedPath = "$env:ProgramFiles\PowerShell\7\pwsh.exe"
        Mock Get-Command { $null } -ParameterFilter { $Name -eq "pwsh" }
        Mock Test-Path { $LiteralPath -eq $expectedPath }

        Get-WinUtilPowerShell7Path | Should -Be $expectedPath
    }

    It "também é usado pela remoção de perfil para dar suporte a uma PATH desatualizada do processo" {
        $source = Get-Content (Join-Path $script:repoRoot "functions\private\Invoke-WinUtilUninstallPSProfile.ps1") -Raw

        $source | Should -Match '\$pwshPath = Get-WinUtilPowerShell7Path'
        $source | Should -Match '& \$pwshPath -NoProfile'
        $source | Should -Not -Match 'Get-Command pwsh'
    }
}

Describe "Invoke-WinUtilCurrentSystem aplicativos instalados" {
    BeforeEach {
        $script:sync = [Hashtable]::Synchronized(@{
            configs = [pscustomobject]@{
                applicationsHashtable = @{
                    WPFInstallGit = [pscustomobject]@{ winget = "Git.Git"; choco = "git" }
                    WPFInstallChatGPT = [pscustomobject]@{ winget = "msstore:9NT1R1C2HH7J"; choco = "na" }
                    WPFInstallMissing = [pscustomobject]@{ winget = "Git"; choco = "missing" }
                }
            }
        })

        Mock winget {
            $global:LASTEXITCODE = 0
            $script:wingetArguments = @($Arguments)
            @(
                "Name  Id  Version  Source",
                "--------------------------------",
                "Git  Git.Git  2.0  winget",
                "ChatGPT  9NT1R1C2HH7J  1.0  msstore"
            )
        }
        Mock choco {
            $script:chocoArguments = @($Arguments)
            @("Chocolatey v2", "git 2.0", "2 packages installed.")
        }
    }

    AfterEach {
        Remove-Variable -Name sync -Scope Script -ErrorAction SilentlyContinue
        Remove-Variable -Name wingetArguments -Scope Script -ErrorAction SilentlyContinue
        Remove-Variable -Name chocoArguments -Scope Script -ErrorAction SilentlyContinue
    }

    It "corresponde a IDs de pacote padrão e da Microsoft Store" {
        $result = @(Invoke-WinUtilCurrentSystem -CheckBox "winget")

        $result | Should -HaveCount 2
        $result | Should -Contain "WPFInstallGit"
        $result | Should -Contain "WPFInstallChatGPT"
        $result | Should -Not -Contain "WPFInstallMissing"
        Should -Invoke -CommandName winget -Times 1 -Exactly
        $script:wingetArguments | Should -Be @("list", "--accept-source-agreements", "--disable-interactivity")
    }

    It "corresponde a um pacote cujo nome é o mais largo na lista do winget" {
        Mock winget {
            $global:LASTEXITCODE = 0
            @(
                "Name                                                         Id                           Version       Source",
                "--------------------------------------------------------------------------------------------------------------",
                "Microsoft Visual C++ v14 Redistributable (x64) - 14.51.36247 Microsoft.VCRedist.2015+.x64 14.51.36247.0 winget",
                "Git                                                          Git.Git                      2.0           winget"
            )
        }
        $script:sync.configs.applicationsHashtable["WPFInstallvc2015_64"] = [pscustomobject]@{ winget = "Microsoft.VCRedist.2015+.x64"; choco = "vcredist2015" }

        $result = @(Invoke-WinUtilCurrentSystem -CheckBox "winget")

        $result | Should -HaveCount 2
        $result | Should -Contain "WPFInstallvc2015_64"
        $result | Should -Contain "WPFInstallGit"
        $result | Should -Not -Contain "WPFInstallMissing"
    }

    It "corresponde ao ID mais largo quando sua versão tem apenas um espaço anterior (<Mode>)" -TestCases @(
        @{ Mode = "winget" }
        @{ Mode = "choco" }
    ) {
        param($Mode)
        Mock winget {
            $global:LASTEXITCODE = 0
            @(
                "Name     Id           Version Source",
                "------------------------------------",
                "Git      Git.Git      2.0     winget",
                "ChatGPT  9NT1R1C2HH7J 1.0     msstore"
            )
        }

        $result = @(Invoke-WinUtilCurrentSystem -CheckBox $Mode)

        $result | Should -HaveCount 2
        $result | Should -Contain "WPFInstallGit"
        $result | Should -Contain "WPFInstallChatGPT"
        $result | Should -Not -Contain "WPFInstallMissing"
        Should -Invoke -CommandName winget -Times 1 -Exactly
    }

    It "corresponde a IDs apenas na coluna Id, não dentro de um nome de pacote" {
        Mock winget {
            $global:LASTEXITCODE = 0
            # "a" mais 16 acentos combinantes são 17 caracteres, mas uma coluna, o que coloca Git.Git na posição da coluna Id
            $accentedName = "a" + ([string][char]0x0301 * 16) + " Git.Git"
            @(
                "Name              Id         Version Source",
                "-------------------------------------------",
                "Some Git.Git Tool Other.Tool 1.0     winget",
                "$accentedName         Third.Tool 1.0     winget"
            )
        }
        $script:sync.configs.applicationsHashtable["WPFInstallOther"] = [pscustomobject]@{ winget = "Other.Tool"; choco = "na" }

        $result = @(Invoke-WinUtilCurrentSystem -CheckBox "winget")

        $result | Should -Be @("WPFInstallOther")
    }

    It "falha prontamente quando o Winget não consegue listar aplicativos" {
        Mock winget {
            $global:LASTEXITCODE = 1
            "winget failed"
        }

        { Invoke-WinUtilCurrentSystem -CheckBox "winget" } | Should -Throw "winget list falhou com o código de saída 1."
    }

    It "corresponde ao ID de pacote primário do Chocolatey em uma única chamada de listagem" {
        $result = @(Invoke-WinUtilCurrentSystem -CheckBox "choco")

        $result | Should -Be @("WPFInstallGit", "WPFInstallChatGPT")
        Should -Invoke -CommandName choco -Times 1 -Exactly
        $script:chocoArguments | Should -Be @("list")
    }

    It "verifica o WinGet apenas para aplicativos que o modo Chocolatey instala por meio do WinGet" {
        $apps = $script:sync.configs.applicationsHashtable
        $apps["WPFInstallVLC"] = [pscustomobject]@{ winget = "VideoLAN.VLC"; choco = "vlc" }
        $apps["WPFInstallNoChoco"] = [pscustomobject]@{ winget = "No.Choco"; choco = "" }
        $apps["WPFInstallAbsent"] = [pscustomobject]@{ winget = "Absent.App"; choco = "na" }
        $apps["WPFInstallNoSource"] = [pscustomobject]@{ winget = "na"; choco = "na" }
        $apps["WPFInstallNoChocoField"] = [pscustomobject]@{ winget = "No.Field" }
        Mock winget {
            $global:LASTEXITCODE = 0
            @(
                "Name  Id  Version  Source",
                "--------------------------------",
                "Git  Git.Git  2.0  winget",
                "ChatGPT  9NT1R1C2HH7J  1.0  msstore",
                "VLC  VideoLAN.VLC  3.0  winget",
                "No Choco  No.Choco  1.0  winget",
                "No Field  No.Field  1.0  winget"
            )
        }

        $result = @(Invoke-WinUtilCurrentSystem -CheckBox "choco")

        $result | Should -HaveCount 4
        $result | Should -Contain "WPFInstallGit"
        $result | Should -Contain "WPFInstallChatGPT"
        $result | Should -Contain "WPFInstallNoChoco"
        $result | Should -Contain "WPFInstallNoChocoField"
        Should -Invoke -CommandName choco -Times 1 -Exactly
        Should -Invoke -CommandName winget -Times 1 -Exactly
    }

    It "mantém os resultados do Chocolatey quando o WinGet não consegue listar aplicativos" {
        Mock winget {
            $global:LASTEXITCODE = 1
            "winget failed"
        }
        Mock Write-Warning { }

        $result = @(Invoke-WinUtilCurrentSystem -CheckBox "choco")

        $result | Should -Be @("WPFInstallGit")
        Should -Invoke -CommandName Write-Warning -Times 1 -Exactly -ParameterFilter { $Message -like "*WinGet*código de saída 1*" }
    }

    It "não executa o WinGet no modo Chocolatey quando nenhum aplicativo precisa dele" {
        $script:sync.configs.applicationsHashtable.Remove("WPFInstallChatGPT")
        $script:sync.configs.applicationsHashtable["WPFInstallNoSource"] = [pscustomobject]@{ winget = "na"; choco = "na" }

        $result = @(Invoke-WinUtilCurrentSystem -CheckBox "choco")

        $result | Should -Be @("WPFInstallGit")
        Should -Invoke -CommandName winget -Times 0 -Exactly
    }

    It "ignora a verificação do WinGet no modo Chocolatey quando o WinGet não está instalado" {
        Mock Test-WinUtilPackageManager { "not-installed" } -ParameterFilter { $winget }

        $result = @(Invoke-WinUtilCurrentSystem -CheckBox "choco")

        $result | Should -Be @("WPFInstallGit")
        Should -Invoke -CommandName winget -Times 0 -Exactly
    }
}

Describe "Invoke-WinUtilCurrentSystem ajustes de serviço" {
    BeforeEach {
        $script:sync = [Hashtable]::Synchronized(@{
            configs = @{
                tweaks = [pscustomobject]@{
                    WPFServiceTweak = [pscustomobject]@{
                        service = @([pscustomobject]@{ Name = "OptionalService"; StartupType = "Disabled" })
                    }
                }
            }
        })
        Mock Test-Path { $true }
        Mock Get-Service { $null }
    }

    AfterEach {
        Remove-Variable -Name sync -Scope Script -ErrorAction SilentlyContinue
    }

    It "tolera um serviço opcional ausente durante a detecção da interface" {
        @(Invoke-WinUtilCurrentSystem -CheckBox "tweaks") | Should -Be @("WPFServiceTweak")
    }

    It "marca um serviço ausente como uma divergência durante a coleta rigorosa de relatório" {
        @(Invoke-WinUtilCurrentSystem -CheckBox "tweaks" -StopOnReadError).Count | Should -Be 0
    }

    It "marca um ajuste como aplicado quando o tipo de inicialização do serviço corresponde" {
        Mock Get-Service { [pscustomobject]@{ StartType = "Disabled" } }
        @(Invoke-WinUtilCurrentSystem -CheckBox "tweaks") | Should -Be @("WPFServiceTweak")
    }
}

Describe "Set-WinUtilRegistry" {
    BeforeEach {
        $script:testPathResults = @{}

        Mock Write-Host { }
        Mock Write-Warning { }
        Mock Write-WinUtilLog { }
        Mock Test-Path {
            param([string]$Path)

            if ($script:testPathResults.ContainsKey($Path)) {
                return $script:testPathResults[$Path]
            }

            throw "Unexpected Test-Path call: $Path"
        }
        Mock New-PSDrive { }
        Mock New-Item { }
        Mock Set-ItemProperty { }
        Mock Remove-ItemProperty { }
        # Um valor existe a menos que um teste lance o erro do provedor para uma chave ou valor ausente
        Mock Get-ItemProperty { }
    }

    AfterEach {
        Remove-Variable -Name absentLookupError -Scope Script -ErrorAction SilentlyContinue
    }

    It "cria um caminho de registro ausente antes de definir um valor" {
        $registryPath = "HKCU:\Software\WinUtilTest"
        $script:testPathResults["HKU:\"] = $true
        $script:testPathResults[$registryPath] = $false

        Set-WinUtilRegistry -Path $registryPath -Name "Enabled" -Type "DWord" -Value "1"

        Should -Invoke -CommandName New-PSDrive -Times 0 -Exactly
        Should -Invoke -CommandName New-Item -Times 1 -Exactly -ParameterFilter {
            $Path -eq $registryPath -and $Force -eq $true -and $ErrorAction -eq "Stop"
        }
        Should -Invoke -CommandName Set-ItemProperty -Times 1 -Exactly -ParameterFilter {
            $Path -eq $registryPath -and
                $Name -eq "Enabled" -and
                $Type -eq "DWord" -and
                $Value -eq "1" -and
                $Force -eq $true -and
                $ErrorAction -eq "Stop"
        }
        Should -Invoke -CommandName Remove-ItemProperty -Times 0 -Exactly
    }

    It "cria a PSDrive HKU quando ela está ausente" {
        $registryPath = "HKCU:\Software\WinUtilTest"
        $script:testPathResults["HKU:\"] = $false
        $script:testPathResults[$registryPath] = $true

        Set-WinUtilRegistry -Path $registryPath -Name "Enabled" -Type "DWord" -Value "1"

        Should -Invoke -CommandName New-PSDrive -Times 1 -Exactly -ParameterFilter {
            $PSProvider -eq "Registry" -and
                $Name -eq "HKU" -and
                $Root -eq "HKEY_USERS"
        }
        Should -Invoke -CommandName New-Item -Times 0 -Exactly
        Should -Invoke -CommandName Set-ItemProperty -Times 1 -Exactly -ParameterFilter {
            $Path -eq $registryPath -and $Name -eq "Enabled" -and $Type -eq "DWord" -and $Value -eq "1"
        }
    }

    It "remove um valor do registro quando solicitado" {
        $registryPath = "HKLM:\Software\WinUtilTest"
        $script:testPathResults["HKU:\"] = $true
        $script:testPathResults[$registryPath] = $true
        Mock Get-ItemProperty { [pscustomobject]@{ ObsoleteValue = "old" } } -ParameterFilter {
            $Path -eq $registryPath -and $Name -eq "ObsoleteValue"
        }

        Set-WinUtilRegistry -Path $registryPath -Name "ObsoleteValue" -Type "String" -Value "<RemoveEntry>"

        Should -Invoke -CommandName Set-ItemProperty -Times 0 -Exactly
        Should -Invoke -CommandName Remove-ItemProperty -Times 1 -Exactly -ParameterFilter {
            $Path -eq $registryPath -and
                $Name -eq "ObsoleteValue" -and
                $Force -eq $true -and
                $ErrorAction -eq "Stop"
        }
    }

    It "trata um <Reason> ausente como um valor que já foi removido" -ForEach @(
        @{ Reason = "value"; LookupError = [System.Management.Automation.PSArgumentException]::new("Property MissingValue does not exist at path HKEY_CURRENT_USER\Software\WinUtilTest.") }
        @{ Reason = "key"; LookupError = [System.Management.Automation.ItemNotFoundException]::new("Cannot find path 'HKCU:\Software\WinUtilTest' because it does not exist.") }
    ) {
        # Remove-ItemProperty em um valor ausente gera PSArgumentException, que o
        # catch genérico registrava como erro, então reverter um ajuste nunca aplicado falhava (#5145).
        # Apenas a verificação do HKU é esperada: o caminho não deve ser criado só para não remover nada.
        $registryPath = "HKCU:\Software\WinUtilTest"
        $script:testPathResults["HKU:\"] = $true
        $script:absentLookupError = $LookupError
        Mock Get-ItemProperty { throw $script:absentLookupError }

        Set-WinUtilRegistry -Path $registryPath -Name "MissingValue" -Type "DWord" -Value "<RemoveEntry>"

        Should -Invoke -CommandName Get-ItemProperty -Times 1 -Exactly -ParameterFilter {
            $Path -eq $registryPath -and $Name -eq "MissingValue" -and $ErrorAction -eq "Stop"
        }
        Should -Invoke -CommandName New-Item -Times 0 -Exactly
        Should -Invoke -CommandName Remove-ItemProperty -Times 0 -Exactly
        Should -Invoke -CommandName Write-Warning -Times 0 -Exactly
        Should -Invoke -CommandName Write-WinUtilLog -Times 0 -Exactly -ParameterFilter { $Level -eq "ERROR" }
        Should -Invoke -CommandName Write-WinUtilLog -Times 1 -Exactly -ParameterFilter { $Message -like "*já está ausente*" }
    }

    It "relata uma falha de consulta em vez de tratar o valor como ausente" {
        # Acesso negado não é "nada a remover": os manipuladores existentes precisam vê-lo
        $registryPath = "HKLM:\SECURITY\WinUtilTest"
        $script:testPathResults["HKU:\"] = $true
        Mock Get-ItemProperty { throw [System.UnauthorizedAccessException]::new("Requested registry access is not allowed.") }

        Set-WinUtilRegistry -Path $registryPath -Name "Protected" -Type "DWord" -Value "<RemoveEntry>"

        Should -Invoke -CommandName New-Item -Times 0 -Exactly
        Should -Invoke -CommandName Remove-ItemProperty -Times 0 -Exactly
        Should -Invoke -CommandName Write-WinUtilLog -Times 0 -Exactly -ParameterFilter { $Message -like "*já está ausente*" }
        Should -Invoke -CommandName Write-WinUtilLog -Times 1 -Exactly -ParameterFilter {
            $Level -eq "ERROR" -and $Message -like "Sem autorização ao alterar $registryPath\Protected*"
        }
        Should -Invoke -CommandName Write-Warning -Times 1 -Exactly
    }

}

Describe "Set-WinUtilService" {
    BeforeEach {
        Mock Write-Host { }
        Mock Write-Warning { }
        Mock Write-WinUtilLog { }
        Mock Get-Service { }
        Mock Set-Service { }
    }

    It "define o tipo de inicialização de um serviço existente" {
        Mock Get-Service {
            [pscustomobject]@{
                Name = "DiagTrack"
                StartType = "Automatic"
            }
        } -ParameterFilter { $Name -eq "DiagTrack" -and $ErrorAction -eq "Stop" }

        Set-WinUtilService -Name "DiagTrack" -StartupType "Disabled"

        Should -Invoke -CommandName Get-Service -Times 1 -Exactly -ParameterFilter {
            $Name -eq "DiagTrack" -and $ErrorAction -eq "Stop"
        }
        Should -Invoke -CommandName Set-Service -Times 1 -Exactly -ParameterFilter {
            $StartupType -eq "Disabled" -and $ErrorAction -eq "Stop"
        }
    }

    It "não altera um serviço que já tem o tipo de inicialização solicitado" {
        Mock Get-Service {
            [pscustomobject]@{
                Name = "DiagTrack"
                StartType = "Disabled"
            }
        } -ParameterFilter { $Name -eq "DiagTrack" -and $ErrorAction -eq "Stop" }

        Set-WinUtilService -Name "DiagTrack" -StartupType "Disabled"

        Should -Invoke -CommandName Get-Service -Times 1 -Exactly
        Should -Invoke -CommandName Set-Service -Times 0 -Exactly
    }

    It "não chama Set-Service quando o serviço está ausente" {
        Mock Get-Service {
            $exception = [Microsoft.PowerShell.Commands.ServiceCommandException]::new("Cannot find any service with service name '$Name'.")
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                $exception,
                "NoServiceFoundForGivenName,Microsoft.PowerShell.Commands.GetServiceCommand",
                [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                $Name
            )
            throw $errorRecord
        } -ParameterFilter { $Name -eq "MissingService" -and $ErrorAction -eq "Stop" }

        Set-WinUtilService -Name "MissingService" -StartupType "Disabled"

        Should -Invoke -CommandName Get-Service -Times 1 -Exactly -ParameterFilter {
            $Name -eq "MissingService" -and $ErrorAction -eq "Stop"
        }
        Should -Invoke -CommandName Set-Service -Times 0 -Exactly
        Should -Invoke -CommandName Write-Warning -Times 1 -Exactly -ParameterFilter {
            $Message -eq "O serviço MissingService não foi encontrado."
        }
    }
}
