function Invoke-WPFToggleSelections {
    <#

    .SYNOPSIS
        Aplica todos os interruptores selecionados

    .DESCRIPTION
        Na janela, um interruptor se aplica no momento em que é alternado, então nunca foi
        necessário aplicar uma lista deles. Uma configuração importada carrega interruptores da
        mesma forma que carrega ajustes e, sem isso, eles seriam lidos e depois ignorados.

    #>

    $toggles = @($sync.selectedToggles)

    if ($toggles.Count -eq 0) {
        Show-WinUtilMessage -Message "Nenhum interruptor está selecionado." -Title "WinUtil" -Button "OK" -Icon "Warning" | Out-Null
        return
    }

    Write-WinUtilLog -Component "Toggles" -Message "Interruptores solicitados: $($toggles.Count) selecionados."

    Start-WinUtilJob -Name "Toggles" -Description "Aplicando interruptores" -Parameters @{
        Toggles = $toggles
    } -ScriptBlock {
        param($Toggles)

        $total = [Math]::Max(@($Toggles).Count, 1)
        $completed = 0

        foreach ($toggle in $Toggles) {
            Step-WinUtilJob -Status "Aplicando $toggle ($($completed + 1)/$total)" -Percent ([int](($completed / $total) * 100))
            Measure-WinUtilStep -Scope "Toggles" -Name $toggle -ScriptBlock {
                Invoke-WinUtilTweaks $toggle
            }
            $completed++
            Step-WinUtilJob -Percent ([int](($completed / $total) * 100))
        }
    }
}
