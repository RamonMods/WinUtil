function Invoke-WinutilThemeChange {
    <#
    .SYNOPSIS
        Alterna entre os temas claro e escuro de um aplicativo utilitário do Windows.

    .DESCRIPTION
        Esta função alterna o tema da interface do usuário entre os modos 'Light' e 'Dark',
        modificando diversos elementos da interface, como cores, margens, raios de canto, fontes, etc.
        Se a opção '-init' for usada, inicializa o tema com base na configuração atual de modo escuro do sistema.

    .EXAMPLE
        Invoke-WinutilThemeChange
        # Alterna o tema entre 'Light' e 'Dark'.


    #>
    param (
        [string]$theme = "Auto"
    )

    function Set-WinutilTheme {
        <#
        .SYNOPSIS
            Aplica o tema especificado à interface do usuário do aplicativo.

        .DESCRIPTION
            Esta função interna aplica o tema informado definindo as propriedades relevantes
            como cores, fontes, raios de canto, etc., na interface. Ela usa a função
            auxiliar 'Set-ThemeResourceProperty' para modificar os recursos do aplicativo.

        .PARAMETER currentTheme
            O nome do tema a ser aplicado. Valores comuns são "Light", "Dark" ou "shared".
        #>
        param (
            [string]$currentTheme
        )

        function Set-ThemeResourceProperty {
            <#
            .SYNOPSIS
                Define uma propriedade específica da interface nos recursos do aplicativo.

            .DESCRIPTION
                Esta função auxiliar define uma propriedade (ex.: cor, margem, raio de canto) nos
                recursos do aplicativo, com base no tipo e no valor informados. Ela inclui
                tratamento de erros para lidar com possíveis problemas ao definir uma propriedade.

            .PARAMETER Name
                O nome da propriedade de recurso a ser modificada (ex.: "MainBackgroundColor", "ButtonBackgroundMouseoverColor").

            .PARAMETER Value
                O valor a atribuir à propriedade de recurso (ex.: "#FFFFFF" para uma cor).

            .PARAMETER Type
                O tipo do recurso, como "ColorBrush", "CornerRadius", "GridLength" ou "FontFamily".
            #>
            param($Name, $Value, $Type)
            try {
                # Define a propriedade de recurso com base no seu tipo
                $sync.Form.Resources[$Name] = switch ($Type) {
                    "ColorBrush" { [Windows.Media.SolidColorBrush]::new($Value) }
                    "Color" {
                        # Converte a string hexadecimal em valores RGB
                        $hexColor = $Value.TrimStart("#")
                        $r = [Convert]::ToInt32($hexColor.Substring(0,2), 16)
                        $g = [Convert]::ToInt32($hexColor.Substring(2,2), 16)
                        $b = [Convert]::ToInt32($hexColor.Substring(4,2), 16)
                        [Windows.Media.Color]::FromRgb($r, $g, $b)
                    }
                    "CornerRadius" { [System.Windows.CornerRadius]::new($Value) }
                    "GridLength" { [System.Windows.GridLength]::new($Value) }
                    "Thickness" {
                        # Interpreta o valor de Thickness (aceita 1, 2 ou 4 entradas)
                        $values = $Value -split ","
                        switch ($values.Count) {
                            1 { [System.Windows.Thickness]::new([double]$values[0]) }
                            2 { [System.Windows.Thickness]::new([double]$values[0], [double]$values[1]) }
                            4 { [System.Windows.Thickness]::new([double]$values[0], [double]$values[1], [double]$values[2], [double]$values[3]) }
                        }
                    }
                    "FontFamily" { [Windows.Media.FontFamily]::new($Value) }
                    "Double" { [double]$Value }
                    default { $Value }
                }
            }
            catch {
                # Registra um aviso se houver problema ao definir a propriedade
                Write-Warning "Falha ao definir a propriedade $($Name): $_"
            }
        }

        # Recupera todas as propriedades do tema da configuração
        $themeProperties = $sync.configs.themes.$currentTheme.PSObject.Properties
        foreach ($themeProperty in $themeProperties) {
            # Aplica as propriedades relacionadas a cores
            if ($themeProperty.Name -like "*color*") {
                Set-ThemeResourceProperty -Name $themeProperty.Name -Value $themeProperty.Value -Type "ColorBrush"
                # Para certas propriedades de cor, defina também valores complementares (ex.: BorderColor -> CBorderColor). Isso é necessário porque, por exemplo, DropShadowEffect exige um objeto <Color> e não um <SolidColorBrush>
                if ($themeProperty.Name -in @("BorderColor", "ButtonBackgroundMouseoverColor", "AppIconShadowColor", "MainGradientTopColor", "MainGradientBottomColor")) {
                    Set-ThemeResourceProperty -Name "C$($themeProperty.Name)" -Value $themeProperty.Value -Type "Color"
                }
            }
            # Aplica propriedades de raio de canto
            elseif ($themeProperty.Name -like "*Radius*") {
                Set-ThemeResourceProperty -Name $themeProperty.Name -Value $themeProperty.Value -Type "CornerRadius"
            }
            # Aplica propriedades de altura de linha
            elseif ($themeProperty.Name -like "*RowHeight*") {
                Set-ThemeResourceProperty -Name $themeProperty.Name -Value $themeProperty.Value -Type "GridLength"
            }
            # Aplica propriedades de espessura ou margem
            elseif (($themeProperty.Name -like "*Thickness*") -or ($themeProperty.Name -like "*margin")) {
                Set-ThemeResourceProperty -Name $themeProperty.Name -Value $themeProperty.Value -Type "Thickness"
            }
            # Aplica propriedades de fonte
            elseif ($themeProperty.Name -like "*FontFamily*") {
                Set-ThemeResourceProperty -Name $themeProperty.Name -Value $themeProperty.Value -Type "FontFamily"
            }
            # Aplica quaisquer outras propriedades como doubles (valores numéricos)
            else {
                Set-ThemeResourceProperty -Name $themeProperty.Name -Value $themeProperty.Value -Type "Double"
            }
        }
    }

    $sync.preferences.theme = $theme
    Set-WinutilTheme -currentTheme "shared"

    switch ($sync.preferences.theme) {
        "Auto" {
            $systemUsesDarkMode = Get-WinUtilToggleStatus WPFToggleDarkMode
            if ($systemUsesDarkMode) {
                $theme = "Dark"
            }
            else{
                $theme = "Light"
            }

            Set-WinutilTheme -currentTheme $theme
            $themeButtonIcon = [char]0xF08C
        }
        "Dark" {
            Set-WinutilTheme -currentTheme $sync.preferences.theme
            $themeButtonIcon = [char]0xE708
           }
        "Light" {
            Set-WinutilTheme -currentTheme $sync.preferences.theme
            $themeButtonIcon = [char]0xE706
        }
    }

    # Reaplica a escala de fonte se ela tiver sido definida antes (a mudança de tema redefine os recursos compartilhados)
    if ($sync.ContainsKey("FontScaleFactor") -and $sync.FontScaleFactor -ne 1.0) {
        Invoke-WinUtilFontScaling -ScaleFactor $sync.FontScaleFactor
    }

    # Atualiza o botão de seleção de tema com o ícone apropriado
    $ThemeButton = $sync.Form.FindName("ThemeButton")
    $ThemeButton.Content = [string]$themeButtonIcon
}
