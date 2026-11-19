function Invoke-WPFOOSU {
    Start-WinUtilJob -Name "OOSU" -Description "Baixando o O&O ShutUp10++" -Parameters @{
        DownloadPath = Join-Path $sync.winutildir "ooshutup10.exe"
    } -ScriptBlock {
        param($DownloadPath)

        Write-WinUtilLog -Component "OOSU" -Message "Baixando o O&O ShutUp10++."

        Save-WinUtilFile -Uri "https://dl5.oo-software.com/files/ooshutup10/OOSU10.exe" -DestinationPath $DownloadPath -ProgressCallback {
            param($percent, $totalBytes)

            # O servidor pode omitir o Content-Length; nesse caso, apenas a porcentagem é conhecida
            $progress = if ($totalBytes -gt 0) {
                "$percent% de $([math]::Round($totalBytes / 1MB)) MB"
            } else {
                "$percent%"
            }
            Step-WinUtilJob -Status "Baixando o O&O ShutUp10++ ($progress)" -Percent $percent
        }

        Step-WinUtilJob -Status "Iniciando o O&O ShutUp10++" -Percent 100
        Start-Process -FilePath $DownloadPath
        Write-WinUtilLog -Component "OOSU" -Message "O&O ShutUp10++ iniciado."
    }
}
