function Get-WinUtilAppEntryHandlers {
    <#
        .SYNOPSIS
            Os tratadores de evento compartilhados por toda entrada de app na aba Instalar

        .DESCRIPTION
            Criar tratadores por entrada é grande parte do custo de desenhar a lista de apps, e
            nenhum deles precisa ser por entrada. Cliques e mudanças de marcação sobem pela árvore, então cada
            painel de categoria carrega um conjunto (veja Initialize-InstallCategoryAppList) que encontra a entrada
            de onde o evento veio. Passar o mouse é um gatilho em AppEntryBorderStyle.

            Os tratadores são criados uma vez e reutilizados, e leem tudo do evento, então uma
            única instância serve para todos os apps.
    #>

    if ($null -ne $script:WinUtilAppEntryHandlers) {
        return $script:WinUtilAppEntryHandlers
    }

    $script:WinUtilAppEntryHandlers = @{
        BorderClick = [Windows.Input.MouseButtonEventHandler]{
            param($sender, $e)
            $entry = Get-WinUtilAppEntryFromElement -Element $e.OriginalSource
            if ($entry) {
                $childCheckbox = $sync.$($entry.Tag)
                $childCheckbox.IsChecked = -not $childCheckbox.IsChecked
            }
        }
        RightClick = [Windows.Input.MouseButtonEventHandler]{
            param($sender, $e)
            $entry = Get-WinUtilAppEntryFromElement -Element $e.OriginalSource
            if ($entry) {
                # Guarda o app selecionado em uma variável global para usá-lo no popup
                $sync.appPopupSelectedApp = $entry.Tag
                # Define a posição do popup na posição atual do mouse
                $sync.appPopup.PlacementTarget = $entry
                $sync.appPopup.IsOpen = $true
            }
        }
        # A caixa de seleção fica dentro do Grid de layout da entrada, então a borda está um nível acima
        Checked = [Windows.RoutedEventHandler]{
            param($sender, $e)
            $checkBox = $e.OriginalSource
            if ($checkBox -is [Windows.Controls.CheckBox] -and $checkBox.Tag -is [string] -and $checkBox.Tag.StartsWith("WPFInstall")) {
                Invoke-WPFSelectedCheckboxesUpdate -type "Add" -checkboxName $checkBox.Tag
                $checkBox.Parent.Parent.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, "AppInstallSelectedColor")
            }
        }
        Unchecked = [Windows.RoutedEventHandler]{
            param($sender, $e)
            $checkBox = $e.OriginalSource
            if ($checkBox -is [Windows.Controls.CheckBox] -and $checkBox.Tag -is [string] -and $checkBox.Tag.StartsWith("WPFInstall")) {
                Invoke-WPFSelectedCheckboxesUpdate -type "Remove" -checkboxName $checkBox.Tag
                # Volta à cor do estilo, o que também restaura o realce ao passar o mouse
                $checkBox.Parent.Parent.ClearValue([Windows.Controls.Border]::BackgroundProperty)
            }
        }
        ImageFailed = {
            $this.Visibility = "Collapsed"
            $this.Parent.Children[0].Visibility = "Visible"
        }
    }

    return $script:WinUtilAppEntryHandlers
}
