function Update-WinUtilSelections {
    param(
        [Parameter(Mandatory)]
        [string[]]$flatJson,

        [switch]$Replace,

        [switch]$SkipUnknown
    )

    $nextSelections = @{
        selectedApps     = [System.Collections.Generic.List[string]]::new()
        selectedTweaks   = [System.Collections.Generic.List[string]]::new()
        selectedToggles  = [System.Collections.Generic.List[string]]::new()
        selectedFeatures = [System.Collections.Generic.List[string]]::new()
        selectedAppx     = [System.Collections.Generic.List[string]]::new()
    }

    foreach ($cbkey in $flatJson) {

        $listName = switch -Regex ($cbkey) {
            '^WPFInstall' { 'selectedApps' }
            '^WPFTweaks'  { 'selectedTweaks' }
            '^WPFToggle'  { 'selectedToggles' }
            '^WPFFeature' { 'selectedFeatures' }
            '^WPFAppx'    { 'selectedAppx' }
        }

        if (-not $listName) {
            if ($SkipUnknown) {
                $cbkey
                continue
            }
            throw "Chave de seleção não suportada: '$cbkey'."
        }

        $isKnownSelection = switch ($listName) {
            'selectedApps' {
                $sync.configs.applicationsHashtable.ContainsKey($cbkey)
            }
            'selectedTweaks' {
                $null -ne $sync.configs.tweaks.PSObject.Properties[$cbkey]
            }
            'selectedToggles' {
                $null -ne $sync.configs.tweaks.PSObject.Properties[$cbkey]
            }
            'selectedFeatures' {
                $null -ne $sync.configs.feature.PSObject.Properties[$cbkey]
            }
            'selectedAppx' {
                $sync.configs.appxHashtable.ContainsKey($cbkey)
            }
        }

        if (-not $isKnownSelection) {
            if ($SkipUnknown) {
                $cbkey
                continue
            }
            throw "Chave de seleção desconhecida: '$cbkey'."
        }

        # Importa��es de substitui��o tamb�m devem se comportar como sele��es de caixa de sele��o, n�o como a��es repetidas.
        if ($nextSelections[$listName] -notcontains $cbkey) {
            $nextSelections[$listName].Add($cbkey)
        }
    }

    $validSelectionCount = ($nextSelections.Values | ForEach-Object { $_.Count } | Measure-Object -Sum).Sum
    if ($SkipUnknown -and $validSelectionCount -eq 0) {
        return
    }

    if ($Replace) {
        foreach ($listName in $nextSelections.Keys) {
            $sync[$listName] = $nextSelections[$listName]
        }
        return
    }

    foreach ($listName in $nextSelections.Keys) {
        foreach ($cbkey in $nextSelections[$listName]) {
            # Ao acrescentar, a mesma entrada pode j� estar presente: uma predefini��o e uma configura��o que a
            # nomeiam acabariam selecionando-a duas vezes
            if ($sync.$listName -notcontains $cbkey) {
                $sync.$listName.Add($cbkey)
            }
        }
    }
}
