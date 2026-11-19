function Update-WinUtilAppEntryWidth {
    <#
        .SYNOPSIS
            Estica os cartões de aplicativos para que cada linha da aba Instalar preencha a largura disponível

        .DESCRIPTION
            AppEntryWidth é a largura mínima que um cartão pode ter. O número de colunas que cabem nessa
            largura é calculado para a largura real da lista, e os cartões dividem a linha igualmente.
            Cada cartão lê um recurso dinâmico, então um redimensionamento é uma única atribuição.
    #>

    # O controle de itens fica diretamente no visualizador de rolagem da lista
    $viewer = if ($sync.ItemsControl) { $sync.ItemsControl.Parent }
    if (-not $viewer -or $viewer.ViewportWidth -le 0) {
        return
    }

    $minimum = [double]$sync.Form.Resources["AppEntryWidth"]
    $spacing = ([Windows.Thickness]$sync.Form.Resources["AppEntryMargin"]).Left * 2
    $columns = [Math]::Max(1, [Math]::Floor($viewer.ViewportWidth / ($minimum + $spacing)))
    # Uma área de visualização mais estreita que um cartão mínimo mantém o cartão no mínimo e a lista rola
    $width = [double][Math]::Max($minimum, [Math]::Floor($viewer.ViewportWidth / $columns) - $spacing)

    if ($sync.Form.Resources["AppEntryCardWidth"] -ne $width) {
        $sync.Form.Resources["AppEntryCardWidth"] = $width
    }
}
