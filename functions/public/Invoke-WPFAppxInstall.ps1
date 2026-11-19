function Invoke-WPFAppxInstall {
    if ($null -eq $sync.selectedAppx -or $sync.selectedAppx.Count -eq 0) {
        Show-WinUtilMessage -Message "Nenhum pacote AppX selecionado" -Title "Erro" -Button "OK" -Icon "Error"
        return
    }

    Start-WinUtilJob -Name "AppX install" -Description "Instalando pacotes AppX" -QueueIfBusy -Parameters @{
        Selected = @($sync.selectedAppx)
        Apps = $sync.configs.appxHashtable
    } -ScriptBlock {
        param($Selected, $Apps)

        $totalPackages = @($Selected).Count
        $results = @()
        Write-WinUtilLog -Component "AppX" -Message "Iniciando a instalação do AppX para $totalPackages pacote(s) selecionado(s)."

        for ($index = 0; $index -lt $totalPackages; $index++) {
            $app = $Apps[$Selected[$index]]
            $position = $index + 1

            Step-WinUtilJob -Status "Instalando $($app.Content) ($position/$totalPackages)" -Percent ([int](($index / $totalPackages) * 100))
            Write-Host "Instalando $($app.Content)"
            $appResults = @(Install-WinUtilAPPX -Name $app.PackageId -StoreId $app.StoreId)
            $results += $appResults
            $status = if (@($appResults | Where-Object Outcome -EQ "Failed").Count -gt 0) {
                "Failed"
            } elseif (@($appResults | Where-Object Outcome -EQ "Skipped").Count -gt 0) {
                "Skipped"
            } else {
                "Installed"
            }
            Step-WinUtilJob -Status "$status $($app.Content) ($position/$totalPackages)" -Percent ([int](($position / $totalPackages) * 100))
        }

        Complete-WinUtilPackageRun -Action "Install" -Results $results
    }
}
