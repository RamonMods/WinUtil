function Invoke-WPFUIElements {
    <#
    .SYNOPSIS
        Adiciona elementos de interface a um Grid especificado na GUI do WinUtil com base em uma configuração JSON.
    .PARAMETER configVariable
        A variável/link que contém a configuração JSON.
    .PARAMETER targetGridName
        O nome do grid ao qual os elementos de interface devem ser adicionados.
    .PARAMETER columncount
        O número de colunas a ser usado no Grid. Se não for informado, é usado um valor padrão com base no painel.
    .EXAMPLE
        Invoke-WPFUIElements -configVariable $sync.configs.applications -targetGridName "install" -columncount 5
    .NOTES
        Eu futuro/colaborador: se possível, encapsule isso em um runspace para carregar todos os painéis ao mesmo tempo.
    #>

    param(
        [Parameter(Mandatory, Position = 0)]
        [PSCustomObject]$configVariable,

        [Parameter(Mandatory, Position = 1)]
        [string]$targetGridName,

        [Parameter(Mandatory, Position = 2)]
        [int]$columncount,

        # Permite que a interface responda entre lotes de entradas. Apenas para conteúdo que
        # ninguém está aguardando: quem acabou de clicar na aba prefere que tudo termine de uma vez.
        [switch]$Yield
    )

    $window = $sync.form

    $borderstyle = $window.FindResource("BorderStyle")
    $HoverTextBlockStyle = $window.FindResource("HoverTextBlockStyle")
    $ColorfulToggleSwitchStyle = $window.FindResource("ColorfulToggleSwitchStyle")
    $ToggleButtonStyle = $window.FindResource("ToggleButtonStyle")

    if (!$borderstyle -or !$HoverTextBlockStyle -or !$ColorfulToggleSwitchStyle) {
        throw "Falha ao recuperar os estilos usando 'FindResource' no elemento da janela principal."
    }

    $targetGrid = $window.FindName($targetGridName)

    if (!$targetGrid) {
        throw "Falha ao recuperar o Grid de destino pelo nome; nome informado: $targetGrid"
    }

    # Limpa as ColumnDefinitions e os filhos existentes
    $targetGrid.ColumnDefinitions.Clear() | Out-Null
    $targetGrid.Children.Clear() | Out-Null

    # Adiciona ColumnDefinitions ao Grid de destino
    for ($i = 0; $i -lt $columncount; $i++) {
        $colDef = New-Object Windows.Controls.ColumnDefinition
        $colDef.Width = New-Object System.Windows.GridLength([double]1, [System.Windows.GridUnitType]::Star)
        $targetGrid.ColumnDefinitions.Add($colDef) | Out-Null
    }

    $radioButtonGroups = @{}
    $organizedData = @{}

    # Itera pelos dados JSON e organiza por painel e categoria usando listas genéricas
    foreach ($prop in $configVariable.PSObject.Properties) {
        $entryInfo = $prop.Value

        $entryObject = [PSCustomObject]@{
            Name        = $prop.Name
            Category    = $entryInfo.Category
            Content     = $entryInfo.Content
            Panel       = if ($entryInfo.Panel) { $entryInfo.Panel } else { "0" }
            Link        = $entryInfo.link
            Description = $entryInfo.description
            Type        = $entryInfo.type
            ComboItems  = $entryInfo.ComboItems
            ComboDescriptions = $entryInfo.ComboDescriptions
            Registry    = $entryInfo.registry
            Checked     = $entryInfo.Checked
            ButtonWidth = $entryInfo.ButtonWidth
            GroupName   = $entryInfo.GroupName
        }

        $panel = $entryObject.Panel
        if (-not $organizedData.ContainsKey($panel)) {
            $organizedData[$panel] = @{}
        }

        $cat = $entryObject.Category
        if (-not $organizedData[$panel].ContainsKey($cat)) {
            $organizedData[$panel][$cat] = [System.Collections.Generic.List[object]]::new()
        }

        $organizedData[$panel][$cat].Add($entryObject)
    }

    # Inicializa a contagem de painéis
    $panelcount = 0

    # Itera por 'organizedData' por painel, categoria e aplicação
    $yieldClock = [System.Diagnostics.Stopwatch]::StartNew()
    foreach ($panelKey in ($organizedData.Keys | Sort-Object)) {
        # Cria uma Border para cada coluna
        $border = New-Object Windows.Controls.Border
        $border.VerticalAlignment = "Stretch"
        [System.Windows.Controls.Grid]::SetColumn($border, $panelcount)
        $border.style = $borderstyle
        $targetGrid.Children.Add($border) | Out-Null

        # Usa um DockPanel para conter o conteúdo
        $dockPanelContainer = New-Object Windows.Controls.DockPanel
        $border.Child = $dockPanelContainer

        # Cria um StackPanel para os controles de conteúdo das aplicações
        $stackPanelContainer = New-Object Windows.Controls.StackPanel
        $stackPanelContainer.HorizontalAlignment = 'Stretch'
        $stackPanelContainer.VerticalAlignment = 'Stretch'

        # Verifica se o grid de destino (ou algum ancestral) já está dentro de um ScrollViewer
        $hasOuterScrollViewer = $false
        $currentElement = $targetGrid
        while ($null -ne $currentElement) {
            if ($currentElement -is [System.Windows.Controls.ScrollViewer] -or $currentElement.GetType().Name -eq "ScrollViewer") {
                $hasOuterScrollViewer = $true
                break
            }
            $currentElement = $currentElement.Parent
        }

        if ($hasOuterScrollViewer) {
            # Adiciona o StackPanel diretamente ao DockPanel sem aninhar um ScrollViewer
            [Windows.Controls.DockPanel]::SetDock($stackPanelContainer, [Windows.Controls.Dock]::Bottom)
            $dockPanelContainer.Children.Add($stackPanelContainer) | Out-Null
        }
        else {
            # Cria um ScrollViewer para destinos que ainda não possuem um ScrollViewer externo
            $scrollViewer = New-Object Windows.Controls.ScrollViewer
            $scrollViewer.VerticalScrollBarVisibility = "Auto"
            $scrollViewer.HorizontalScrollBarVisibility = "Disabled"
            $scrollViewer.HorizontalAlignment = 'Stretch'
            $scrollViewer.VerticalAlignment = 'Stretch'
            $scrollViewer.Content = $stackPanelContainer

            [Windows.Controls.DockPanel]::SetDock($scrollViewer, [Windows.Controls.Dock]::Bottom)
            $dockPanelContainer.Children.Add($scrollViewer) | Out-Null
        }
        $panelcount++

        # Agora segue adicionando rótulos de categoria e entradas a $stackPanelContainer
        foreach ($category in ($organizedData[$panelKey].Keys | Sort-Object)) {

            $label = New-Object Windows.Controls.Label
            $categoryCleanName = $category -replace ".*__", ""
            $label.Content = $categoryCleanName
            $label.Focusable = $true
            $label.IsTabStop = $true
            [System.Windows.Automation.AutomationProperties]::SetName($label, $categoryCleanName)
            $label.SetResourceReference([Windows.Controls.Control]::FontSizeProperty, "HeaderFontSize")
            $label.SetResourceReference([Windows.Controls.Control]::FontFamilyProperty, "HeaderFontFamily")
            $label.UseLayoutRounding = $true
            $stackPanelContainer.Children.Add($label) | Out-Null
            $sync[$category] = $label

            # Ordena as entradas por tipo (caixas de seleção primeiro, depois botões, depois caixas de combinação e notas por último) e então alfabeticamente por Content
            $entries = $organizedData[$panelKey][$category] | Sort-Object @{Expression = {
                switch ($_.Type) {
                    'Button' { 1 }
                    'Combobox' { 2 }
                    'Note' { 3 }
                    default { 0 }
                }
            }}, Content
            foreach ($entryInfo in $entries) {

                # Construir todos os controles de um painel de uma só vez prende a interface por
                # centenas de milissegundos. Esvaziar a fila por prazo, em vez de a cada n entradas,
                # mantém a espera limitada independentemente do custo de cada entrada.
                if ($Yield -and $yieldClock.ElapsedMilliseconds -ge 25 -and (Test-WinUtilUIAlive)) {
                    $yieldClock.Restart()
                    $frame = New-Object Windows.Threading.DispatcherFrame
                    $null = $sync.Form.Dispatcher.BeginInvoke(
                        [Windows.Threading.DispatcherPriority]::Background,
                        [Windows.Threading.DispatcherOperationCallback]{
                            param($dispatcherFrame)
                            $dispatcherFrame.Continue = $false
                            return $null
                        },
                        $frame)
                    [Windows.Threading.Dispatcher]::PushFrame($frame)
                }

                # Cria os elementos de interface com base no tipo de entrada
                switch ($entryInfo.Type) {
                    "Toggle" {
                        $dockPanel = New-Object Windows.Controls.DockPanel
                        [System.Windows.Automation.AutomationProperties]::SetName($dockPanel, $entryInfo.Content)
                        $checkBox = New-Object Windows.Controls.CheckBox
                        $checkBox.Name = $entryInfo.Name
                        $checkBox.HorizontalAlignment = "Right"
                        $checkBox.UseLayoutRounding = $true
                        [System.Windows.Automation.AutomationProperties]::SetName($checkBox, $entryInfo.Content)
                        $dockPanel.Children.Add($checkBox) | Out-Null
                        $checkBox.Style = $ColorfulToggleSwitchStyle

                        $label = New-Object Windows.Controls.Label
                        $label.Content = $entryInfo.Content
                        $label.ToolTip = $entryInfo.Description
                        $label.HorizontalAlignment = "Left"
                        $label.SetResourceReference([Windows.Controls.Control]::FontSizeProperty, "FontSize")
                        $label.SetResourceReference([Windows.Controls.Control]::ForegroundProperty, "MainForegroundColor")
                        $label.UseLayoutRounding = $true
                        $dockPanel.Children.Add($label) | Out-Null
                        $stackPanelContainer.Children.Add($dockPanel) | Out-Null

                        $sync[$entryInfo.Name] = $checkBox
                        $sync[$entryInfo.Name].IsChecked = (Get-WinUtilToggleStatus $entryInfo.Name)

                        $sync[$entryInfo.Name].Add_Checked({
                            [System.Object]$Sender = $args[0]
                            Invoke-WPFSelectedCheckboxesUpdate -type "Add" -checkboxName $Sender.name
                            # Ignora a aplicação de ajustes enquanto uma importação restaura os estados dos interruptores
                            if (-not $sync.ImportInProgress) {
                                Invoke-WinUtilTweaks $Sender.name
                            }
                        })

                        $sync[$entryInfo.Name].Add_Unchecked({
                            [System.Object]$Sender = $args[0]
                            Invoke-WPFSelectedCheckboxesUpdate -type "Remove" -checkboxName $Sender.name
                            # Ignora a reversão de ajustes enquanto uma importação restaura os estados dos interruptores
                            if (-not $sync.ImportInProgress) {
                                Invoke-WinUtiltweaks $Sender.name -undo $true
                            }
                        })
                    }

                    "ToggleButton" {
                        $toggleButton = New-Object Windows.Controls.Primitives.ToggleButton
                        $toggleButton.Name = $entryInfo.Name
                        $toggleButton.Content = $entryInfo.Content[1]
                        $toggleButton.ToolTip = Get-WinUtilEntryToolTip -Description $entryInfo.Description -Key $entryInfo.Name
                        $toggleButton.HorizontalAlignment = "Left"
                        $toggleButton.Style = $ToggleButtonStyle
                        [System.Windows.Automation.AutomationProperties]::SetName($toggleButton, $entryInfo.Content[0])

                        $toggleButton.Tag = @{
                            contentOn = if ($entryInfo.Content.Count -ge 1) { $entryInfo.Content[0] } else { "" }
                            contentOff = if ($entryInfo.Content.Count -ge 2) { $entryInfo.Content[1] } else { $contentOn }
                        }

                        $stackPanelContainer.Children.Add($toggleButton) | Out-Null

                        $sync[$entryInfo.Name] = $toggleButton

                        $sync[$entryInfo.Name].Add_Checked({
                            $this.Content = $this.Tag.contentOn
                        })

                        $sync[$entryInfo.Name].Add_Unchecked({
                            $this.Content = $this.Tag.contentOff
                        })

                        if ($null -eq $sync.Buttons) {
                            $sync.Buttons = [System.Collections.Generic.List[PSObject]]::new()
                        }

                        if ($sync.Buttons -notcontains $toggleButton.Name) {
                            $toggleButton.Add_Click({
                                [System.Object]$Sender = $args[0]
                                Invoke-WPFButton $Sender.name
                            })
                            $sync.Buttons.Add($toggleButton.Name) | Out-Null
                        }
                    }

                    "Combobox" {
                        $horizontalStackPanel = New-Object Windows.Controls.StackPanel
                        $horizontalStackPanel.Orientation = "Horizontal"
                        $horizontalStackPanel.Margin = "0,5,0,0"
                        [System.Windows.Automation.AutomationProperties]::SetName($horizontalStackPanel, $entryInfo.Content)

                        $label = New-Object Windows.Controls.Label
                        $label.Content = $entryInfo.Content
                        $label.HorizontalAlignment = "Left"
                        $label.ToolTip = $entryInfo.Description
                        $label.VerticalAlignment = "Center"
                        $label.SetResourceReference([Windows.Controls.Control]::FontSizeProperty, "ButtonFontSize")
                        $label.UseLayoutRounding = $true
                        $horizontalStackPanel.Children.Add($label) | Out-Null

                        $comboBox = New-Object Windows.Controls.ComboBox
                        $comboBox.Name = $entryInfo.Name
                        $comboBox.SetResourceReference([Windows.Controls.Control]::HeightProperty, "ButtonHeight")
                        $comboBox.SetResourceReference([Windows.Controls.Control]::WidthProperty, "ButtonWidth")
                        $comboBox.HorizontalAlignment = "Left"
                        $comboBox.VerticalAlignment = "Center"
                        $comboBox.SetResourceReference([Windows.Controls.Control]::MarginProperty, "ButtonMargin")
                        $comboBox.SetResourceReference([Windows.Controls.Control]::FontSizeProperty, "ButtonFontSize")
                        $comboBox.UseLayoutRounding = $true
                        $comboBox.Tag = [pscustomobject]@{
                            Registry = $entryInfo.Registry
                            State = $null
                        }
                        [System.Windows.Automation.AutomationProperties]::SetName($comboBox, $entryInfo.Content)

                        $comboItems = if ($entryInfo.ComboItems -is [string]) {
                            if ($entryInfo.ComboItems.Contains("|")) {
                                $entryInfo.ComboItems -split "\|"
                            } else {
                                $entryInfo.ComboItems -split " "
                            }
                        } else {
                            @($entryInfo.ComboItems)
                        }

                        foreach ($comboitem in $comboItems) {
                            $comboBoxItem = New-Object Windows.Controls.ComboBoxItem
                            $comboBoxItem.Content = $comboitem
                            if ($entryInfo.ComboDescriptions) {
                                $comboDescription = $entryInfo.ComboDescriptions.PSObject.Properties[$comboitem].Value
                                if ($comboDescription) {
                                    $comboBoxItem.ToolTip = $comboDescription
                                }
                            }
                            $comboBoxItem.SetResourceReference([Windows.Controls.Control]::FontSizeProperty, "ButtonFontSize")
                            $comboBoxItem.UseLayoutRounding = $true
                            $comboBox.Items.Add($comboBoxItem) | Out-Null
                        }

                        $horizontalStackPanel.Children.Add($comboBox) | Out-Null
                        $stackPanelContainer.Children.Add($horizontalStackPanel) | Out-Null

                        if ($entryInfo.Registry -and @($entryInfo.Registry)[0].Values) {
                            try {
                                $comboBox.Tag.State = Get-WinUtilRegistryComboState -Registry $entryInfo.Registry
                                $comboBox.SelectedIndex = @($comboBox.Items.Content).IndexOf([string]$comboBox.Tag.State)
                            } catch {
                                $unknownStateItem = New-Object Windows.Controls.ComboBoxItem
                                $unknownStateItem.Content = "Personalizado / Desconhecido - escolha um estado"
                                $unknownStateItem.IsEnabled = $false
                                $unknownStateItem.ToolTip = "$($_.Exception.Message) Selecione um dos estados compatíveis para substituir estes valores."
                                $comboBox.Items.Add($unknownStateItem) | Out-Null
                                $comboBox.SelectedItem = $unknownStateItem
                                $comboBox.ToolTip = $unknownStateItem.ToolTip
                            }
                        } else {
                            $comboBox.SelectedIndex = 0
                        }

                        # Define o texto inicial
                        if ($comboBox.Items.Count -gt 0) {
                            $comboBox.Text = $comboBox.SelectedItem.Content
                        }

                        $sync[$entryInfo.Name] = $comboBox

                        # Adiciona o manipulador do evento SelectionChanged para atualizar a propriedade de texto
                        $comboBox.Add_SelectionChanged({
                            $selectedItem = $this.SelectedItem
                            if ($selectedItem) {
                                $this.Text = $selectedItem.Content
                                $registry = $this.Tag.Registry
                                if ($registry -and $selectedItem.IsEnabled -and $selectedItem.Content -ne $this.Tag.State) {
                                    try {
                                        Set-WinUtilRegistryComboState -Registry $registry -State $selectedItem.Content
                                        $this.Tag.State = $selectedItem.Content
                                        $this.ToolTip = $null
                                        $unknownStateItem = @($this.Items) | Where-Object Content -EQ "Custom / Unknown - select a state" | Select-Object -First 1
                                        if ($unknownStateItem) {
                                            $this.Items.Remove($unknownStateItem)
                                        }
                                    } catch {
                                        $applyError = $_.Exception.Message
                                        if ([string]::IsNullOrWhiteSpace($applyError)) {
                                            $applyError = "Não foi possível aplicar o estado do registro '$($selectedItem.Content)'."
                                        }
                                        $previousState = if ($this.Tag.State) { $this.Tag.State } else { "Custom / Unknown - select a state" }
                                        $this.SelectedItem = @($this.Items) | Where-Object Content -EQ $previousState | Select-Object -First 1
                                        [System.Windows.MessageBox]::Show(
                                            $applyError,
                                            "WinUtil",
                                            [System.Windows.MessageBoxButton]::OK,
                                            [System.Windows.MessageBoxImage]::Warning
                                        ) | Out-Null
                                    }
                                }
                            }
                        })

                        if ($entryInfo.Registry -and @($entryInfo.Registry)[0].Values -and $entryInfo.Link) {
                            $textBlock = New-Object Windows.Controls.TextBlock
                            $textBlock.Name = $comboBox.Name + "Link"
                            $textBlock.Text = "(?)"
                            $textBlock.ToolTip = $entryInfo.Link
                            $textBlock.Style = $HoverTextBlockStyle
                            $textBlock.UseLayoutRounding = $true
                            $textBlock.VerticalAlignment = "Center"
                            $textBlock.SetResourceReference([Windows.Controls.Control]::FontSizeProperty, "FontSize")
                            $textBlock.Tag = $comboBox

                            $textBlock.Add_MouseUp({
                                [System.Object]$Sender = $args[0]
                                Start-Process $Sender.ToolTip -ErrorAction Stop
                            })

                            $horizontalStackPanel.Children.Add($textBlock) | Out-Null
                            $sync[$textBlock.Name] = $textBlock
                        }
                    }

                    "Button" {
                        $button = New-Object Windows.Controls.Button
                        $button.Name = $entryInfo.Name
                        $button.Content = $entryInfo.Content
                        $button.HorizontalAlignment = "Left"
                        $button.SetResourceReference([Windows.Controls.Control]::MarginProperty, "ButtonMargin")
                        $button.SetResourceReference([Windows.Controls.Control]::FontSizeProperty, "ButtonFontSize")
                        $button.ToolTip = $entryInfo.Description
                        if ($entryInfo.ButtonWidth) {
                            $baseWidth = [int]$entryInfo.ButtonWidth
                            $button.Width = [math]::Max($baseWidth, 350)
                        }
                        [System.Windows.Automation.AutomationProperties]::SetName($button, $entryInfo.Content)
                        $stackPanelContainer.Children.Add($button) | Out-Null

                        $sync[$entryInfo.Name] = $button

                        if ($null -eq $sync.Buttons) {
                            $sync.Buttons = [System.Collections.Generic.List[PSObject]]::new()
                        }

                        if ($sync.Buttons -notcontains $button.Name) {
                            $button.Add_Click({
                                [System.Object]$Sender = $args[0]
                                Invoke-WPFButton $Sender.name
                            })
                            $sync.Buttons.Add($button.Name) | Out-Null
                        }
                    }

                    "RadioButton" {
                        # Verifica se já existe um contêiner para este GroupName
                        if (-not $radioButtonGroups.ContainsKey($entryInfo.GroupName)) {
                            # Cria um StackPanel para este grupo
                            $groupStackPanel = New-Object Windows.Controls.StackPanel
                            $groupStackPanel.Orientation = "Vertical"
                            [System.Windows.Automation.AutomationProperties]::SetName($groupStackPanel, $entryInfo.GroupName)
                            $radioButtonGroups[$entryInfo.GroupName] = $groupStackPanel

                            # Adiciona o contêiner do grupo ao ItemsControl
                            $stackPanelContainer.Children.Add($groupStackPanel) | Out-Null
                        }
                        else {
                            # Recupera o contêiner do grupo existente
                            $groupStackPanel = $radioButtonGroups[$entryInfo.GroupName]
                        }

                        # Cria o RadioButton
                        $radioButton = New-Object Windows.Controls.RadioButton
                        $radioButton.Name = $entryInfo.Name
                        $radioButton.GroupName = $entryInfo.GroupName
                        $radioButton.Content = $entryInfo.Content
                        $radioButton.HorizontalAlignment = "Left"
                        $radioButton.SetResourceReference([Windows.Controls.Control]::MarginProperty, "CheckBoxMargin")
                        $radioButton.SetResourceReference([Windows.Controls.Control]::FontSizeProperty, "ButtonFontSize")
                        $radioButton.ToolTip = $entryInfo.Description
                        $radioButton.UseLayoutRounding = $true
                        [System.Windows.Automation.AutomationProperties]::SetName($radioButton, $entryInfo.Content)

                        if ($entryInfo.Checked -eq $true) {
                            $radioButton.IsChecked = $true
                        }

                        # Adiciona o RadioButton ao contêiner do grupo
                        $groupStackPanel.Children.Add($radioButton) | Out-Null
                        $sync[$entryInfo.Name] = $radioButton
                    }

                    "Note" {
                        $textBlock = New-Object Windows.Controls.TextBlock
                        $textBlock.TextWrapping = "Wrap"
                        $textBlock.Margin = "5,5,5,5"
                        $textBlock.UseLayoutRounding = $true

                        $bulletBadge = [Windows.Documents.InlineUIContainer]::new((New-WinUtilFossBadge -Size 18 -Round))
                        $bulletBadge.BaselineAlignment = [Windows.BaselineAlignment]::Center

                        $textRun = New-Object Windows.Documents.Run
                        $textRun.Text = " $($entryInfo.Content)"
                        $textRun.SetResourceReference([Windows.Controls.Control]::FontSizeProperty, "FontSize")
                        $textRun.Foreground = [Windows.Media.SolidColorBrush]::new([Windows.Media.Color]::FromRgb(19, 143, 83))

                        $textBlock.Inlines.Add($bulletBadge)
                        $textBlock.Inlines.Add($textRun)

                        $stackPanelContainer.Children.Add($textBlock) | Out-Null
                    }

                    default {
                        $horizontalStackPanel = New-Object Windows.Controls.StackPanel
                        $horizontalStackPanel.Orientation = "Horizontal"
                        [System.Windows.Automation.AutomationProperties]::SetName($horizontalStackPanel, $entryInfo.Content)

                        $checkBox = New-Object Windows.Controls.CheckBox
                        $checkBox.Name = $entryInfo.Name
                        $checkBox.Content = $entryInfo.Content
                        $checkBox.SetResourceReference([Windows.Controls.Control]::FontSizeProperty, "FontSize")
                        $checkBox.ToolTip = Get-WinUtilEntryToolTip -Description $entryInfo.Description -Key $entryInfo.Name
                        $checkBox.SetResourceReference([Windows.Controls.Control]::MarginProperty, "CheckBoxMargin")
                        $checkBox.UseLayoutRounding = $true
                        [System.Windows.Automation.AutomationProperties]::SetName($checkBox, $entryInfo.Content)
                        if ($entryInfo.Checked -eq $true) {
                            $checkBox.IsChecked = $entryInfo.Checked
                        }
                        $horizontalStackPanel.Children.Add($checkBox) | Out-Null

                        if ($entryInfo.Link) {
                            $textBlock = New-Object Windows.Controls.TextBlock
                            $textBlock.Name = $checkBox.Name + "Link"
                            $textBlock.Text = "(?)"
                            $textBlock.ToolTip = $entryInfo.Link
                            $textBlock.Style = $HoverTextBlockStyle
                            $textBlock.UseLayoutRounding = $true

                            $textBlock.VerticalAlignment = "Center"
                            $textBlock.SetResourceReference([Windows.Controls.Control]::FontSizeProperty, "FontSize")
                            $textBlock.Tag = $checkBox

                            $textBlock.Add_MouseUp({
                                [System.Object]$Sender = $args[0]
                                Start-Process $Sender.ToolTip -ErrorAction Stop
                            })

                            $updateLinkMargin = {
                                [System.Object]$Sender = $args[0]
                                $linkedCheckBox = $Sender.Tag
                                $MarginTopBase = if ($linkedCheckBox) { $linkedCheckBox.Margin.Top } else { 0 }
                                $Sender.Margin = New-Object Windows.Thickness(
                                    [math]::Round($Sender.FontSize * 0.5),
                                    ($MarginTopBase - [math]::Round($Sender.FontSize / 2)),
                                    0, 0
                                )
                            }
                            $textBlock.Add_Loaded($updateLinkMargin)
                            $fontSizeDescriptor = [System.ComponentModel.DependencyPropertyDescriptor]::FromProperty(
                                [Windows.Controls.Control]::FontSizeProperty,
                                [Windows.Controls.TextBlock]
                            )
                            $fontSizeDescriptor.AddValueChanged($textBlock, $updateLinkMargin)

                            $horizontalStackPanel.Children.Add($textBlock) | Out-Null

                            $sync[$textBlock.Name] = $textBlock
                        }

                        $stackPanelContainer.Children.Add($horizontalStackPanel) | Out-Null
                        $sync[$entryInfo.Name] = $checkBox

                        $sync[$entryInfo.Name].Add_Checked({
                            [System.Object]$Sender = $args[0]
                            Invoke-WPFSelectedCheckboxesUpdate -type "Add" -checkboxName $Sender.name
                        })

                        $sync[$entryInfo.Name].Add_Unchecked({
                            [System.Object]$Sender = $args[0]
                            Invoke-WPFSelectedCheckboxesUpdate -type "Remove" -checkboxName $Sender.name
                        })
                    }
                }
            }
        }
    }

    # Um evento de busca pode ocorrer dentro de um dos frames do dispatcher cedidos acima. Os
    # controles adicionados depois desse evento começam visíveis, então reaplique o filtro ativo
    # assim que esta aba estiver completa.
    $filterPanel = switch ($sync.currentTab) {
        "Tweaks" { "tweakspanel" }
        "AppX" { "appxpanel" }
    }
    if ($filterPanel -eq $targetGridName -and $null -ne $sync.SearchBar) {
        Find-TweaksByNameOrDescription -SearchString $sync.SearchBar.Text
    }
}
