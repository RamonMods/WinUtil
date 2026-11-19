function Set-WinUtilAppCategoryFilter {
    <#
        .SYNOPSIS
            Aplica o filtro de categoria da aba Instalar e sincroniza o estado dos chips com ele

        .DESCRIPTION
            A seleção fica em $sync.SelectedAppCategories. Uma seleção vazia significa que todas
            as categorias são exibidas, que é o que o chip Todas representa. O filtro de categoria e a
            caixa de busca são independentes: isto mexe apenas nas categorias, e o texto de busca
            atual é reaplicado por cima.

        .PARAMETER Category
            A categoria sobre a qual agir. Um valor vazio limpa o filtro e volta para Todas.

        .PARAMETER Additive
            Alterna esta categoria dentro ou fora da seleção atual em vez de substituí-la.
            Ligado ao clique com ctrl.
    #>
    param(
        [Parameter(Mandatory = $false)]
        [string]$Category = "",

        [Parameter(Mandatory = $false)]
        [switch]$Additive
    )

    if ($null -eq $sync.SelectedAppCategories) {
        $sync.SelectedAppCategories = [System.Collections.Generic.List[string]]::new()
    }
    $selected = $sync.SelectedAppCategories

    if ([string]::IsNullOrWhiteSpace($Category)) {
        $selected.Clear()
    } elseif ($Additive) {
        if ($selected.Contains($Category)) {
            [void]$selected.Remove($Category)
        } else {
            $selected.Add($Category)
        }
    } elseif ($selected.Count -eq 1 -and $selected.Contains($Category)) {
        # Clicar novamente na única categoria ativa limpa o filtro
        $selected.Clear()
    } else {
        $selected.Clear()
        $selected.Add($Category)
    }

    Update-WinUtilAppCategoryChip
    Find-AppsByNameOrDescription -SearchString $sync.SearchBar.Text -Categories $selected.ToArray()
}
