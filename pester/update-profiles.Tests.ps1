#===========================================================================
# Testes - Perfis do Windows Update
#===========================================================================

BeforeAll {
    $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
    . (Join-Path $script:repoRoot "functions\public\Invoke-WPFUpdatesdisable.ps1")
    . (Join-Path $script:repoRoot "functions\public\Invoke-WPFUpdatesdefault.ps1")
    . (Join-Path $script:repoRoot "functions\public\Invoke-WPFUpdatessecurity.ps1")

    function Write-WinUtilLog {
        param($Message, $Level, $Component)
    }
    function Show-WinUtilMessage {
        param($Message, $Title, $Button, $Icon)
    }
    function Get-ScheduledTask {
        param($TaskPath, $ErrorAction)
    }
    function Disable-ScheduledTask {
        param(
            [Parameter(ValueFromPipeline = $true)]
            $InputObject,
            $ErrorAction
        )
        process { }
    }
    function Enable-ScheduledTask {
        param(
            [Parameter(ValueFromPipeline = $true)]
            $InputObject,
            $ErrorAction
        )
        process { }
    }
    function secedit {
        param(
            [Parameter(ValueFromRemainingArguments = $true)]
            $Arguments
        )
    }

    $script:updateTaskPaths = @(
        '\Microsoft\Windows\InstallService\*',
        '\Microsoft\Windows\UpdateOrchestrator\*',
        '\Microsoft\Windows\UpdateAssistant\*',
        '\Microsoft\Windows\WaaSMedic\*',
        '\Microsoft\Windows\WindowsUpdate\*',
        '\Microsoft\WindowsUpdate\*'
    )

    function Get-TestServiceKeyAcl {
        param(
            [string[]]$DenySid = @()
        )

        $acl = New-Object System.Security.AccessControl.RegistrySecurity
        $allowSystem = New-Object System.Security.AccessControl.RegistryAccessRule(
            (New-Object System.Security.Principal.SecurityIdentifier("S-1-5-18")),
            [System.Security.AccessControl.RegistryRights]::FullControl,
            [System.Security.AccessControl.InheritanceFlags]::None,
            [System.Security.AccessControl.PropagationFlags]::None,
            [System.Security.AccessControl.AccessControlType]::Allow
        )
        $acl.AddAccessRule($allowSystem)

        foreach ($sid in $DenySid) {
            $denyRule = New-Object System.Security.AccessControl.RegistryAccessRule(
                (New-Object System.Security.Principal.SecurityIdentifier($sid)),
                [System.Security.AccessControl.RegistryRights]"SetValue, CreateSubKey, Delete",
                [System.Security.AccessControl.InheritanceFlags]::None,
                [System.Security.AccessControl.PropagationFlags]::None,
                [System.Security.AccessControl.AccessControlType]::Deny
            )
            $acl.AddAccessRule($denyRule)
        }

        return $acl
    }

    $script:updateServiceKeys = @("BITS", "wuauserv", "UsoSvc", "WaaSMedicSvc") | ForEach-Object {
        "HKLM:\SYSTEM\CurrentControlSet\Services\$_"
    }
}

Describe "Invoke-WPFUpdatesdisable" {
    BeforeEach {
        Mock Write-Host { }
        Mock Write-WinUtilLog { }
        Mock Show-WinUtilMessage { "Yes" }
        Mock Test-Path { $false }
        Mock New-Item { }
        Mock Set-ItemProperty { }
        Mock Set-Service { }
        Mock Stop-Service { }
        Mock Remove-Item { }
        Mock Get-ScheduledTask {
            [pscustomobject]@{
                TaskPath = $TaskPath
            }
        }
        Mock Disable-ScheduledTask { }
    }

    It "define valores de política do registro para desativar atualizações" {
        Invoke-WPFUpdatesdisable

        Should -Invoke -CommandName New-Item -Times 1 -Exactly -ParameterFilter {
            $Path -eq "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -and $Force -eq $true
        }
        Should -Invoke -CommandName Set-ItemProperty -Times 1 -Exactly -ParameterFilter {
            $Path -eq "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -and
                $Name -eq "NoAutoUpdate" -and
                $Type -eq "DWord" -and
                $Value -eq 1
        }
        Should -Invoke -CommandName Set-ItemProperty -Times 1 -Exactly -ParameterFilter {
            $Path -eq "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -and
                $Name -eq "AUOptions" -and
                $Type -eq "DWord" -and
                $Value -eq 1
        }
        Should -Invoke -CommandName Set-ItemProperty -Times 1 -Exactly -ParameterFilter {
            $Path -eq "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config" -and
                $Name -eq "DODownloadMode" -and
                $Type -eq "DWord" -and
                $Value -eq 0
        }
    }

    It "mantém chaves de política existentes em vez de recriá-las" {
        Mock Test-Path { $true }

        Invoke-WPFUpdatesdisable

        Should -Not -Invoke New-Item
        Should -Invoke -CommandName Set-ItemProperty -Times 1 -Exactly -ParameterFilter {
            $Path -eq "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -and
                $Name -eq "NoAutoUpdate" -and
                $Value -eq 1
        }
    }

    It "desativa serviços de atualização e limpa a pasta SoftwareDistribution" {
        Invoke-WPFUpdatesdisable

        foreach ($expectedServiceName in @("BITS", "wuauserv", "UsoSvc")) {
            $expected = $expectedServiceName
            Should -Invoke -CommandName Stop-Service -Times 1 -Exactly -ParameterFilter {
                $Name -eq $expected -and $Force -eq $true
            }
        }
        Should -Invoke -CommandName Set-Service -Times 1 -Exactly -ParameterFilter {
            $Name -eq "BITS" -and $StartupType -eq "Disabled"
        }
        Should -Invoke -CommandName Set-Service -Times 1 -Exactly -ParameterFilter {
            $Name -eq "wuauserv" -and $StartupType -eq "Disabled"
        }
        Should -Invoke -CommandName Set-Service -Times 1 -Exactly -ParameterFilter {
            $Name -eq "UsoSvc" -and $StartupType -eq "Disabled"
        }
        Should -Invoke -CommandName Remove-Item -Times 1 -Exactly -ParameterFilter {
            $Path -eq "C:\Windows\SoftwareDistribution\*" -and
                $Recurse -eq $true -and
                $Force -eq $true
        }
    }

    It "desativa os caminhos das tarefas agendadas de atualização" {
        Invoke-WPFUpdatesdisable

        foreach ($expectedTaskPath in $script:updateTaskPaths) {
            $expected = $expectedTaskPath
            Should -Invoke -CommandName Get-ScheduledTask -Times 1 -Exactly -ParameterFilter {
                $TaskPath -eq $expected
            }
        }
        Should -Invoke -CommandName Disable-ScheduledTask -Times $script:updateTaskPaths.Count -Exactly
    }

    It "exige confirmação antes de desativar atualizações" {
        Mock Show-WinUtilMessage { "No" }

        Invoke-WPFUpdatesdisable

        Should -Invoke Show-WinUtilMessage -Times 1 -Exactly -ParameterFilter {
            $Title -eq "Desativar o Windows Update?" -and
                $Button -eq "YesNo" -and
                $Icon -eq "Warning"
        }
        Should -Not -Invoke Set-ItemProperty
        Should -Not -Invoke Set-Service
        Should -Not -Invoke Remove-Item
    }
}

Describe "Invoke-WPFUpdatesdefault" {
    BeforeEach {
        Mock Write-Host { }
        Mock Write-WinUtilLog { }
        Mock Remove-Item { }
        Mock Remove-ItemProperty { }
        Mock Get-ItemProperty {
            [pscustomobject]@{
                SettingsPageVisibility = "hide:windowsupdate"
            }
        }
        Mock Set-Service { }
        Mock Start-Service { }
        Mock Set-ItemProperty { }
        Mock Get-Acl { Get-TestServiceKeyAcl }
        Mock Set-Acl { }
        Mock Get-ScheduledTask {
            [pscustomobject]@{
                TaskPath = $TaskPath
            }
        }
        Mock Enable-ScheduledTask { }
        Mock secedit { }
    }

    It "remove apenas valores do registro gerenciados pelo WinUtil" {
        Invoke-WPFUpdatesdefault

        $expectedRegistryValues = @(
            @("HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU", "NoAutoUpdate", "AUOptions", "NoAutoRebootWithLoggedOnUsers", "AUPowerManagement"),
            @("HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate", "ExcludeWUDriversInQualityUpdate", "DeferFeatureUpdates", "DeferFeatureUpdatesPeriodInDays", "DeferQualityUpdates", "DeferQualityUpdatesPeriodInDays"),
            @("HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings", "BranchReadinessLevel", "DeferFeatureUpdatesPeriodInDays", "DeferQualityUpdatesPeriodInDays"),
            @("HKLM:\SOFTWARE\Policies\Microsoft\Windows\Device Metadata", "PreventDeviceMetadataFromNetwork"),
            @("HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching", "DontPromptForWindowsUpdate", "DontSearchWindowsUpdate", "DriverUpdateWizardWuSearchEnabled"),
            @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config", "DODownloadMode")
        )

        foreach ($expectedEntry in $expectedRegistryValues) {
            $expectedPath = $expectedEntry[0]
            foreach ($expectedName in $expectedEntry[1..($expectedEntry.Count - 1)]) {
                $valueName = $expectedName
                Should -Invoke -CommandName Remove-ItemProperty -Times 1 -Exactly -ParameterFilter {
                    $Path -eq $expectedPath -and $Name -eq $valueName
                }
            }
        }
        Should -Not -Invoke Remove-Item
        Should -Invoke -CommandName Remove-ItemProperty -Times 1 -Exactly -ParameterFilter {
            $Path -eq "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" -and
                $Name -eq "SettingsPageVisibility"
        }
    }

    It "preserva a política de visibilidade da página Settings não relacionada" {
        Mock Get-ItemProperty {
            [pscustomobject]@{
                SettingsPageVisibility = "hide:privacy"
            }
        }

        Invoke-WPFUpdatesdefault

        Should -Not -Invoke Remove-ItemProperty -ParameterFilter {
            $Path -eq "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" -and
                $Name -eq "SettingsPageVisibility"
        }
    }

    It "restaura os tipos de inicialização dos serviços de atualização" {
        Invoke-WPFUpdatesdefault

        Should -Invoke -CommandName Set-Service -Times 1 -Exactly -ParameterFilter {
            $Name -eq "BITS" -and $StartupType -eq "Manual"
        }
        Should -Invoke -CommandName Set-Service -Times 1 -Exactly -ParameterFilter {
            $Name -eq "wuauserv" -and $StartupType -eq "Manual"
        }
        Should -Invoke -CommandName Start-Service -Times 1 -Exactly -ParameterFilter {
            $Name -eq "UsoSvc"
        }
        Should -Invoke -CommandName Set-Service -Times 1 -Exactly -ParameterFilter {
            $Name -eq "UsoSvc" -and $StartupType -eq "Automatic"
        }
        Should -Not -Invoke Set-Service -ParameterFilter {
            $Name -eq "WaaSMedicSvc"
        }
    }

    It "restaura o WaaSMedicSvc por meio de seu valor de inicialização no registro" {
        Invoke-WPFUpdatesdefault

        Should -Invoke -CommandName Set-ItemProperty -Times 1 -Exactly
        Should -Invoke -CommandName Set-ItemProperty -Times 1 -Exactly -ParameterFilter {
            $Path -eq "HKLM:\SYSTEM\CurrentControlSet\Services\WaaSMedicSvc" -and
                $Name -eq "Start" -and
                $Type -eq "DWord" -and
                $Value -eq 3
        }
    }

    It "não altera o WaaSMedicSvc quando ele já está como Manual" {
        Mock Get-ItemProperty {
            [pscustomobject]@{ Start = 3 }
        } -ParameterFilter { $Name -eq "Start" }

        Invoke-WPFUpdatesdefault

        Should -Not -Invoke Set-ItemProperty
    }

    It "avisa e continua quando o WaaSMedicSvc não pode ser restaurado" {
        Mock Set-ItemProperty { throw "Requested registry access is not allowed." }

        { Invoke-WPFUpdatesdefault } | Should -Not -Throw

        Should -Invoke -CommandName Write-WinUtilLog -Times 1 -Exactly -ParameterFilter {
            $Level -eq "WARN" -and $Message -like "*WaaSMedicSvc*Requested registry access*"
        }
        Should -Invoke -CommandName Enable-ScheduledTask -Times $script:updateTaskPaths.Count -Exactly
    }

    It "remove apenas regras de negação de SYSTEM das chaves dos serviços de atualização" {
        Mock Get-Acl { Get-TestServiceKeyAcl -DenySid "S-1-5-18", "S-1-1-0" }
        $script:savedAcls = @{}
        Mock Set-Acl { $script:savedAcls["$Path"] = $AclObject }

        Invoke-WPFUpdatesdefault

        Should -Invoke -CommandName Set-Acl -Times $script:updateServiceKeys.Count -Exactly
        foreach ($serviceKey in $script:updateServiceKeys) {
            $remainingRules = $script:savedAcls[$serviceKey].GetAccessRules($true, $false, [System.Security.Principal.SecurityIdentifier])
            $denied = @($remainingRules | Where-Object { $_.AccessControlType -eq "Deny" } | ForEach-Object { $_.IdentityReference.Value })
            $allowed = @($remainingRules | Where-Object { $_.AccessControlType -eq "Allow" } | ForEach-Object { $_.IdentityReference.Value })

            $denied | Should -Be @("S-1-1-0")
            $allowed | Should -Be @("S-1-5-18")
        }
    }

    It "limpa as regras de negação de SYSTEM antes de alterar os tipos de inicialização dos serviços" {
        Mock Get-Acl { Get-TestServiceKeyAcl -DenySid "S-1-5-18" }
        $script:restoreOrder = [System.Collections.Generic.List[string]]::new()
        Mock Set-Acl { $script:restoreOrder.Add("Set-Acl") }
        Mock Set-Service { $script:restoreOrder.Add("Set-Service") }
        Mock Set-ItemProperty { $script:restoreOrder.Add("Set-ItemProperty") }

        Invoke-WPFUpdatesdefault

        $lastAclWrite = $script:restoreOrder.LastIndexOf("Set-Acl")
        $lastAclWrite | Should -BeLessThan $script:restoreOrder.IndexOf("Set-Service")
        $lastAclWrite | Should -BeLessThan $script:restoreOrder.IndexOf("Set-ItemProperty")
    }

    It "não altera as permissões das chaves de serviço quando SYSTEM não está negado" {
        Mock Get-Acl { Get-TestServiceKeyAcl -DenySid "S-1-1-0" }

        Invoke-WPFUpdatesdefault

        Should -Not -Invoke Set-Acl
    }

    It "avisa e continua quando as permissões das chaves de serviço não podem ser alteradas" {
        Mock Get-Acl { Get-TestServiceKeyAcl -DenySid "S-1-5-18" }
        Mock Set-Acl { throw "Requested registry access is not allowed." }

        { Invoke-WPFUpdatesdefault } | Should -Not -Throw

        foreach ($serviceName in @("BITS", "wuauserv", "UsoSvc", "WaaSMedicSvc")) {
            $expected = $serviceName
            Should -Invoke -CommandName Write-WinUtilLog -Times 1 -Exactly -ParameterFilter {
                $Level -eq "WARN" -and $Message -like "*$expected*Requested registry access*"
            }
        }
        Should -Invoke -CommandName Set-Service -Times 1 -Exactly -ParameterFilter {
            $Name -eq "wuauserv" -and $StartupType -eq "Manual"
        }
    }

    It "habilita os caminhos das tarefas agendadas de atualização sem redefinir a política de segurança local não relacionada" {
        Invoke-WPFUpdatesdefault

        foreach ($expectedTaskPath in $script:updateTaskPaths) {
            $expected = $expectedTaskPath
            Should -Invoke -CommandName Get-ScheduledTask -Times 1 -Exactly -ParameterFilter {
                $TaskPath -eq $expected
            }
        }
        Should -Invoke -CommandName Enable-ScheduledTask -Times $script:updateTaskPaths.Count -Exactly
        Should -Not -Invoke secedit
    }
}

Describe "Invoke-WPFUpdatessecurity" {
    BeforeEach {
        Mock Write-Host { }
        Mock Write-WinUtilLog { }
        Mock Test-Path { $false }
        Mock New-Item { }
        Mock Set-ItemProperty { }
        Mock Remove-ItemProperty { }
        Mock Get-ItemProperty { }
        Mock Set-Service { }
        Mock Start-Service { }
        Mock Get-ScheduledTask {
            [pscustomobject]@{
                TaskPath = $TaskPath
            }
        }
        Mock Enable-ScheduledTask { }
    }

    It "restaura a disponibilidade de atualizações antes de aplicar as configurações recomendadas" {
        Invoke-WPFUpdatessecurity

        Should -Invoke -CommandName Remove-ItemProperty -Times 1 -Exactly -ParameterFilter {
            $Path -eq "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -and
                $Name -eq "NoAutoUpdate"
        }
        Should -Invoke -CommandName Remove-ItemProperty -Times 1 -Exactly -ParameterFilter {
            $Path -eq "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config" -and
                $Name -eq "DODownloadMode"
        }
        Should -Invoke -CommandName Set-Service -Times 1 -Exactly -ParameterFilter {
            $Name -eq "BITS" -and $StartupType -eq "Manual"
        }
        Should -Invoke -CommandName Set-Service -Times 1 -Exactly -ParameterFilter {
            $Name -eq "wuauserv" -and $StartupType -eq "Manual"
        }
        Should -Invoke -CommandName Set-Service -Times 1 -Exactly -ParameterFilter {
            $Name -eq "UsoSvc" -and $StartupType -eq "Automatic"
        }
        Should -Invoke -CommandName Start-Service -Times 1 -Exactly -ParameterFilter {
            $Name -eq "UsoSvc"
        }
        foreach ($expectedTaskPath in $script:updateTaskPaths) {
            $expected = $expectedTaskPath
            Should -Invoke -CommandName Get-ScheduledTask -Times 1 -Exactly -ParameterFilter {
                $TaskPath -eq $expected
            }
        }
        Should -Invoke -CommandName Enable-ScheduledTask -Times $script:updateTaskPaths.Count -Exactly
    }

    It "desativa metadados de driver e a busca de drivers do Windows Update" {
        Invoke-WPFUpdatessecurity

        Should -Invoke -CommandName New-Item -Times 1 -Exactly -ParameterFilter {
            $Path -eq "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Device Metadata" -and $Force -eq $true
        }
        Should -Invoke -CommandName Set-ItemProperty -Times 1 -Exactly -ParameterFilter {
            $Path -eq "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Device Metadata" -and
                $Name -eq "PreventDeviceMetadataFromNetwork" -and
                $Type -eq "DWord" -and
                $Value -eq 1
        }
        Should -Invoke -CommandName Set-ItemProperty -Times 1 -Exactly -ParameterFilter {
            $Path -eq "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching" -and
                $Name -eq "DontPromptForWindowsUpdate" -and
                $Type -eq "DWord" -and
                $Value -eq 1
        }
        Should -Invoke -CommandName Set-ItemProperty -Times 1 -Exactly -ParameterFilter {
            $Path -eq "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching" -and
                $Name -eq "DontSearchWindowsUpdate" -and
                $Type -eq "DWord" -and
                $Value -eq 1
        }
        Should -Invoke -CommandName Set-ItemProperty -Times 1 -Exactly -ParameterFilter {
            $Path -eq "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching" -and
                $Name -eq "DriverUpdateWizardWuSearchEnabled" -and
                $Type -eq "DWord" -and
                $Value -eq 0
        }
        Should -Invoke -CommandName Set-ItemProperty -Times 1 -Exactly -ParameterFilter {
            $Path -eq "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -and
                $Name -eq "ExcludeWUDriversInQualityUpdate" -and
                $Type -eq "DWord" -and
                $Value -eq 1
        }
    }

    It "define valores de política recomendados de adiamento de atualizações e notificação de instalação" {
        Invoke-WPFUpdatessecurity

        Should -Invoke -CommandName Set-ItemProperty -Times 1 -Exactly -ParameterFilter {
            $Path -eq "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -and
                $Name -eq "DeferFeatureUpdates" -and
                $Type -eq "DWord" -and
                $Value -eq 1
        }
        Should -Invoke -CommandName Set-ItemProperty -Times 1 -Exactly -ParameterFilter {
            $Path -eq "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -and
                $Name -eq "DeferFeatureUpdatesPeriodInDays" -and
                $Type -eq "DWord" -and
                $Value -eq 365
        }
        Should -Invoke -CommandName Set-ItemProperty -Times 1 -Exactly -ParameterFilter {
            $Path -eq "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -and
                $Name -eq "DeferQualityUpdates" -and
                $Type -eq "DWord" -and
                $Value -eq 1
        }
        Should -Invoke -CommandName Set-ItemProperty -Times 1 -Exactly -ParameterFilter {
            $Path -eq "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -and
                $Name -eq "DeferQualityUpdatesPeriodInDays" -and
                $Type -eq "DWord" -and
                $Value -eq 4
        }
        Should -Invoke -CommandName Remove-ItemProperty -Times 1 -Exactly -ParameterFilter {
            $Path -eq "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -and
                $Name -eq "NoAutoRebootWithLoggedOnUsers"
        }
        Should -Invoke -CommandName Set-ItemProperty -Times 1 -Exactly -ParameterFilter {
            $Path -eq "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -and
                $Name -eq "AUOptions" -and
                $Type -eq "DWord" -and
                $Value -eq 3
        }
        Should -Invoke -CommandName Set-ItemProperty -Times 1 -Exactly -ParameterFilter {
            $Path -eq "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -and
                $Name -eq "AUPowerManagement" -and
                $Type -eq "DWord" -and
                $Value -eq 0
        }
    }

    It "mantém chaves de política existentes em vez de recriá-las" {
        Mock Test-Path { $true }

        Invoke-WPFUpdatessecurity

        Should -Not -Invoke New-Item
        Should -Invoke -CommandName Set-ItemProperty -Times 1 -Exactly -ParameterFilter {
            $Path -eq "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -and
                $Name -eq "DeferFeatureUpdates" -and
                $Value -eq 1
        }
        Should -Invoke -CommandName Set-ItemProperty -Times 1 -Exactly -ParameterFilter {
            $Path -eq "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -and
                $Name -eq "AUOptions" -and
                $Value -eq 3
        }
    }

    It "limpa um bloqueio de atualização deixado pelo Criador do Win11" {
        Mock Get-ItemProperty {
            [pscustomobject]@{ WUServer = "http://localhost:8080" }
        } -ParameterFilter { $Name -eq "WUServer" }

        Invoke-WPFUpdatessecurity

        foreach ($expectedValue in @(
            @("HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate", "DisableWindowsUpdateAccess"),
            @("HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate", "WUServer"),
            @("HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate", "WUStatusServer"),
            @("HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU", "UseWUServer")
        )) {
            $expected = $expectedValue
            Should -Invoke -CommandName Remove-ItemProperty -Times 1 -Exactly -ParameterFilter {
                $Path -eq $expected[0] -and $Name -eq $expected[1]
            }
        }
    }

    It "mantém um servidor WSUS real" {
        Mock Get-ItemProperty {
            [pscustomobject]@{ WUServer = "http://wsus.example.local:8530" }
        } -ParameterFilter { $Name -eq "WUServer" }

        Invoke-WPFUpdatessecurity

        Should -Not -Invoke Remove-ItemProperty -ParameterFilter {
            $Name -in @("WUServer", "WUStatusServer", "UseWUServer")
        }
    }

    It "remove valores de adiamento legados do WinUtil do caminho de configurações UX não suportado" {
        Invoke-WPFUpdatessecurity

        foreach ($expectedValueName in @("BranchReadinessLevel", "DeferFeatureUpdatesPeriodInDays", "DeferQualityUpdatesPeriodInDays")) {
            $expected = $expectedValueName
            Should -Invoke Remove-ItemProperty -Times 1 -Exactly -ParameterFilter {
                $Path -eq "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" -and
                    $Name -eq $expected
            }
        }
    }
}
