function Invoke-WPFUpdatessecurity {
    <#

    .SYNOPSIS
        Define o Windows Update para as configurações recomendadas

    .DESCRIPTION
        1. Desativa a oferta de drivers por meio do Windows Update
        2. Adia atualizações de recursos por 365 dias
        3. Adia atualizações de qualidade por 4 dias
        4. Configura as atualizações automáticas para notificar quando as atualizações baixadas estiverem prontas para instalação

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

    # O Criador do Win11 bloqueia o Windows Update até a limpeza de primeiro logon rodar. Limpa o que sobrou desse bloqueio,
    # mas mantém um servidor WSUS real.
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

    # O New-Item -Force em uma chave de registro existente exclui a chave e suas subchaves primeiro,
    # então crie apenas as chaves ausentes e preserve as demais políticas já armazenadas nelas.
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

    # Remove a política anterior de reinicialização para instalação agendada ao alternar para baixar e notificar.
    Remove-ItemProperty -Path $automaticUpdatePolicyPath -Name "NoAutoRebootWithLoggedOnUsers" -ErrorAction SilentlyContinue

    # AUOptions 3 baixa as atualizações e notifica antes da instalação; não controla as reinicializações.
    Set-ItemProperty -Path $automaticUpdatePolicyPath -Name "AUOptions" -Type DWord -Value 3
    Set-ItemProperty -Path $automaticUpdatePolicyPath -Name "AUPowerManagement" -Type DWord -Value 0

    Write-WinUtilLog -Component "Updates" -Message "Fluxo de configurações recomendadas do Windows Update concluído."
}
