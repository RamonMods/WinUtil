    function Initialize-InstallAppArea {
        <#
            .SYNOPSIS
                Cria um [Windows.Controls.ScrollViewer] contendo um [Windows.Controls.ItemsControl] que é configurado para usar Virtualização e carregar apenas os elementos visíveis, por motivos de desempenho.
                Ele é usado como objeto pai de todas as entradas de categoria e de app na aba Instalar
                Usado como parte da geração da interface da aba Instalar

            .PARAMETER TargetElement
                O elemento ao qual a AppArea deve ser adicionada

        #>
        param($TargetElement)
        $targetGrid = $sync.Form.FindName($TargetElement)
        $null = $targetGrid.Children.Clear()

        # Cria a Borda externa para a área onde os apps serão colocados
        $Border = New-Object Windows.Controls.Border
        $Border.VerticalAlignment = "Stretch"
        $Border.SetResourceReference([Windows.Controls.Control]::StyleProperty, "BorderStyle")
        # Adiciona um ScrollViewer, porque o ItemsControl não suporta rolagem por conta própria
        $scrollViewer = New-Object Windows.Controls.ScrollViewer
        $scrollViewer.VerticalScrollBarVisibility = 'Auto'
        $scrollViewer.HorizontalAlignment = 'Stretch'
        $scrollViewer.VerticalAlignment = 'Stretch'
        $scrollViewer.CanContentScroll = $true
        $Border.Child = $scrollViewer

        # Os cartões têm pelo menos AppEntryWidth de largura e crescem para dividir cada linha, assim nenhuma linha termina em espaço vazio
        $sync.Form.Resources["AppEntryCardWidth"] = [double]$sync.Form.Resources["AppEntryWidth"]
        # A largura da própria lista muda com a janela, e também quando sua barra de rolagem aparece ou some
        $scrollViewer.Add_ScrollChanged({
            param($sender, $e)
            if ($e.ViewportWidthChange -ne 0) { Update-WinUtilAppEntryWidth }
        })

        ## Cria o ItemsControl, que será o pai de todas as entradas de app
        $itemsControl = New-Object Windows.Controls.ItemsControl
        $itemsControl.HorizontalAlignment = 'Stretch'
        $itemsControl.VerticalAlignment = 'Stretch'
        $scrollViewer.Content = $itemsControl

        # Usa WrapPanel para criar colunas dinâmicas com base na largura do cartão e na largura da janela
        $itemsPanelTemplate = New-Object Windows.Controls.ItemsPanelTemplate
        $factory = New-Object Windows.FrameworkElementFactory ([Windows.Controls.WrapPanel])
        $factory.SetValue([Windows.Controls.WrapPanel]::OrientationProperty, [Windows.Controls.Orientation]::Horizontal)
        $factory.SetValue([Windows.Controls.WrapPanel]::HorizontalAlignmentProperty, [Windows.HorizontalAlignment]::Left)
        $itemsPanelTemplate.VisualTree = $factory
        $itemsControl.ItemsPanel = $itemsPanelTemplate

        # Adiciona a Borda que contém a Área de Apps ao Grid de destino
        $targetGrid.Children.Add($Border) | Out-Null

        return $itemsControl
    }
