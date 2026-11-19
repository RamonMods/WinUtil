function Update-WinUtilAppCategoryChip {
    <#
        .SYNOPSIS
            Aplica a seleção de categoria atual aos chips de filtro da aba Instalar

        .DESCRIPTION
            Os chips são botões de alternância, então seu estado de marcado deve acompanhar a
            seleção, e não o que o último clique fez com eles. O chip Todos é marcado quando
            nenhuma categoria está selecionada.
    #>
    $selected = $sync.SelectedAppCategories
    if ($null -eq $selected) { return }

    foreach ($chip in $sync.AppCategoryChips) {
        $control = $sync[$chip.Name]
        if ($null -eq $control) { continue }
        $control.IsChecked = if ($chip.Category) { $selected.Contains($chip.Category) } else { $selected.Count -eq 0 }
    }
}
