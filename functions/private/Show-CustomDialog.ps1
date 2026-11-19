function Show-CustomDialog {
    <#
    .SYNOPSIS
    Exibe uma caixa de diálogo personalizada com uma imagem, título, mensagem e um botão OK.

    .DESCRIPTION
    Esta função cria uma caixa de diálogo personalizada com a mensagem especificada e elementos adicionais como imagem, título e um botão OK. A caixa de diálogo é projetada com borda verde, cantos arredondados e fundo preto.

    .PARAMETER Title
    O título a ser usado na barra de título da janela do diálogo; não será visível ao usuário, já que o estilo da janela é None.

    .PARAMETER Message
    A mensagem a ser exibida na caixa de diálogo.

    .PARAMETER Width
    A largura da janela do diálogo personalizado.

    .PARAMETER Height
    A altura da janela do diálogo personalizado.

    .PARAMETER FontSize
    O tamanho da fonte da mensagem exibida dentro da janela do diálogo personalizado.

    .PARAMETER HeaderFontSize
    O tamanho da fonte do cabeçalho da janela do diálogo personalizado.

    .PARAMETER LogoSize
    O tamanho do logo usado dentro da janela do diálogo personalizado.

    .PARAMETER ForegroundColor
    A cor de primeiro plano do título e da mensagem da janela do diálogo.

    .PARAMETER BackgroundColor
    A cor de fundo da janela do diálogo.

    .PARAMETER BorderColor
    A cor da borda da janela do diálogo.

    .PARAMETER ButtonBackgroundColor
    A cor de fundo dos botões da janela do diálogo.

    .PARAMETER ButtonForegroundColor
    A cor de primeiro plano dos botões da janela do diálogo.

    .PARAMETER ShadowColor
    A cor usada ao criar o efeito de sombra projetada da janela do diálogo.

    .PARAMETER LogoColor
    A cor do texto WinUtil exibido ao lado do logo do WinUtil dentro da janela do diálogo.

    .PARAMETER LinkForegroundColor
    A cor de primeiro plano dos links dentro da janela do diálogo.

    .PARAMETER LinkHoverForegroundColor
    A cor de primeiro plano dos links quando o ponteiro do mouse passa sobre eles dentro da janela do diálogo.

    .PARAMETER EnableScroll
    Um sinalizador indicando se a rolagem deve ser habilitada quando o conteúdo exceder o tamanho da janela.

    .EXAMPLE
    Show-CustomDialog -Title "Meu diálogo personalizado" -Message "Este é um diálogo personalizado com uma mensagem e uma imagem acima." -Width 300 -Height 200

    Cria um novo diálogo personalizado com o título 'Meu diálogo personalizado' e a mensagem 'Este é um diálogo personalizado com uma mensagem e uma imagem acima.', com dimensões de 300 por 200 pixels.
    As demais opções de estilo são obtidas da variável global '$sync.Form.Resources'.

    .EXAMPLE
    $foregroundColor = New-Object System.Windows.Media.SolidColorBrush("#0088e5")
    $backgroundColor = New-Object System.Windows.Media.SolidColorBrush("#1e1e1e")
    $linkForegroundColor = New-Object System.Windows.Media.SolidColorBrush("#0088e5")
    $linkHoverForegroundColor = New-Object System.Windows.Media.SolidColorBrush("#005289")
    Show-CustomDialog -Title "Meu diálogo personalizado" -Message "Este é um diálogo personalizado com uma mensagem e uma imagem acima." -Width 300 -Height 200 -ForegroundColor $foregroundColor -BackgroundColor $backgroundColor -LinkForegroundColor $linkForegroundColor -LinkHoverForegroundColor $linkHoverForegroundColor

    Cria um novo diálogo personalizado com o título 'Meu diálogo personalizado' e a mensagem 'Este é um diálogo personalizado com uma mensagem e uma imagem acima.', com dimensões de 300 por 200 pixels, com cor de primeiro plano do link (e geral) '#0088e5', cor de fundo '#1e1e1e' e cor do link ao passar o mouse '005289', todos em hexadecimal (o símbolo '#' é exigido pelo construtor de SolidColorBrush).
    As demais opções de estilo são obtidas da variável global '$sync.Form.Resources'.

    #>
    param(
        [string]$Title,
        [string]$Message,
        [int]$Width = $sync.Form.Resources.CustomDialogWidth,
        [int]$Height = $sync.Form.Resources.CustomDialogHeight,

        [System.Windows.Media.FontFamily]$FontFamily = $sync.Form.Resources.FontFamily,
        [int]$FontSize = $sync.Form.Resources.CustomDialogFontSize,
        [int]$HeaderFontSize = $sync.Form.Resources.CustomDialogFontSizeHeader,
        [int]$LogoSize = $sync.Form.Resources.CustomDialogLogoSize,

        [System.Windows.Media.Color]$ShadowColor = "#AAAAAAAA",
        [System.Windows.Media.SolidColorBrush]$LogoColor = $sync.Form.Resources.LabelboxForegroundColor,
        [System.Windows.Media.SolidColorBrush]$BorderColor = $sync.Form.Resources.BorderColor,
        [System.Windows.Media.SolidColorBrush]$ForegroundColor = $sync.Form.Resources.MainForegroundColor,
        [System.Windows.Media.SolidColorBrush]$BackgroundColor = $sync.Form.Resources.MainBackgroundColor,
        [System.Windows.Media.SolidColorBrush]$ButtonForegroundColor = $sync.Form.Resources.ButtonInstallForegroundColor,
        [System.Windows.Media.SolidColorBrush]$ButtonBackgroundColor = $sync.Form.Resources.ButtonInstallBackgroundColor,
        [System.Windows.Media.SolidColorBrush]$LinkForegroundColor = $sync.Form.Resources.LinkForegroundColor,
        [System.Windows.Media.SolidColorBrush]$LinkHoverForegroundColor = $sync.Form.Resources.LinkHoverForegroundColor,

        [bool]$EnableScroll = $false
    )

    # Cria uma janela de diálogo personalizada
    $dialog = New-Object Windows.Window
    $dialog.Title = $Title
    $dialog.Height = $Height
    $dialog.Width = $Width
    $dialog.Margin = New-Object Windows.Thickness(10)  # Adiciona margem a toda a caixa de diálogo
    $dialog.WindowStyle = [Windows.WindowStyle]::None  # Remove a barra de título e os controles da janela
    $dialog.ResizeMode = [Windows.ResizeMode]::NoResize  # Desabilita o redimensionamento
    $dialog.WindowStartupLocation = [Windows.WindowStartupLocation]::CenterScreen  # Centraliza a janela
    $dialog.Foreground = $ForegroundColor
    $dialog.Background = $BackgroundColor
    $dialog.FontFamily = $FontFamily
    $dialog.FontSize = $FontSize

    # Cria uma borda para a aresta verde com cantos arredondados
    $border = New-Object Windows.Controls.Border
    $border.BorderBrush = $BorderColor
    $border.BorderThickness = New-Object Windows.Thickness(1)  # Ajusta a espessura da borda conforme necessário
    $border.CornerRadius = New-Object Windows.CornerRadius(10)  # Ajusta o raio para cantos arredondados

    # Cria um efeito de sombra projetada
    $dropShadow = New-Object Windows.Media.Effects.DropShadowEffect
    $dropShadow.Color = $shadowColor
    $dropShadow.Direction = 270
    $dropShadow.ShadowDepth = 5
    $dropShadow.BlurRadius = 10

    # Aplica o efeito de sombra projetada à borda
    $dialog.Effect = $dropShadow

    $dialog.Content = $border

    $grid = New-Object Windows.Controls.Grid
    $border.Child = $grid
    $grid.Background = [Windows.Media.Brushes]::Transparent
    $grid.HorizontalAlignment = [Windows.HorizontalAlignment]::Stretch
    $grid.VerticalAlignment = [Windows.VerticalAlignment]::Stretch
    $border.HorizontalAlignment = [Windows.HorizontalAlignment]::Stretch
    $border.VerticalAlignment = [Windows.VerticalAlignment]::Stretch

    $row0 = New-Object Windows.Controls.RowDefinition; $row0.Height = [Windows.GridLength]::Auto
    $row1 = New-Object Windows.Controls.RowDefinition; $row1.Height = [Windows.GridLength]::new(1, [Windows.GridUnitType]::Star)
    $row2 = New-Object Windows.Controls.RowDefinition; $row2.Height = [Windows.GridLength]::Auto
    $grid.RowDefinitions.Add($row0)
    $grid.RowDefinitions.Add($row1)
    $grid.RowDefinitions.Add($row2)

    $stackPanel = New-Object Windows.Controls.StackPanel
    $stackPanel.Margin = New-Object Windows.Thickness(10)
    $stackPanel.Orientation = [Windows.Controls.Orientation]::Horizontal
    $stackPanel.HorizontalAlignment = [Windows.HorizontalAlignment]::Left
    $stackPanel.VerticalAlignment = [Windows.VerticalAlignment]::Top
    $grid.Children.Add($stackPanel)
    [Windows.Controls.Grid]::SetRow($stackPanel, 0)

    $stackPanel.Children.Add((Invoke-WinUtilAssets -Type "logo" -Size $LogoSize))

    $winutilTextBlock = New-Object Windows.Controls.TextBlock
    $winutilTextBlock.Text = "WinUtil"
    $winutilTextBlock.FontSize = $HeaderFontSize
    $winutilTextBlock.Foreground = $LogoColor
    $winutilTextBlock.Margin = New-Object Windows.Thickness(10, 10, 10, 5)
    $stackPanel.Children.Add($winutilTextBlock)
    # Adiciona um TextBlock para as informações com quebra de texto e margens
    $messageTextBlock = New-Object Windows.Controls.TextBlock
    $messageTextBlock.FontSize = $FontSize
    $messageTextBlock.TextWrapping = [Windows.TextWrapping]::Wrap  # Habilita a quebra de texto
    $messageTextBlock.HorizontalAlignment = [Windows.HorizontalAlignment]::Left
    $messageTextBlock.VerticalAlignment = [Windows.VerticalAlignment]::Top
    $messageTextBlock.Margin = New-Object Windows.Thickness(10)  # Adiciona margens ao redor do bloco de texto

    # Define a expressão regular para encontrar hiperlinks formatados como tags HTML <a>
    $regex = [regex]::new('<a href="([^"]+)">([^<]+)</a>')
    $lastPos = 0
    $linkHoverBrush = $LinkHoverForegroundColor

    # Percorre cada correspondência e adiciona o texto normal e os hiperlinks
    foreach ($match in $regex.Matches($Message)) {
        # Adiciona o texto anterior ao hiperlink, se houver
        $textBefore = $Message.Substring($lastPos, $match.Index - $lastPos)
        if ($textBefore.Length -gt 0) {
            $messageTextBlock.Inlines.Add((New-Object Windows.Documents.Run($textBefore)))
        }

        # Cria e adiciona o hiperlink
        $hyperlink = New-Object Windows.Documents.Hyperlink
        $hyperlink.NavigateUri = New-Object System.Uri($match.Groups[1].Value)
        $hyperlink.Inlines.Add($match.Groups[2].Value)
        $hyperlink.TextDecorations = [Windows.TextDecorations]::None  # Remove o sublinhado
        $hyperlink.Foreground = $LinkForegroundColor

        $hyperlink.Add_Click({
            param($eventSender, $routedEvent)
            $null = $routedEvent
            Start-Process $eventSender.NavigateUri.AbsoluteUri
        })
        $hyperlink.Add_MouseEnter({
            param($eventSender, $routedEvent)
            $null = $routedEvent
            $eventSender.Foreground = $linkHoverBrush
            $eventSender.FontSize = ($FontSize + ($FontSize / 4))
            $eventSender.FontWeight = "SemiBold"
        })
        $hyperlink.Add_MouseLeave({
            param($eventSender, $routedEvent)
            $null = $routedEvent
            $eventSender.Foreground = $LinkForegroundColor
            $eventSender.FontSize = $FontSize
            $eventSender.FontWeight = "Normal"
        })

        $messageTextBlock.Inlines.Add($hyperlink)

        # Atualiza a última posição
        $lastPos = $match.Index + $match.Length
    }

    # Adiciona qualquer texto restante após o último hiperlink
    if ($lastPos -lt $Message.Length) {
        $textAfter = $Message.Substring($lastPos)
        $messageTextBlock.Inlines.Add((New-Object Windows.Documents.Run($textAfter)))
    }

    # Se não houver correspondências, adiciona a mensagem inteira como um run
    if ($regex.Matches($Message).Count -eq 0) {
        $messageTextBlock.Inlines.Add((New-Object Windows.Documents.Run($Message)))
    }

    # Cria um ScrollViewer se EnableScroll for verdadeiro
    if ($EnableScroll) {
        $scrollViewer = New-Object System.Windows.Controls.ScrollViewer
        $scrollViewer.VerticalScrollBarVisibility = 'Auto'
        $scrollViewer.HorizontalScrollBarVisibility = 'Disabled'
        $scrollViewer.Content = $messageTextBlock
        $grid.Children.Add($scrollViewer)
        [Windows.Controls.Grid]::SetRow($scrollViewer, 1)  # Define a linha como a segunda (índice baseado em 0)
    } else {
        $grid.Children.Add($messageTextBlock)
        [Windows.Controls.Grid]::SetRow($messageTextBlock, 1)  # Define a linha como a segunda (índice baseado em 0)
    }

    # Adiciona o botão OK
    $okButton = New-Object Windows.Controls.Button
    $okButton.Content = "OK"
    $okButton.FontSize = $FontSize
    $okButton.Width = 80
    $okButton.Height = 30
    $okButton.HorizontalAlignment = [Windows.HorizontalAlignment]::Center
    $okButton.VerticalAlignment = [Windows.VerticalAlignment]::Bottom
    $okButton.Margin = New-Object Windows.Thickness(0, 0, 0, 10)
    $okButton.Background = $buttonBackgroundColor
    $okButton.Foreground = $buttonForegroundColor
    $okButton.BorderBrush = $BorderColor
    $okButton.Add_Click({
        $dialog.Close()
    })
    $grid.Children.Add($okButton)
    [Windows.Controls.Grid]::SetRow($okButton, 2)  # Define a linha como a terceira (índice baseado em 0)

    # Trata o pressionamento da tecla Escape para fechar o diálogo
    $dialog.Add_KeyDown({
        if ($_.Key -eq 'Escape') {
            $dialog.Close()
        }
    })

    # Define o botão OK como botão padrão (ativado com Enter)
    $okButton.IsDefault = $true

    # Exibe o diálogo personalizado
    $dialog.ShowDialog()
}
