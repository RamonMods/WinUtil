function Invoke-WPFUpdatesdefault {
    <#

    .SYNOPSIS
        Resets Windows Update settings to default

    #>
    Write-WinUtilLog -Component "Updates" -Message "Redefinindo as configurações do Windows Update para os padrões."

    Write-Host "Removendo as configurações do Windows Update gerenciadas pelo WinUtil..." -ForegroundColor Green
    Write-WinUtilLog -Component "Updates" -Message "Removendo os valores de registro do Windows Update gerenciados pelo WinUtil."

    $registryValues = @(
        @{
            Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
            Names = @("NoAutoUpdate", "AUOptions", "NoAutoRebootWithLoggedOnUsers", "AUPowerManagement")
        },
        @{
            Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
            Names = @("ExcludeWUDriversInQualityUpdate", "DeferFeatureUpdates", "DeferFeatureUpdatesPeriodInDays", "DeferQualityUpdates", "DeferQualityUpdatesPeriodInDays")
        },
        @{
            Path = "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings"
            Names = @("BranchReadinessLevel", "DeferFeatureUpdatesPeriodInDays", "DeferQualityUpdatesPeriodInDays")
        },
        @{
            Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Device Metadata"
            Names = @("PreventDeviceMetadataFromNetwork")
        },
        @{
            Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching"
            Names = @("DontPromptForWindowsUpdate", "DontSearchWindowsUpdate", "DriverUpdateWizardWuSearchEnabled")
        },
        @{
            Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config"
            Names = @("DODownloadMode")
        }
    )

    foreach ($registryEntry in $registryValues) {
        foreach ($valueName in $registryEntry.Names) {
            Remove-ItemProperty -Path $registryEntry.Path -Name $valueName -ErrorAction SilentlyContinue
        }
    }

    $explorerPolicyPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer"
    $settingsPageVisibility = (Get-ItemProperty -Path $explorerPolicyPath -Name "SettingsPageVisibility" -ErrorAction SilentlyContinue).SettingsPageVisibility
    if ($settingsPageVisibility -eq "hide:windowsupdate") {
        Write-Host "Removendo a restrição herdada da página do Windows Update do WinUtil..."
        Write-WinUtilLog -Component "Updates" -Message "Removendo a restrição herdada da página de configurações do Windows Update."
        Remove-ItemProperty -Path $explorerPolicyPath -Name "SettingsPageVisibility" -ErrorAction SilentlyContinue
    }

    Write-Host "Reativando os serviços do Windows Update..." -ForegroundColor Green
    Write-WinUtilLog -Component "Updates" -Message "Restaurando os tipos de inicialização dos serviços do Windows Update."

    # Other tweak tools can deny SYSTEM write access to these keys. Set-Service goes through the Service
    # Control Manager, which runs as SYSTEM, so clear those rules before restoring startup types.
    foreach ($serviceName in @("BITS", "wuauserv", "UsoSvc", "WaaSMedicSvc")) {
        $serviceKeyPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$serviceName"
        try {
            $serviceKeyAcl = Get-Acl -Path $serviceKeyPath -ErrorAction Stop
            # Match the SID because the SYSTEM account name is localized on some Windows languages.
            $systemDenyRules = @($serviceKeyAcl.GetAccessRules($true, $false, [System.Security.Principal.SecurityIdentifier]) | Where-Object {
                $_.AccessControlType -eq "Deny" -and $_.IdentityReference.Value -eq "S-1-5-18"
            })

            if ($systemDenyRules.Count -gt 0) {
                foreach ($denyRule in $systemDenyRules) {
                    $serviceKeyAcl.RemoveAccessRule($denyRule) | Out-Null
                }
                Set-Acl -Path $serviceKeyPath -AclObject $serviceKeyAcl -ErrorAction Stop
                Write-Host "Regras de negação do SYSTEM removidas de $serviceName."
                Write-WinUtilLog -Component "Updates" -Message "Regras de negação do SYSTEM removidas da chave de serviço $serviceName."
            }
        } catch {
            Write-Host "Não foi possível verificar as regras de negação do SYSTEM em $serviceName." -ForegroundColor Yellow
            Write-WinUtilLog -Level "WARN" -Component "Updates" -Message "Não foi possível verificar as regras de negação do SYSTEM na chave do serviço $serviceName`: $($_.Exception.Message)"
        }
    }

    Write-Host "BITS restaurado para Manual."
    Write-WinUtilLog -Component "Updates" -Message "Restaurando o serviço BITS para Manual."
    Set-Service -Name BITS -StartupType Manual

    Write-Host "wuauserv restaurado para Manual."
    Write-WinUtilLog -Component "Updates" -Message "Restaurando o serviço wuauserv para Manual."
    Set-Service -Name wuauserv -StartupType Manual

    Write-Host "UsoSvc restaurado para Automatic."
    Write-WinUtilLog -Component "Updates" -Message "Iniciando o serviço UsoSvc e restaurando o tipo de inicialização para Automatic."
    Set-Service -Name UsoSvc -StartupType Automatic
    Start-Service -Name UsoSvc

    # WaaSMedicSvc is launch protected, so Set-Service is denied even for administrators.
    $waaSMedicKeyPath = "HKLM:\SYSTEM\CurrentControlSet\Services\WaaSMedicSvc"
    if ((Get-ItemProperty -Path $waaSMedicKeyPath -Name "Start" -ErrorAction SilentlyContinue).Start -ne 3) {
        try {
            Set-ItemProperty -Path $waaSMedicKeyPath -Name "Start" -Type DWord -Value 3 -ErrorAction Stop
            Write-Host "WaaSMedicSvc restaurado para Manual."
            Write-WinUtilLog -Component "Updates" -Message "Restaurando o serviço WaaSMedicSvc para Manual."
        } catch {
            Write-Host "Não foi possível restaurar o WaaSMedicSvc para Manual." -ForegroundColor Yellow
            Write-WinUtilLog -Level "WARN" -Component "Updates" -Message "Não foi possível restaurar o WaaSMedicSvc para Manual`: $($_.Exception.Message)"
        }
    }

    Write-Host "Habilitando tarefas agendadas relacionadas a atualizações..." -ForegroundColor Green
    Write-WinUtilLog -Component "Updates" -Message "Habilitando tarefas agendadas relacionadas a atualizações."

    $Tasks =
        '\Microsoft\Windows\InstallService\*',
        '\Microsoft\Windows\UpdateOrchestrator\*',
        '\Microsoft\Windows\UpdateAssistant\*',
        '\Microsoft\Windows\WaaSMedic\*',
        '\Microsoft\Windows\WindowsUpdate\*',
        '\Microsoft\WindowsUpdate\*'

    foreach ($Task in $Tasks) {
        Get-ScheduledTask -TaskPath $Task -ErrorAction SilentlyContinue | Enable-ScheduledTask -ErrorAction SilentlyContinue
    }


    Write-Host "Observação: você deve reiniciar o sistema para que todas as alterações tenham efeito." -ForegroundColor Yellow
    Write-WinUtilLog -Component "Updates" -Message "Fluxo padrão do Windows Update concluído. É necessário reiniciar."
}
