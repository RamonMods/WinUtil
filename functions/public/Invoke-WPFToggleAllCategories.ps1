function Invoke-WPFToggleAllCategories {
    <#
        .SYNOPSIS
            Expande ou recolhe todas as categorias na aba Instalar

        .PARAMETER Action
            A ação a executar: "Expand" ou "Collapse"

        .DESCRIPTION
            Esta função percorre todos os contêineres de categoria na aba Instalar
            e expande ou recolhe seus WrapPanels enquanto atualiza os rótulos dos botões de alternância
    #>

    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet("Expand", "Collapse")]
        [string]$Action
    )

    try {
        if ($null -eq $sync.ItemsControl) {
            Write-Warning "ItemsControl não inicializado"
            return
        }

        $targetVisibility = if ($Action -eq "Expand") { [Windows.Visibility]::Visible } else { [Windows.Visibility]::Collapsed }
        $targetPrefix = if ($Action -eq "Expand") { "-" } else { "+" }
        $sourcePrefix = if ($Action -eq "Expand") { "+" } else { "-" }

        # Itera por todos os itens no ItemsControl
        $sync.ItemsControl.Items | ForEach-Object {
            $categoryContainer = $_

            # Verifica se este é um contêiner de categoria (StackPanel com filhos)
            if ($categoryContainer -is [System.Windows.Controls.StackPanel] -and $categoryContainer.Children.Count -ge 2) {
                # Obtém o WrapPanel (segundo filho)
                $wrapPanel = $categoryContainer.Children[1]
                $wrapPanel.Visibility = $targetVisibility

                # Atualiza o rótulo para mostrar o estado correto
                $categoryLabel = $categoryContainer.Children[0]
                if ($categoryLabel.Content -like "$sourcePrefix*") {
                    $escapedSourcePrefix = [regex]::Escape($sourcePrefix)
                    $categoryLabel.Content = $categoryLabel.Content -replace "^$escapedSourcePrefix ", "$targetPrefix "
                }
            }
        }
    }
    catch {
        Write-Error "Erro ao alternar categorias: $_"
    }
}
