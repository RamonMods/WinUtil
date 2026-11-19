function Initialize-InstallAppEntries {
    <#
        .SYNOPSIS
            Cria as entradas de app para um conjunto de apps e as coloca na aba Instalar
            Usado como parte da geração da interface da aba Instalar

        .DESCRIPTION
            As entradas são escritas como um único documento XAML e analisadas em uma única chamada. Construir
            um cartão controle a controle custa várias chamadas do PowerShell por elemento, o que é a maior
            parte do tempo que a aba Instalar leva para aparecer; o analisador faz o mesmo trabalho nativamente.

            Estilos e cores são referências DynamicResource, então eles resolvem contra a janela
            depois que as entradas são anexadas e acompanham mudanças de tema. O tratamento de mouse e de marcação não é
            anexado por entrada: o painel da categoria mantém um conjunto de tratadores para todos os seus cartões (veja
            Get-WinUtilAppEntryHandlers).

        .PARAMETER TargetElement
            O WrapPanel no qual as entradas devem ser colocadas

        .PARAMETER AppKeys
            As chaves dos apps dentro da $sync.configs.applicationsHashtable

        .OUTPUTS
            A caixa de seleção de cada entrada, na ordem de AppKeys
    #>
    param(
        [Windows.Controls.WrapPanel]$TargetElement,
        [string[]]$AppKeys
    )

    $document = [System.Text.StringBuilder]::new()
    [void]$document.Append('<WrapPanel xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">')

    $icons = @{}
    foreach ($appKey in $AppKeys) {
        $app = $sync.configs.applicationsHashtable[$appKey]
        $icon = Get-WinUtilAppIcon -Key ($appKey -replace '^WPFInstall', '')
        $icons[$appKey] = $icon

        $name = [Security.SecurityElement]::Escape($app.content)
        $key = [Security.SecurityElement]::Escape($appKey)
        # Sanitiza o nome para o WPF
        $id = $appKey.Replace('-', '_')
        $tooltip = [Security.SecurityElement]::Escape((Get-WinUtilEntryToolTip -Description $app.description -Key $appKey)).Replace("`r", '').Replace("`n", '&#10;')
        $letter = [Security.SecurityElement]::Escape($app.content.TrimStart(".").Substring(0, 1).ToUpper())

        $letterVisibility = if ($icon) { ' Visibility="Collapsed"' } else { '' }

        [void]$document.Append(@"
<Border Style="{DynamicResource AppEntryBorderStyle}" Tag="$key" ToolTip="$tooltip" AutomationProperties.Name="$name"><Grid><CheckBox x:Name="$id" Tag="$key" Style="{DynamicResource AppEntryCheckboxStyle}" AutomationProperties.Name="$name"><StackPanel Orientation="Horizontal" VerticalAlignment="Center"><Border Style="{DynamicResource AppEntryIconPlateStyle}"><Grid><TextBlock Style="{DynamicResource AppEntryIconLetterStyle}" Text="$letter"$letterVisibility/><Image x:Name="Icon_$id" Style="{DynamicResource AppEntryIconStyle}"/></Grid></Border><TextBlock Style="{DynamicResource AppEntryNameStyle}" Text="$name"/></StackPanel></CheckBox>
"@)

        # Mantém o selo do canto dentro dos limites de layout do cartão para evitar corte.
        # O Viewbox escala a arte, então deixe suas próprias dimensões sem arredondamento em DPI fracionário.
        # A mesma arte de New-WinUtilFossBadge, escrita aqui para que seja analisada junto com o resto.
        if ($app.foss -eq $true) {
            [void]$document.Append('<Viewbox Width="22" Height="22" HorizontalAlignment="Right" VerticalAlignment="Top" Margin="0,1,1,0" UseLayoutRounding="False" ToolTip="Software Livre e de Código Aberto"><Grid Width="22" Height="22"><Path Fill="#138F53" Data="M 0,0 L 17,0 A 5,5 0 0 1 22,5 L 22,22 Z"/><Path Stroke="#F7F7F7" StrokeThickness="2.4" StrokeStartLineCap="Round" StrokeEndLineCap="Round" Data="M 13.61,9.225 A 3.4,3.4 0 1 1 17.51,9.225"/></Grid></Viewbox>')
        }
        [void]$document.Append('</Grid></Border>')
    }
    [void]$document.Append('</WrapPanel>')

    $parsed = [Windows.Markup.XamlReader]::Parse($document.ToString())
    $handlers = Get-WinUtilAppEntryHandlers

    $checkBoxes = foreach ($appKey in $AppKeys) {
        $id = $appKey.Replace('-', '_')
        $checkBox = $parsed.FindName($id)
        $icon = $icons[$appKey]

        if ($icon) {
            $parsed.FindName("Icon_$id").Source = $icon
        } elseif ($sync.configs.applicationsHashtable[$appKey].link) {
            # Sem ícone embutido: consulta o serviço de favicon, como antes
            $logo = $parsed.FindName("Icon_$id")
            $checkBox.Content.Children[0].Child.Children[0].Visibility = "Collapsed"
            $logo.Add_ImageFailed($handlers.ImageFailed)
            try {
                # Evita reutilizar uma imagem WIC em cache de uma janela anterior neste processo.
                # Mantém o download no WPF para que os ícones não ocupem o pool de jobs compartilhado.
                $bitmap = [Windows.Media.Imaging.BitmapImage]::new()
                $bitmap.BeginInit()
                $bitmap.CreateOptions = [Windows.Media.Imaging.BitmapCreateOptions]::IgnoreImageCache
                $bitmap.UriCachePolicy = [Net.Cache.RequestCachePolicy]::new([Net.Cache.RequestCacheLevel]::BypassCache)
                $bitmap.UriSource = [uri]"https://www.google.com/s2/favicons?sz=64&domain_url=$([uri]::EscapeDataString($sync.configs.applicationsHashtable[$appKey].link))"
                $bitmap.EndInit()
                $logo.Source = $bitmap
            } catch {
                $logo.Visibility = "Collapsed"
                $checkBox.Content.Children[0].Child.Children[0].Visibility = "Visible"
            }
        }
        $checkBox
    }

    # Move os cartões de uma só vez. Retirá-los primeiro evita que cada um fique com dois pais.
    $entries = @($parsed.Children)
    $parsed.Children.Clear()
    foreach ($entry in $entries) {
        [void]$TargetElement.Children.Add($entry)
    }

    # Anexado por último, para que marcar um app que já foi escolhido atualize seu cartão
    foreach ($checkBox in $checkBoxes) {
        if ($sync.selectedApps -contains $checkBox.Tag) {
            $checkBox.IsChecked = $true
        }
    }

    return $checkBoxes
}
