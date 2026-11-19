function Initialize-InstallCategoryAppList {
    <#
        .SYNOPSIS
            Limpa o Elemento de Destino e configura uma mensagem de "Carregando". Isso é feito porque carregar todos os apps pode levar um tempo em alguns cenários
            Percorre todas as Categorias e Apps e os adiciona à interface
            Usado como parte da geração da interface da aba Instalar
        .PARAMETER TargetElement
            O Elemento no qual as Categorias e os Apps devem ser colocados
        .PARAMETER Apps
            A Hashtable de Apps a serem adicionados à interface
            As Categorias também são extraídas da Hashtable de Apps

    #>
        param(
            $TargetElement,
            $Apps
        )

        # Pré-agrupa os apps por categoria antes de criar controles WPF. Listas, porque anexar a
        # um array o copia e existem várias centenas de apps.
        $appsByCategory = @{}
        # Consulta indexada, não por membro dinâmico: esta última passa pelo adaptador PSObject e
        # custa cerca de setenta vezes mais por app.
        foreach ($appKey in $Apps.Keys) {
            $category = $Apps[$appKey].Category
            if (-not $appsByCategory.ContainsKey($category)) {
                $appsByCategory[$category] = [System.Collections.Generic.List[string]]::new()
            }
            $appsByCategory[$category].Add($appKey)
        }
        $sync.InstallAppRenderQueue = [System.Collections.Queue]::new()

        foreach ($category in $($appsByCategory.Keys | Sort-Object)) {
            # Cria um contêiner para o rótulo da categoria + apps
            $categoryContainer = New-Object Windows.Controls.StackPanel
            $categoryContainer.Orientation = "Vertical"
            $categoryContainer.Margin = New-Object Windows.Thickness(0, 0, 0, 0)
            $categoryContainer.HorizontalAlignment = [Windows.HorizontalAlignment]::Stretch
            [System.Windows.Automation.AutomationProperties]::SetName($categoryContainer, $Category)

            # Vincula Width ao ActualWidth do ItemsControl para forçar o layout de linha inteira no WrapPanel
            $binding = New-Object Windows.Data.Binding
            $binding.Path = New-Object Windows.PropertyPath("ActualWidth")
            $binding.RelativeSource = New-Object Windows.Data.RelativeSource([Windows.Data.RelativeSourceMode]::FindAncestor, [Windows.Controls.ItemsControl], 1)
            [void][Windows.Data.BindingOperations]::SetBinding($categoryContainer, [Windows.FrameworkElement]::WidthProperty, $binding)

            # Adiciona o rótulo da categoria ao contêiner
            $toggleButton = New-Object Windows.Controls.Label
            $toggleButton.Content = "- $Category"
            $toggleButton.Tag = "CategoryToggleButton"
            $toggleButton.SetResourceReference([Windows.Controls.Control]::FontSizeProperty, "HeaderFontSize")
            $toggleButton.SetResourceReference([Windows.Controls.Control]::FontFamilyProperty, "HeaderFontFamily")
            $toggleButton.SetResourceReference([Windows.Controls.Control]::ForegroundProperty, "LabelboxForegroundColor")
            $toggleButton.Cursor = [System.Windows.Input.Cursors]::Hand
            $toggleButton.HorizontalAlignment = [Windows.HorizontalAlignment]::Stretch
            $sync.$Category = $toggleButton

            # Adiciona um tratador de clique para alternar a visibilidade da categoria
            $toggleButton.Add_MouseLeftButtonUp({
                param($categoryToggle)

                # Encontra o StackPanel pai (categoryContainer)
                $categoryContainer = $categoryToggle.Parent
                if ($categoryContainer -and $categoryContainer.Children.Count -ge 2) {
                    # O WrapPanel é o segundo filho
                    $wrapPanel = $categoryContainer.Children[1]

                    # Um clique explícito tem prioridade sobre o que a filtragem expandiu automaticamente
                    if ($sync.AppCategoryAutoExpanded) {
                        $sync.AppCategoryAutoExpanded.Remove(($categoryToggle.Content -replace '^[+-] ', ''))
                    }

                    # Alterna a visibilidade
                    if ($wrapPanel.Visibility -eq [Windows.Visibility]::Visible) {
                        $wrapPanel.Visibility = [Windows.Visibility]::Collapsed
                        # Muda - para +
                        $categoryToggle.Content = $categoryToggle.Content -replace "^- ", "+ "
                    } else {
                        $wrapPanel.Visibility = [Windows.Visibility]::Visible
                        # Muda + para -
                        $categoryToggle.Content = $categoryToggle.Content -replace "^\+ ", "- "
                    }
                }
            })

            $null = $categoryContainer.Children.Add($toggleButton)

            # Adiciona o painel de quebra de linha dos apps ao contêiner
            $wrapPanel = New-Object Windows.Controls.WrapPanel
            $wrapPanel.Orientation = "Horizontal"
            $wrapPanel.HorizontalAlignment = "Left"
            $wrapPanel.VerticalAlignment = "Top"
            $wrapPanel.Margin = New-Object Windows.Thickness(0, 0, 0, 0)
            $wrapPanel.Visibility = [Windows.Visibility]::Visible
            $wrapPanel.Tag = "CategoryWrapPanel_$category"

            # Um conjunto de tratadores para cada cartão da categoria; os eventos sobem até aqui
            $entryHandlers = Get-WinUtilAppEntryHandlers
            $wrapPanel.AddHandler([Windows.UIElement]::MouseLeftButtonUpEvent, $entryHandlers.BorderClick)
            $wrapPanel.AddHandler([Windows.UIElement]::MouseRightButtonUpEvent, $entryHandlers.RightClick)
            $wrapPanel.AddHandler([Windows.Controls.Primitives.ToggleButton]::CheckedEvent, $entryHandlers.Checked)
            $wrapPanel.AddHandler([Windows.Controls.Primitives.ToggleButton]::UncheckedEvent, $entryHandlers.Unchecked)

            $null = $categoryContainer.Children.Add($wrapPanel)

            # Adiciona o contêiner inteiro da categoria ao elemento de destino
            $null = $TargetElement.Items.Add($categoryContainer)

            $sync.InstallAppRenderQueue.Enqueue([pscustomobject]@{
                Category = $category
                TargetElement = $wrapPanel
                AppKeys = @($appsByCategory[$category] | Sort-Object)
            })
        }

        Start-WinUtilInstallAppRendering
    }
