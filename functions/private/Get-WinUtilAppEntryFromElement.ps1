function Get-WinUtilAppEntryFromElement {
    <#
        .SYNOPSIS
            Encontra a entrada (cartão) de app à qual um elemento da aba Instalar pertence

        .PARAMETER Element
            O elemento de onde veio um evento, como um ícone, um nome ou o próprio cartão

        .OUTPUTS
            A borda mais próxima marcada com uma chave de app, ou nada quando o elemento não está em um cartão
    #>
    param($Element)

    while ($null -ne $Element) {
        if ($Element -is [Windows.Controls.Border] -and $Element.Tag -is [string] -and $Element.Tag.StartsWith("WPFInstall")) {
            return $Element
        }
        $Element = if ($Element -is [Windows.Media.Visual]) {
            [Windows.Media.VisualTreeHelper]::GetParent($Element)
        } else {
            [Windows.LogicalTreeHelper]::GetParent($Element)
        }
    }
}