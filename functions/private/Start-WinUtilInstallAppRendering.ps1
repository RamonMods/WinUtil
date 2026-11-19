function Invoke-WinUtilInstallAppRenderBatch {
    param(
        [Parameter(Mandatory = $true)]
        $CategoryBatch,

        # Quantas entradas construir nesta passagem. Cada entrada é construída em uma análise, então uma passagem
        # custa alguns milissegundos por dez entradas; o restante volta para a fila.
        [int]$ChunkSize = 40
    )

    $keys = @($CategoryBatch.AppKeys)
    $count = [Math]::Min($keys.Count, $ChunkSize)
    $chunk = @($keys[0..($count - 1)])

    # Isto roda no dispatcher, então mantenha a fatia livre de registro em log e outras operações de disco.
    $checkBoxes = @(Initialize-InstallAppEntries -TargetElement $CategoryBatch.TargetElement -AppKeys $chunk)
    for ($i = 0; $i -lt $chunk.Count; $i++) {
        $sync.($chunk[$i]) = $checkBoxes[$i]
    }

    if ($count -lt $keys.Count) {
        $sync.InstallAppRenderQueue.Enqueue([pscustomobject]@{
            Category = $CategoryBatch.Category
            TargetElement = $CategoryBatch.TargetElement
            AppKeys = @($keys[$count..($keys.Count - 1)])
        })
    }

    # As entradas são renderizadas em lotes, então um filtro já ativo precisa ser aplicado a cada novo
    # lote. Categorias contam como filtro ativo, assim como o texto de busca.
    if ($sync.currentTab -eq "Install" -and $sync.SearchBar) {
        $selectedCategories = if ($sync.SelectedAppCategories) { $sync.SelectedAppCategories.ToArray() } else { @() }

        if (-not [string]::IsNullOrWhiteSpace($sync.SearchBar.Text) -or $selectedCategories.Count -gt 0) {
            Find-AppsByNameOrDescription -SearchString $sync.SearchBar.Text -Categories $selectedCategories
        }
    }
}

function Complete-WinUtilInstallAppRendering {
    $sync.InstallAppEntriesRendered = $true

}

function Start-WinUtilInstallAppRendering {
    if ($null -eq $sync.InstallAppRenderQueue) {
        return
    }

    $sync.InstallAppEntriesRendered = $false

    # Antes de a janela ser exibida, nada espera pela thread da interface, então a lista inteira é
    # construída em uma passagem e a janela abre completa em vez de preencher aos poucos
    if ($sync.BuildingBeforeShow) {
        while ($sync.InstallAppRenderQueue.Count -gt 0) {
            Invoke-WinUtilInstallAppRenderBatch -CategoryBatch $sync.InstallAppRenderQueue.Dequeue() -ChunkSize ([int]::MaxValue)
        }
        Complete-WinUtilInstallAppRendering
        return
    }

    Start-WinUtilBackgroundQueue -Name "InstallAppRender" -Queue $sync.InstallAppRenderQueue `
        -RequiresTab "Install" `
        -Step { param($CategoryBatch) Invoke-WinUtilInstallAppRenderBatch -CategoryBatch $CategoryBatch } `
        -OnComplete { Complete-WinUtilInstallAppRendering } `
        -DeferWhile {
            # Abas que nunca foram construídas vêm primeiro. Esta lista já está na tela e sendo
            # preenchida, enquanto outra aba fica vazia até ser construída, então um clique nela custa
            # a construção inteira. A lista terminar um pouco depois não é notado; uma aba que leva
            # meio segundo para abrir, sim.
            $sync.TabWarmupQueue -and $sync.TabWarmupQueue.Count -gt 0
        }
}
