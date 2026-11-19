function Invoke-WinUtilFontScaling {
    <#

    .SYNOPSIS
        Aplica escala de interface e de fonte para acessibilidade

    .PARAMETER ScaleFactor
        Define a escala entre 0.75 e 2.0.
        O padrão é 1.0 (100% - sem escala)

    .EXAMPLE
        Invoke-WinUtilFontScaling -ScaleFactor 1.25
        # Aplica escala de 125%
    #>

    param (
        [double]$ScaleFactor = 1.0
    )

    # Valida se o fator de escala está dentro do intervalo
    if ($ScaleFactor -lt 0.75 -or $ScaleFactor -gt 2.0) {
        Write-Warning "O fator de escala deve estar entre 0.75 e 2.0. Usando 1.0 no lugar."
        $ScaleFactor = 1.0
    }

    # Define uma matriz de recursos a serem escalados
    $fontResources = @(
        # Fontes
        "FontSize",
        "ButtonFontSize",
        "HeaderFontSize",
        "Win11StepTitleFontSize",
        "Win11StepHeroFontSize",
        "TabButtonFontSize",
        "ConfigTabButtonFontSize",
        "IconFontSize",
        "SettingsIconFontSize",
        "CloseIconFontSize",
        "AppEntryFontSize",
        "SearchBarTextBoxFontSize",
        "SearchBarClearButtonFontSize",
        "CustomDialogFontSize",
        "CustomDialogFontSizeHeader",
        "ConfigUpdateButtonFontSize",
        # Botões e interface
        "CheckBoxBulletDecoratorSize",
        "ButtonWidth",
        "ButtonHeight",
        "TabButtonWidth",
        "TabButtonHeight",
        "IconButtonSize",
        "AppEntryWidth",
        "SearchBarWidth",
        "SearchBarHeight",
        "CustomDialogWidth",
        "CustomDialogHeight",
        "CustomDialogLogoSize",
        "ToolTipWidth"
    )

    # Aplica a escala a cada recurso
    foreach ($resourceName in $fontResources) {
        try {
            # Obtém o tamanho de fonte padrão da configuração do tema
            $originalValue = $sync.configs.themes.shared.$resourceName
            if ($originalValue) {
                # Converte a string para double, já que os valores são armazenados como strings
                $originalValue = [double]$originalValue
                # Calcula e aplica o novo tamanho de fonte
                $newValue = [math]::Round($originalValue * $ScaleFactor, 1)
                $sync.Form.Resources[$resourceName] = $newValue
            }
        }
        catch {
            Write-Warning "Falha ao escalar o recurso $resourceName : $_"
        }
    }

    # Armazena o fator de escala para poder reaplicá-lo depois de mudanças de tema
    $sync.FontScaleFactor = $ScaleFactor

    # A largura mínima dos cartões acabou de mudar, então os cartões precisam ser ajustados à linha novamente
    Update-WinUtilAppEntryWidth

    # Atualiza a porcentagem de escala de fonte exibida na interface
    if ($sync.FontScalingValue) {
        $percentage = [math]::Round($ScaleFactor * 100)
        $sync.FontScalingValue.Text = "$percentage%"
    }
}
