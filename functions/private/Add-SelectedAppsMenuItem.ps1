function Add-SelectedAppsMenuItem {
    <#
    .SYNOPSIS
        Função auxiliar que gera e adiciona os itens de menu ao popup de Apps Selecionados.

    .Parameter name
        O nome real de um app, como "Chrome" ou "Brave"
        Esse nome fica na propriedade "Content" dentro do applications.json
    .PARAMETER key
        A chave que identifica um objeto de app em applications.json
        Para o Chrome seria "WPFInstallchrome", pois "WPFInstall" é prefixado automaticamente em cada chave do applications.json
    #>

    param ([string]$name, [string]$key)

    $selectedAppGrid = New-Object Windows.Controls.Grid

    $selectedAppGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{Width = "*"}))
    $selectedAppGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{Width = "30"}))

    # Define o nome tanto em Content como em ToolTip, porque a borda do Popup pai tem largura fixa e o texto pode "transbordar".
    # Com a dica, você ainda consegue ler a entrada inteira ao passar o mouse
    $selectedAppLabel = New-Object Windows.Controls.Label
    $selectedAppLabel.Content = $name
    $selectedAppLabel.ToolTip = $name
    $selectedAppLabel.HorizontalAlignment = "Left"
    $selectedAppLabel.SetResourceReference([Windows.Controls.Control]::ForegroundProperty, "MainForegroundColor")
    [System.Windows.Controls.Grid]::SetColumn($selectedAppLabel, 0)
    $selectedAppGrid.Children.Add($selectedAppLabel)

    $selectedAppRemoveButton = New-Object Windows.Controls.Button
    $selectedAppRemoveButton.FontFamily = "Segoe MDL2 Assets"
    $selectedAppRemoveButton.Content = [string]([char]0xE711)
    $selectedAppRemoveButton.HorizontalAlignment = "Center"
    $selectedAppRemoveButton.Tag = $key
    $selectedAppRemoveButton.ToolTip = "Remover o app da seleção"
    $selectedAppRemoveButton.SetResourceReference([Windows.Controls.Control]::ForegroundProperty, "MainForegroundColor")
    $selectedAppRemoveButton.SetResourceReference([Windows.Controls.Control]::StyleProperty, "HoverButtonStyle")

    # Destaca o ícone de remover ao passar o mouse
    $selectedAppRemoveButton.Add_MouseEnter({ $this.Foreground = "Red" })
    $selectedAppRemoveButton.Add_MouseLeave({ $this.SetResourceReference([Windows.Controls.Control]::ForegroundProperty, "MainForegroundColor") })
    $selectedAppRemoveButton.Add_Click({
            $sync.($this.Tag).isChecked = $false # Ao clicar no botão remover, só precisamos desmarcar a caixa de seleção correspondente. Isso dispara todas as mudanças necessárias para atualizar a interface
    })
    [System.Windows.Controls.Grid]::SetColumn($selectedAppRemoveButton, 1)
    $selectedAppGrid.Children.Add($selectedAppRemoveButton)
    # Adiciona o novo elemento ao Popup
    $sync.selectedAppsstackPanel.Children.Add($selectedAppGrid)
}
