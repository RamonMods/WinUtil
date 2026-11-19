function Invoke-WinUtilUninstallPSProfile {
    <#
    .SYNOPSIS
        Restaura o perfil do PowerShell 7 que o perfil do RamonMods substituiu

    .DESCRIPTION
        O caminho do perfil deve vir do próprio pwsh. $PROFILE dentro deste job é o perfil
        do próprio Windows PowerShell do worker, que não é o arquivo que a instalação escreveu.
    #>

    $pwshPath = Get-WinUtilPowerShell7Path
    if (-not $pwshPath) {
        throw "O PowerShell 7 não está instalado, portanto não há perfil do RamonMods para remover."
    }

    $profilePath = (& $pwshPath -NoProfile -NonInteractive -Command '$PROFILE' | Select-Object -First 1)
    if ([string]::IsNullOrWhiteSpace($profilePath)) {
        throw "Não foi possível determinar o caminho do perfil do PowerShell 7."
    }
    $profilePath = $profilePath.Trim()
    $backupPath = "$profilePath.bak"

    if (Test-Path $backupPath) {
        Move-Item -Path $backupPath -Destination $profilePath -Force
        Write-WinUtilLog -Component "Feature" -Message "Perfil restaurado ao estado anterior: $profilePath"
        return
    }

    if (Test-Path $profilePath) {
        Remove-Item -Path $profilePath -Force
        Write-WinUtilLog -Component "Feature" -Message "Perfil do RamonMods do PowerShell removido: $profilePath"
        return
    }

    Write-WinUtilLog -Level "WARN" -Component "Feature" -Message "Nenhum perfil do PowerShell 7 encontrado em $profilePath; nada a remover."
}
