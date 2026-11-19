function Invoke-WinUtilAppCategoryChip {
    <#
        .SYNOPSIS
            Trata um clique em um chip de categoria da aba Instalar

        .DESCRIPTION
            O chip carrega sua categoria em Tag, então todos os chips compartilham este manipulador. Manter o Ctrl
            pressionado adiciona a categoria à seleção atual em vez de substituí-la.

        .PARAMETER Chip
            O chip que foi clicado
    #>
    param(
        [Parameter(Mandatory)]
        $Chip
    )

    $ctrlDown = [bool]([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control)
    Set-WinUtilAppCategoryFilter -Category $Chip.Tag -Additive:$ctrlDown
}
