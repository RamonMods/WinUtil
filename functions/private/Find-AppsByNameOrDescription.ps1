function Find-AppsByNameOrDescription {
    <#
        .SYNOPSIS
            Filtra as entradas da aba Instalar por texto de busca e por categoria

        .DESCRIPTION
            Texto de busca e categorias são filtros independentes que precisam passar juntos. Uma entrada
            é exibida quando seu nome, descrição ou chave de predefinição do aplicativo corresponde ao texto
            buscado, e quando sua categoria está no conjunto selecionado. Uma busca vazia corresponde a
            tudo, e um conjunto de categorias vazio corresponde a todas as categorias.

            Enquanto um dos filtros está ativo, as categorias correspondentes são expandidas, já que uma
            categoria recolhida esconderia justamente os resultados pedidos. Sem nenhum filtro,
            o estado recolhido definido pelo usuário é restaurado.

        .PARAMETER SearchString
            O texto a buscar. Curingas são tratados como caracteres literais.

        .PARAMETER Categories
            As categorias a exibir. Uma matriz vazia ou ausente exibe todas.

        .NOTES
            - Usa $sync no escopo do módulo (sem parâmetro; herda do escopo do chamador)
            - Trata com segurança chaves ausentes na hashtable e elementos de interface nulos
            - Protegido por try/catch para evitar quedas da thread de interface
    #>
    param(
        [Parameter(Mandatory = $false)]
        [string]$SearchString = "",

        [Parameter(Mandatory = $false)]
        [string[]]$Categories = @()
    )

    # Valida que $sync existe e tem a estrutura necessária
    if ($null -eq $sync) {
        Write-Warning "Find-AppsByNameOrDescription: `$sync global não encontrado. Abortando a busca."
        return
    }

    if ($null -eq $sync.ItemsControl) {
        Write-Warning "Find-AppsByNameOrDescription: `$sync.ItemsControl não inicializado. Abortando a busca."
        return
    }

    if ($null -eq $sync.configs -or $null -eq $sync.configs.applicationsHashtable) {
        Write-Warning "Find-AppsByNameOrDescription: `$sync.configs.applicationsHashtable não inicializado. Abortando a busca."
        return
    }

    # Categorias que a filtragem expandiu em nome do usuário, para que limpar o filtro possa desfazer isso
    if ($null -eq $sync.AppCategoryAutoExpanded) {
        $sync.AppCategoryAutoExpanded = @{}
    }

    try {
        $activeCategories = @($Categories | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        $hasSearch = -not [string]::IsNullOrWhiteSpace($SearchString)
        $hasCategories = $activeCategories.Count -gt 0

        # Nada está filtrado, então devolve todas as entradas e deixa as categorias recolhidas recolhidas
        if (-not $hasSearch -and -not $hasCategories) {
            $sync.ItemsControl.Items | ForEach-Object {
                $_.Visibility = [Windows.Visibility]::Visible

                if ($_.Children.Count -ge 2) {
                    $categoryLabel = $_.Children[0]
                    $wrapPanel = $_.Children[1]

                    $categoryLabel.Visibility = [Windows.Visibility]::Visible

                    # Uma categoria que a filtragem expandiu volta a como o usuário a deixou
                    $categoryName = $categoryLabel.Content -replace '^[+-] ', ''
                    if ($sync.AppCategoryAutoExpanded.ContainsKey($categoryName)) {
                        $categoryLabel.Content = $categoryLabel.Content -replace "^- ", "+ "
                        $sync.AppCategoryAutoExpanded.Remove($categoryName)
                    }

                    if ($categoryLabel.Content -like "+*") {
                        $wrapPanel.Visibility = [Windows.Visibility]::Collapsed
                    }
                    else {
                        $wrapPanel.Visibility = [Windows.Visibility]::Visible
                    }

                    $wrapPanel.Children | ForEach-Object {
                        $_.Visibility = [Windows.Visibility]::Visible
                    }
                }
            }
            return
        }

        # IndexOf com OrdinalIgnoreCase é mais rápido que -like com escape de curinga
        $sync.ItemsControl.Items | ForEach-Object {
            if ($_.Children.Count -ge 2) {
                $categoryLabel = $_.Children[0]
                $wrapPanel = $_.Children[1]
                $categoryHasMatch = $false
                $categoryLabel.Visibility = [Windows.Visibility]::Visible

                foreach ($appControl in $wrapPanel.Children) {
                    $appTag = $appControl.Tag
                    $appEntry = $null
                    if (-not [string]::IsNullOrWhiteSpace($appTag) -and $sync.configs.applicationsHashtable.ContainsKey($appTag)) {
                        $appEntry = $sync.configs.applicationsHashtable[$appTag]
                    }

                    if ($null -ne $appEntry) {
                        $categoryMatch = -not $hasCategories -or $activeCategories -contains $appEntry.Category
                        $textMatch = -not $hasSearch -or
                            ([string]$appEntry.Content).IndexOf($SearchString, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -or
                            ([string]$appEntry.Description).IndexOf($SearchString, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -or
                            ([string]$appTag).IndexOf($SearchString, [System.StringComparison]::OrdinalIgnoreCase) -ge 0

                        if ($categoryMatch -and $textMatch) {
                            $appControl.Visibility = [Windows.Visibility]::Visible
                            $categoryHasMatch = $true
                        } else {
                            $appControl.Visibility = [Windows.Visibility]::Collapsed
                        }
                    } else {
                        $appControl.Visibility = [Windows.Visibility]::Collapsed
                    }
                }

                if ($categoryHasMatch) {
                    $wrapPanel.Visibility = [Windows.Visibility]::Visible
                    $_.Visibility = [Windows.Visibility]::Visible
                    # Expande, senão os resultados ficam escondidos atrás de um cabeçalho recolhido.
                    # Lembra que estava recolhida para que limpar o filtro possa restaurá-la.
                    if ($categoryLabel.Content -like "+*") {
                        $categoryLabel.Content = $categoryLabel.Content -replace "^\+ ", "- "
                        $sync.AppCategoryAutoExpanded[($categoryLabel.Content -replace '^- ', '')] = $true
                    }
                }
                else {
                    $_.Visibility = [Windows.Visibility]::Collapsed
                }
            }
        }
    }
    catch {
        Write-Warning "Find-AppsByNameOrDescription: ocorreu um erro durante a busca: $_"
        # Falha com elegância - não derrube a thread da interface
        return
    }
}
