function New-WinUtilFossBadge {
    <#
        .SYNOPSIS
            Cria o marcador FOSS: o buraco de fechadura de código aberto sobre um fundo verde
        .DESCRIPTION
            Retorna um elemento novo a cada chamada, porque um elemento WPF só pode ter um pai.
            A arte é criada em uma caixa de 22x22 e escalada pelo Viewbox, portanto os chamadores só escolhem um tamanho.
        .PARAMETER Size
            Comprimento da borda do selo em pixels
        .PARAMETER Round
            Usa um círculo completo em vez do triângulo no canto, para a legenda em vez de uma entrada de aplicativo
    #>
    param(
        [double]$Size = 24,
        [switch]$Round
    )

    $artwork = New-Object Windows.Controls.Grid
    $artwork.Width = 22
    $artwork.Height = 22

    $backdrop = New-Object Windows.Shapes.Path
    $backdrop.Fill = [Windows.Media.SolidColorBrush]::new([Windows.Media.Color]::FromRgb(19, 143, 83))
    $keyhole = New-Object Windows.Shapes.Path
    $keyhole.Stroke = [Windows.Media.SolidColorBrush]::new([Windows.Media.Color]::FromRgb(247, 247, 247))

    if ($Round) {
        $backdrop.Data = [Windows.Media.EllipseGeometry]::new([Windows.Point]::new(11, 11), 11, 11)
        # Buraco de fechadura centralizado no círculo, que tem espaço para um anel maior do que o triângulo
        $keyhole.Data = [Windows.Media.Geometry]::Parse("M 7.673,15.751 A 5.8,5.8 0 1 1 14.327,15.751")
        $keyhole.StrokeThickness = 3.4
    } else {
        # Triângulo preenchendo o canto superior direito, com o canto externo arredondado para combinar com AppEntryBorderStyle
        $backdrop.Data = [Windows.Media.Geometry]::Parse("M 0,0 L 17,0 A 5,5 0 0 1 22,5 L 22,22 Z")
        # Buraco de fechadura centralizado no incentro do triângulo (15.56, 6.44) para manter a mesma
        # folga de 1.8 em relação às três bordas
        $keyhole.Data = [Windows.Media.Geometry]::Parse("M 13.61,9.225 A 3.4,3.4 0 1 1 17.51,9.225")
        $keyhole.StrokeThickness = 2.4
    }

    $keyhole.StrokeStartLineCap = [Windows.Media.PenLineCap]::Round
    $keyhole.StrokeEndLineCap = [Windows.Media.PenLineCap]::Round
    [void]$artwork.Children.Add($backdrop)
    [void]$artwork.Children.Add($keyhole)

    $badge = New-Object Windows.Controls.Viewbox
    $badge.Width = $Size
    $badge.Height = $Size
    $badge.Child = $artwork
    $badge.ToolTip = "Software Livre e de Código Aberto"

    return $badge
}
