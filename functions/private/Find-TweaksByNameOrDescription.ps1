function Find-TweaksByNameOrDescription {
    <#
    .SYNOPSIS
        Filtra entradas de ajustes/appx por nome ou descrição usando correspondência literal de texto.
    .PARAMETER SearchString
        O texto a buscar. Tratado como literal (sem expansão de curinga).
    #>
    param(
        [string]$SearchString = ""
    )

    # $sync está sempre no escopo no script compilado - não é preciso fallback em vários níveis
    if ($null -eq $sync -or $null -eq $sync.Form) { return }

    if ($null -eq $sync.TweakCategoryAutoExpanded) {
        $sync.TweakCategoryAutoExpanded = @{}
    }

    $panelName = if ($sync.currentTab -eq "AppX") { "appxpanel" } else { "tweakspanel" }
    try { $tweaksPanel = $sync.Form.FindName($panelName) } catch { return }
    if ($null -eq $tweaksPanel) { return }

    # --- Auxiliar: extrai o texto pesquisável de um item DockPanel ou StackPanel ---
    function Get-ItemSearchText($item) {
        $text = ""; $tip = ""
        if ($item -is [Windows.Controls.DockPanel]) {
            $label = $item.Children | Where-Object { $_ -is [Windows.Controls.Label] } | Select-Object -First 1
            if ($label) { $text = [string]$label.Content; $tip = [string]$label.ToolTip }
        } elseif ($item -is [Windows.Controls.StackPanel]) {
            $cb = $item.Children | Where-Object { $_ -is [Windows.Controls.CheckBox] } | Select-Object -First 1
            if ($cb) { $text = [string]$cb.Content; $tip = [string]$cb.ToolTip }
        }
        return @{ Text = $text; Tip = $tip.Replace("Preset key: ", "") }
    }

    try {
        # Restaura a visibilidade quando a busca é limpa
        if ([string]::IsNullOrWhiteSpace($SearchString)) {
            foreach ($categoryBorder in $tweaksPanel.Children) {
                if ($null -eq $categoryBorder) { continue }
                $categoryBorder.Visibility = [Windows.Visibility]::Visible
                if ($categoryBorder -is [Windows.Controls.Border] -and $categoryBorder.Child -is [Windows.Controls.DockPanel]) {
                    $container = $categoryBorder.Child.Children | Where-Object { $_ -is [Windows.Controls.ItemsControl] -or $_ -is [Windows.Controls.StackPanel] -or $_ -is [Windows.Controls.ScrollViewer] } | Select-Object -First 1
                    if ($container) {
                        $targetPanel = if ($container -is [Windows.Controls.ScrollViewer]) { $container.Content } else { $container }
                        $items = if ($targetPanel -is [Windows.Controls.ItemsControl]) { $targetPanel.Items } else { $targetPanel.Children }
                        foreach ($item in $items) {
                            if ($null -eq $item) { continue }
                            if ($item -is [Windows.Controls.Label]) {
                                $item.Visibility = [Windows.Visibility]::Visible
                                # Uma categoria que a filtragem expandiu volta a como o usuário a deixou
                                $labelStr = [string]$item.Content
                                $categoryName = $labelStr -replace '^[+-] ', ''
                                if ($sync.TweakCategoryAutoExpanded.ContainsKey($categoryName)) {
                                    $item.Content = $labelStr -replace "^- ", "+ "
                                    $labelStr = [string]$item.Content
                                    $sync.TweakCategoryAutoExpanded.Remove($categoryName)
                                }
                                # Respeita o estado recolhido: rótulos que começam com "+" mantêm os itens recolhidos
                                if ($labelStr.StartsWith("+ ")) {
                                    $collapsed = $true
                                } else {
                                    $collapsed = $false
                                }
                            } else {
                                $item.Visibility = if ($collapsed) { [Windows.Visibility]::Collapsed } else { [Windows.Visibility]::Visible }
                            }
                        }
                    }
                }
            }
            return
        }

        # Executa a busca literal
        foreach ($categoryBorder in $tweaksPanel.Children) {
            $categoryHasMatch = $false
            if (-not ($categoryBorder -is [Windows.Controls.Border])) { continue }
            if (-not ($categoryBorder.Child -is [Windows.Controls.DockPanel])) { continue }

            $container = $categoryBorder.Child.Children | Where-Object { $_ -is [Windows.Controls.ItemsControl] -or $_ -is [Windows.Controls.StackPanel] -or $_ -is [Windows.Controls.ScrollViewer] } | Select-Object -First 1
            if ($null -eq $container) { continue }

            $targetPanel = if ($container -is [Windows.Controls.ScrollViewer]) { $container.Content } else { $container }
            $items = if ($targetPanel -is [Windows.Controls.ItemsControl]) { $targetPanel.Items } else { $targetPanel.Children }

            $categoryLabel = $null
            for ($i = 0; $i -lt $items.Count; $i++) {
                $item = $items[$i]
                if ($null -eq $item) { continue }

                if ($item -is [Windows.Controls.Label]) {
                    $categoryLabel = $item
                    $item.Visibility = [Windows.Visibility]::Collapsed
                    continue
                }

                # Busca unificada para itens DockPanel e StackPanel
                if ($item -is [Windows.Controls.DockPanel] -or $item -is [Windows.Controls.StackPanel]) {
                    $search = Get-ItemSearchText $item
                    $isMatch = ($search.Text -and $search.Text.IndexOf($SearchString, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) -or
                               ($search.Tip -and $search.Tip.IndexOf($SearchString, [System.StringComparison]::OrdinalIgnoreCase) -ge 0)

                    if ($isMatch) {
                        $item.Visibility = [Windows.Visibility]::Visible
                        $categoryHasMatch = $true
                    } else {
                        $item.Visibility = [Windows.Visibility]::Collapsed
                    }
                }
            }

            # Atualiza o rótulo da categoria e a visibilidade da borda
            if ($categoryHasMatch -and $null -ne $categoryLabel) {
                $categoryLabel.Visibility = [Windows.Visibility]::Visible
                $labelStr = [string]$categoryLabel.Content
                if ($labelStr.StartsWith("+ ")) {
                    $categoryLabel.Content = "- " + $labelStr.Substring(2)
                    $sync.TweakCategoryAutoExpanded[($labelStr.Substring(2))] = $true
                }
            }
            $categoryBorder.Visibility = if ($categoryHasMatch) { [Windows.Visibility]::Visible } else { [Windows.Visibility]::Collapsed }
        }
    } catch {
        # Registra em log em vez de engolir em silêncio - mas só em DEBUG para evitar spam a cada tecla
        Write-WinUtilLog -Level "DEBUG" -Component "Search" -Message "Erro na busca de ajustes: $($_.Exception.Message)"
    }
}
