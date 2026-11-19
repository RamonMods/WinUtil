function Invoke-WPFUpdatesdisable {
    <#

    .SYNOPSIS
        Desativa o Windows Update

    .NOTES
        Não é recomendado desativar o Windows Update. Isso é apenas para usuários avançados que sabem o que estão fazendo.

    #>
    param([switch]$Confirmed)

    if (-not $Confirmed -and -not (Confirm-WPFUpdatesdisable)) {
        return
    }

    Write-WinUtilLog -Component "Updates" -Message "Desativando as configurações do Windows Update."

    Write-Host "Configurando as configurações do registro..." -ForegroundColor Yellow
    Write-WinUtilLog -Component "Updates" -Message "Configurando os valores de política do registro do Windows Update para o modo desativado."
    # O New-Item -Force em uma chave de registro existente exclui a chave e suas subchaves primeiro,
    # então crie apenas as chaves ausentes e preserve as demais políticas já armazenadas nelas.
    if (-not (Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU")) {
        New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Force | Out-Null
    }

    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "NoAutoUpdate" -Type DWord -Value 1
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "AUOptions" -Type DWord -Value 1

    if (-not (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config")) {
        New-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config" -Force | Out-Null
    }
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config" -Name "DODownloadMode" -Type DWord -Value 0

    foreach ($serviceName in @("BITS", "wuauserv", "UsoSvc")) {
        Write-Host "Interrompendo e desativando o serviço $serviceName."
        Write-WinUtilLog -Component "Updates" -Message "Interrompendo e desativando o serviço $serviceName."
        Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
        Set-Service -Name $serviceName -StartupType Disabled
    }

    Remove-Item -Path "C:\Windows\SoftwareDistribution\*" -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "Pasta SoftwareDistribution limpa."
    Write-WinUtilLog -Component "Updates" -Message "Pasta SoftwareDistribution limpa."

    Write-Host "Desativando tarefas agendadas relacionadas a atualizações..." -ForegroundColor Yellow
    Write-WinUtilLog -Component "Updates" -Message "Desativando tarefas agendadas relacionadas a atualizações."

    $Tasks =
        '\Microsoft\Windows\InstallService\*',
        '\Microsoft\Windows\UpdateOrchestrator\*',
        '\Microsoft\Windows\UpdateAssistant\*',
        '\Microsoft\Windows\WaaSMedic\*',
        '\Microsoft\Windows\WindowsUpdate\*',
        '\Microsoft\WindowsUpdate\*'

    foreach ($Task in $Tasks) {
        Get-ScheduledTask -TaskPath $Task -ErrorAction SilentlyContinue | Disable-ScheduledTask -ErrorAction SilentlyContinue
    }


    Write-Host "Observação: você deve reiniciar o sistema para que todas as alterações tenham efeito." -ForegroundColor Yellow
    Write-WinUtilLog -Component "Updates" -Message "Fluxo de desativação do Windows Update concluído. É necessário reiniciar."
}

function Confirm-WPFUpdatesdisable {
    $confirmation = Show-WinUtilMessage `
        -Message "Desativar o Windows Update interrompe os serviços de atualização, desativa as tarefas agendadas e limpa os arquivos de atualização baixados. As atualizações de segurança não serão instaladas até que os padrões sejam restaurados. Continuar?" `
        -Title "Desativar o Windows Update?" `
        -Button "YesNo" `
        -Icon "Warning"

    if ($confirmation -ne "Yes") {
        Write-WinUtilLog -Component "Updates" -Message "Fluxo de desativação do Windows Update cancelado."
        return $false
    }
    return $true
}
