function Invoke-WPFUpdatessecurity {
    <#

    .SYNOPSIS
        Sets Windows Update to recommended settings

    .DESCRIPTION
        1. Disables driver offering through Windows Update
        2. Defers feature updates for 365 days
        3. Defers quality updates for 4 days
        4. Configures automatic updates to notify when downloaded updates are ready to install

    #>

    Write-Host "Desativando a oferta de drivers pelo Windows Update..."
    Write-WinUtilLog -Component "Updates" -Message "Aplicando as configurações recomendadas do Windows Update."
    Write-WinUtilLog -Component "Updates" -Message "Desativando a oferta de drivers pelo Windows Update."

    $windowsUpdatePolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
    $automaticUpdatePolicyPath = Join-Path $windowsUpdatePolicyPath "AU"

    Write-Host "Restaurando a disponibilidade do Windows Update..."
    Write-WinUtilLog -Component "Updates" -Message "Restaurando os serviços e as tarefas agendadas do Windows Update antes de aplicar as configurações recomendadas."

    Remove-ItemProperty -Path $automaticUpdatePolicyPath -Name "NoAutoUpdate" -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config" -Name "DODownloadMode" -ErrorAction SilentlyContinue

    # O Criar Win11 bloqueia o Windows Update até a limpeza de primeiro logon rodar. Limpa o que sobrou desse bloqueio,
    # but keep a real WSUS server.
    Remove-ItemProperty -Path $windowsUpdatePolicyPath -Name "DisableWindowsUpdateAccess" -ErrorAction SilentlyContinue
    if ((Get-ItemProperty -Path $windowsUpdatePolicyPath -Name "WUServer" -ErrorAction SilentlyContinue).WUServer -eq "http://localhost:8080") {
        Remove-ItemProperty -Path $windowsUpdatePolicyPath -Name "WUServer" -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $windowsUpdatePolicyPath -Name "WUStatusServer" -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $automaticUpdatePolicyPath -Name "UseWUServer" -ErrorAction SilentlyContinue
    }

    Set-Service -Name BITS -StartupType Manual
    Set-Service -Name wuauserv -StartupType Manual
    Set-Service -Name UsoSvc -StartupType Automatic
    Start-Service -Name UsoSvc

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

    # New-Item -Force on an existing registry key deletes the key and its subkeys first, so only
    # create missing keys and keep any other policies already stored under them.
    if (-not (Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Device Metadata")) {
        New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Device Metadata" -Force | Out-Null
    }
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Device Metadata" -Name "PreventDeviceMetadataFromNetwork" -Type DWord -Value 1

    if (-not (Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching")) {
        New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching" -Force | Out-Null
    }

    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching" -Name "DontPromptForWindowsUpdate" -Type DWord -Value 1
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching" -Name "DontSearchWindowsUpdate" -Type DWord -Value 1
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching" -Name "DriverUpdateWizardWuSearchEnabled" -Type DWord -Value 0

    if (-not (Test-Path $windowsUpdatePolicyPath)) {
        New-Item -Path $windowsUpdatePolicyPath -Force | Out-Null
    }
    Set-ItemProperty -Path $windowsUpdatePolicyPath -Name "ExcludeWUDriversInQualityUpdate" -Type DWord -Value 1

    Write-Host "Adiando atualizações de recursos em 365 dias e atualizações de qualidade em 4 dias..."
    Write-WinUtilLog -Component "Updates" -Message "Adiando atualizações de recursos em 365 dias e atualizações de qualidade em 4 dias."

    Set-ItemProperty -Path $windowsUpdatePolicyPath -Name "DeferFeatureUpdates" -Type DWord -Value 1
    Set-ItemProperty -Path $windowsUpdatePolicyPath -Name "DeferFeatureUpdatesPeriodInDays" -Type DWord -Value 365
    Set-ItemProperty -Path $windowsUpdatePolicyPath -Name "DeferQualityUpdates" -Type DWord -Value 1
    Set-ItemProperty -Path $windowsUpdatePolicyPath -Name "DeferQualityUpdatesPeriodInDays" -Type DWord -Value 4

    $legacySettingsPath = "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings"
    foreach ($legacyValue in @("BranchReadinessLevel", "DeferFeatureUpdatesPeriodInDays", "DeferQualityUpdatesPeriodInDays")) {
        Remove-ItemProperty -Path $legacySettingsPath -Name $legacyValue -ErrorAction SilentlyContinue
    }

    Write-Host "Configurando atualizações automáticas para baixar e notificar antes da instalação..."
    Write-WinUtilLog -Component "Updates" -Message "Configurando atualizações automáticas para baixar e notificar antes da instalação."

    if (-not (Test-Path $automaticUpdatePolicyPath)) {
        New-Item -Path $automaticUpdatePolicyPath -Force | Out-Null
    }

    # Remove the previous scheduled-install reboot policy when switching to download-and-notify.
    Remove-ItemProperty -Path $automaticUpdatePolicyPath -Name "NoAutoRebootWithLoggedOnUsers" -ErrorAction SilentlyContinue

    # AUOptions 3 downloads updates and notifies before installation; it does not control restarts.
    Set-ItemProperty -Path $automaticUpdatePolicyPath -Name "AUOptions" -Type DWord -Value 3
    Set-ItemProperty -Path $automaticUpdatePolicyPath -Name "AUPowerManagement" -Type DWord -Value 0

    Write-WinUtilLog -Component "Updates" -Message "Fluxo de configurações recomendadas do Windows Update concluído."
}
