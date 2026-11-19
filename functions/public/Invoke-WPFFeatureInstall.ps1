function Invoke-WPFFeatureInstall {
    <#

    .SYNOPSIS
        Instala os Recursos do Windows selecionados

    #>

    if ($null -eq $sync.selectedFeatures -or $sync.selectedFeatures.Count -eq 0) {
        Show-WinUtilMessage -Message "Nenhum Recurso do Windows selecionado" -Title "WinUtil" -Button "OK" -Icon "Warning"
        return
    }

    Start-WinUtilJob -Name "Features" -Description "Instalando recursos do Windows" -QueueIfBusy -Parameters @{
        Features = @($sync.selectedFeatures)
    } -ScriptBlock {
        param($Features)

        $total = @($Features).Count
        $completed = 0

        foreach ($feature in $Features) {
            $completed++
            Step-WinUtilJob -Status "Instalando $feature ($completed/$total)" -Percent ([int]((($completed - 1) / $total) * 100))
            Measure-WinUtilStep -Scope "Features" -Name $feature -ScriptBlock {
                Invoke-WinUtilFeatureInstall $feature
            }
            Step-WinUtilJob -Status "Instalado $feature ($completed/$total)" -Percent ([int](($completed / $total) * 100))
        }

        Write-Host "Pode ser necessário reiniciar o computador."
    }
}
