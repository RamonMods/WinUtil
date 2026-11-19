function Invoke-WPFundoall {
    <#

    .SYNOPSIS
        Desfaz todos os ajustes selecionados

    #>

    $tweaks = $sync.selectedTweaks

    if ($tweaks.count -eq 0) {
        Show-WinUtilMessage -Message "Marque os ajustes que deseja desfazer." -Title "WinUtil" -Button "OK" -Icon "Warning"
        return
    }

    Start-WinUtilJob -Name "Undo tweaks" -Description "Desfazendo ajustes" -QueueIfBusy -Parameters @{
        Tweaks = @($tweaks)
    } -ScriptBlock {
        param($Tweaks)

        $total = @($Tweaks).Count
        Write-WinUtilLog -Component "Tweaks" -Message "Desfazer ajustes solicitado: $total ajuste(s) selecionado(s)."

        for ($i = 0; $i -lt $total; $i++) {
            $tweakLabel = Get-WinUtilTweakDisplayName -Key $Tweaks[$i]
            Step-WinUtilJob -Status "Undoing $tweakLabel ($($i + 1)/$total)" -Percent ([int](($i / $total) * 100))
            Measure-WinUtilStep -Scope "Undo tweaks" -Name $Tweaks[$i] -ScriptBlock {
                Invoke-WinUtiltweaks $Tweaks[$i] -undo $true
            }
            Step-WinUtilJob -Percent ([int]((($i + 1) / $total) * 100))
        }
    }
}
