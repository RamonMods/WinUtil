Describe "Atualização MSI do PowerShell" {
    BeforeAll {
        . "$PSScriptRoot/../functions/private/Install-WinUtilProgramWinget.ps1"
        . "$PSScriptRoot/../functions/private/Write-WinUtilLog.ps1"
    }

    BeforeEach {
        Mock Test-WinUtilPowerShellMSIUpgradeAllowed { $true }
        Mock Write-WinUtilLog {}
        Mock Write-Host {}
        Mock Test-Path { $true }
        Mock Remove-Item {}

        Mock Get-ItemProperty {
            [pscustomobject]@{
                WindowsInstaller = 1
                DisplayName = "PowerShell 7-x64"
                InstallLocation = "C:\Program Files\PowerShell\7"
                DisplayVersion = "7.5.2"
            }
        }

        Mock Get-WinUtilPowerShellVersion { "7.5.2" }
        Mock Get-WinUtilPowerShellArchitecture { "X64" }
        Mock Start-Process { [pscustomobject]@{ ExitCode = 0 } }

        Mock Invoke-RestMethod {
            [pscustomobject]@{
                tag_name = "v7.5.3"
                assets = @(
                    [pscustomobject]@{
                        name = "PowerShell-7.5.3-win-x64.msi"
                        browser_download_url = "https://example.com/PowerShell.msi"
                        digest = $null
                    }
                )
            }
        }

        Mock Invoke-WebRequest {}
        Mock Get-AuthenticodeSignature {
            [pscustomobject]@{
                Status = "Valid"
                SignerCertificate = [pscustomobject]@{
                    Subject = "CN=Microsoft Corporation"
                }
            }
        }
    }

    It "atualiza o PowerShell MSI com sucesso" {
        Mock Start-Process { [pscustomobject]@{ ExitCode = 0 } }

        $result = Update-WinUtilPowerShellMSI

        $result.Outcome | Should -Be "Succeeded"
        Should -Invoke Invoke-WebRequest -Times 1
        Should -Invoke Get-AuthenticodeSignature -Times 1
        Should -Invoke Start-Process -Times 1
    }

    It "trata o código de saída de reinício <Code> como sucesso" -TestCases @(@{ Code = 3010 }, @{ Code = 1641 }) {
        param($Code)
        Mock Start-Process { [pscustomobject]@{ ExitCode = $Code } }
        $result = Update-WinUtilPowerShellMSI
        $result.Outcome | Should -Be "Succeeded"
        $result.ExitCode | Should -Be $Code
        $expected = if ($Code -eq 3010) { 'é preciso reiniciar para concluir' } else { 'o instalador iniciou uma reinicialização' }
        $result.Detail | Should -Match $expected
        Should -Invoke Write-Host -Times 1 -Exactly -ParameterFilter { $Object -match $expected }
        Should -Invoke Write-WinUtilLog -Times 1 -Exactly -ParameterFilter { $Message -match $expected }
        Should -Invoke Start-Process -Times 1 -Exactly
    }

    It "informa falha na instalação MSI" {
        Mock Start-Process { [pscustomobject]@{ ExitCode = 1603 } }

        $result = Update-WinUtilPowerShellMSI

        $result.Outcome | Should -Be "Failed"
        Should -Invoke Write-WinUtilLog -ParameterFilter {
            $Level -eq "ERROR"
        }
    }

    It "ignora o download quando o PowerShell já está atualizado" {
        Mock Get-WinUtilPowerShellVersion { "7.5.3" }
        Mock Start-Process { [pscustomobject]@{ ExitCode = 0 } }

        $result = Update-WinUtilPowerShellMSI

        $result.Outcome | Should -Be "Skipped"
        Should -Invoke Invoke-WebRequest -Times 0
        Should -Invoke Start-Process -Times 0
    }

    It "retorna NotInstalled quando o PowerShell não foi instalado por MSI" {
        Mock Get-ItemProperty { $null }

        $result = Update-WinUtilPowerShellMSI

        $result.Outcome | Should -Be "NotInstalled"
        Should -Invoke Invoke-RestMethod -Times 0
        Should -Invoke Start-Process -Times 0
    }

    It "rejeita um certificado de assinante inválido ou ausente" {
        Mock Get-AuthenticodeSignature {
            [pscustomobject]@{
                Status = "NotTrusted"
                SignerCertificate = $null
            }
        }

        Mock Start-Process { [pscustomobject]@{ ExitCode = 0 } }

        $result = Update-WinUtilPowerShellMSI

        $result.Outcome | Should -Be "Failed"
        Should -Invoke Start-Process -Times 0
    }

    It "rejeita um certificado não Microsoft que contém Microsoft" {
        Mock Get-AuthenticodeSignature {
            [pscustomobject]@{
                Status = "Valid"
                SignerCertificate = [pscustomobject]@{
                    Subject = "CN=Microsoft Malware Research"
                }
            }
        }

        Mock Start-Process { [pscustomobject]@{ ExitCode = 0 } }

        $result = Update-WinUtilPowerShellMSI

        $result.Outcome | Should -Be "Failed"
        Should -Invoke Start-Process -Times 0
    }

    It "rejeita um digest SHA256 incompatível" {
        Mock Invoke-RestMethod {
            [pscustomobject]@{
                tag_name = "v7.5.3"
                assets = @(
                    [pscustomobject]@{
                        name = "PowerShell-7.5.3-win-x64.msi"
                        browser_download_url = "https://example.com/PowerShell.msi"
                        digest = "sha256:0000000000000000000000000000000000000000000000000000000000000000"
                    }
                )
            }
        }

        Mock Get-FileHash {
            [pscustomobject]@{
                Hash = "1111111111111111111111111111111111111111111111111111111111111111"
            }
        }

        Mock Start-Process { [pscustomobject]@{ ExitCode = 0 } }

        $result = Update-WinUtilPowerShellMSI

        $result.Outcome | Should -Be "Failed"
        Should -Invoke Start-Process -Times 0
    }

    It "usa MSI para Instalar e Atualizar o PowerShell selecionado" {
        Mock Start-Process { [pscustomobject]@{ ExitCode = 0 } }

        foreach ($action in @("Install", "Upgrade")) {
            $result = Install-WinUtilProgramWinget `
                -Action $action `
                -Programs @("Microsoft.PowerShell")

            $result.Package | Should -Be "Microsoft.PowerShell"
            $result.Manager | Should -Be "msi"
            $result.Outcome | Should -Be "Succeeded"
        }

        Should -Invoke Start-Process -Times 2
    }

    It "recorre ao WinGet quando o PowerShell não foi instalado por MSI" {
        Mock Get-ItemProperty { $null }
        Mock Start-Process { [pscustomobject]@{ ExitCode = 0 } }

        $result = Install-WinUtilProgramWinget `
            -Action Upgrade `
            -Programs @("Microsoft.PowerShell")

        $result.Manager | Should -Be "winget"
        $result.Outcome | Should -Be "Succeeded"
        Should -Invoke Start-Process -Times 1
    }

    It "não recai para o WinGet após o tratamento MSI" {
        Mock Start-Process { [pscustomobject]@{ ExitCode = 0 } }

        $result = Install-WinUtilProgramWinget `
            -Action Upgrade `
            -Programs @("Microsoft.PowerShell")

        $result.Manager | Should -Be "msi"
        $result.Outcome | Should -Be "Succeeded"

        Should -Invoke Start-Process -Times 1 -ParameterFilter {
            $FilePath -eq "msiexec.exe"
        }
    }

    It "informa o tratamento MSI e ainda atualiza outros pacotes com o WinGet all" {
        $result = @(Install-WinUtilProgramWinget -Action Upgrade -Programs @("all"))
        $result.Count | Should -Be 2
        $result[0].Manager | Should -Be "msi"
        $result[0].Outcome | Should -Be "Succeeded"
        $result[1].Manager | Should -Be "winget"
        Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter {
            $FilePath -eq "winget" -and $ArgumentList -contains "--all"
        }
    }

    It "informa falhas MSI mesmo quando as demais atualizações têm sucesso" {
        Mock Update-WinUtilPowerShellMSI { [pscustomobject]@{ Outcome = 'Failed'; ExitCode = -1; Detail = 'failed' } }
        $result = @(Install-WinUtilProgramWinget -Action Upgrade -Programs @('all'))
        $result[0].Outcome | Should -Be 'Failed'
        $result[1].Outcome | Should -Be 'Succeeded'
    }

    It "resolve o registro MSI oficial pelo ProductCode sem desinstalar o InstallLocation" {
        Mock Get-ItemProperty {
            [pscustomobject]@{ WindowsInstaller = 1; DisplayName = 'PowerShell 7-x64'; PSChildName = '{stable-product}' }
        } -ParameterFilter { $Path[0] -like '*Uninstall*' }
        Mock Get-ItemProperty {
            @(
                [pscustomobject]@{ ProductCode = '{other-product}'; InstallLocation = 'C:\Wrong' },
                [pscustomobject]@{ ProductCode = '{stable-product}'; InstallLocation = 'C:\Custom\PowerShell\7' }
            )
        } -ParameterFilter { $Path[0] -like '*InstalledVersions*' }
        (Update-WinUtilPowerShellMSI).Outcome | Should -Be 'Succeeded'
        Should -Invoke Get-WinUtilPowerShellVersion -Times 1 -Exactly -ParameterFilter { $Path -eq 'C:\Custom\PowerShell\7\pwsh.exe' }
    }

    It "não baixa um MSI quando há pins ou não é possível verificá-los" {
        Mock Test-WinUtilPowerShellMSIUpgradeAllowed { $false }
        (Update-WinUtilPowerShellMSI).Outcome | Should -Be 'Skipped'
        Should -Invoke Invoke-RestMethod -Times 0 -Exactly
        Should -Invoke Start-Process -Times 0 -Exactly
    }

    It "informa instalações MSI lado a lado não suportadas sem atualizar nenhuma" {
        Mock Get-ItemProperty {
            @(
                [pscustomobject]@{ WindowsInstaller = 1; DisplayName = 'PowerShell 7-x64'; InstallLocation = 'C:\PowerShell-x64\7' },
                [pscustomobject]@{ WindowsInstaller = 1; DisplayName = 'PowerShell 7-x86'; InstallLocation = 'C:\PowerShell-x86\7' }
            )
        }
        $result = Install-WinUtilProgramWinget -Action Install -Programs @('Microsoft.PowerShell')
        $result.Outcome | Should -Be 'Failed'
        $result.Detail | Should -Match 'Várias instalações estáveis do PowerShell via MSI'
        Should -Invoke Invoke-RestMethod -Times 0 -Exactly
        Should -Invoke Start-Process -Times 0 -Exactly
    }

    It "não trata o registro duplicado de um caminho como várias instalações" {
        Mock Get-ItemProperty {
            @(
                [pscustomobject]@{ WindowsInstaller = 1; DisplayName = 'PowerShell 7-x64'; InstallLocation = 'C:\PowerShell\7' },
                [pscustomobject]@{ WindowsInstaller = 1; DisplayName = 'PowerShell 7-x64'; InstallLocation = 'C:\powershell\7\' }
            )
        }
        (Update-WinUtilPowerShellMSI).Outcome | Should -Be 'Succeeded'
        Should -Invoke Start-Process -Times 1 -Exactly
    }

    It "corresponde a nomes MSI oficiais com versão" {
        Mock Get-ItemProperty { [pscustomobject]@{ WindowsInstaller = 1; DisplayName = 'PowerShell 7.5.2.0-x64'; InstallLocation = 'C:\PowerShell\7' } }
        (Update-WinUtilPowerShellMSI).Outcome | Should -Be 'Succeeded'
    }

    It "usa a arquitetura x86 instalada em uma arquitetura de host diferente" {
        Mock Get-WinUtilPowerShellArchitecture { 'X86' }
        Mock Invoke-RestMethod { [pscustomobject]@{ tag_name = 'v7.5.3'; assets = @(
            [pscustomobject]@{ name = 'PowerShell-7.5.3-win-x86.msi'; browser_download_url = 'https://example.com/x86.msi' },
            [pscustomobject]@{ name = 'PowerShell-7.5.3-win-x64.msi'; browser_download_url = 'https://example.com/x64.msi' }
        ) } }
        (Update-WinUtilPowerShellMSI).Outcome | Should -Be 'Succeeded'
        Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter { $Uri -eq 'https://example.com/x86.msi' }
    }

    It "ignora instalações de versão prévia do PowerShell" {
        Mock Get-ItemProperty {
            @(
                [pscustomobject]@{
                    WindowsInstaller = 1
                    DisplayName = "PowerShell 7-preview"
                    InstallLocation = "C:\PowerShell\preview"
                    DisplayVersion = "7.6.0-preview"
                },
                [pscustomobject]@{
                    WindowsInstaller = 1
                    DisplayName = "PowerShell 7-x64"
                    InstallLocation = "C:\PowerShell\7"
                    DisplayVersion = "7.5.2"
                }
            )
        }

        $result = Update-WinUtilPowerShellMSI

        $result.Outcome | Should -Not -Be "NotInstalled"
    }
}

Describe "Proteção de pin do MSI" {
    BeforeAll {
        . "$PSScriptRoot/../functions/private/Install-WinUtilProgramWinget.ps1"
        function winget { }
    }
    It "permite MSI somente quando a listagem de pins tem sucesso sem uma tabela" {
        Mock winget { $global:LASTEXITCODE = 0; 'No pins exist.' }
        Test-WinUtilPowerShellMSIUpgradeAllowed | Should -BeTrue
    }
    It "bloqueia MSI para uma tabela de pins localizada" {
        Mock winget { $global:LASTEXITCODE = 0; "Nom ID Version`n-------------------`nPowerShell Microsoft.PowerShell 7.5" }
        Test-WinUtilPowerShellMSIUpgradeAllowed | Should -BeFalse
    }
    It "bloqueia MSI quando o comando de pin falha" {
        Mock winget { $global:LASTEXITCODE = 1; 'error' }
        Test-WinUtilPowerShellMSIUpgradeAllowed | Should -BeFalse
    }
    It "bloqueia MSI quando o comando de pin não produz saída" {
        Mock winget { $global:LASTEXITCODE = 0 }
        Test-WinUtilPowerShellMSIUpgradeAllowed | Should -BeFalse
    }
}
