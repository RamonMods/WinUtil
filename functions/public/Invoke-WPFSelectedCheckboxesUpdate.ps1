function Invoke-WPFSelectedCheckboxesUpdate ($type, $checkboxName) {
    $listName = switch -Regex ($checkboxName) {
        '^WPFInstall' { 'selectedApps' }
        '^WPFTweaks'  { 'selectedTweaks' }
        '^WPFToggle'  { 'selectedToggles' }
        '^WPFFeature' { 'selectedFeatures' }
        '^WPFAppx'    { 'selectedAppx' }
    }

    $selectionChanged = $false
    if ($type -eq "Add") {
        if ($sync.$listName -notcontains $checkboxName) {
            $sync.$listName.Add($checkboxName)
            $selectionChanged = $true
        }
    } else {
        # As chaves importadas são validadas sem diferenciar maiúsculas de minúsculas, portanto os eventos das caixas
        # de seleção devem usar a mesma comparação, mesmo quando a grafia importada for diferente.
        for ($index = $sync.$listName.Count - 1; $index -ge 0; $index--) {
            if ($sync.$listName[$index] -eq $checkboxName) {
                $sync.$listName.RemoveAt($index)
                $selectionChanged = $true
            }
        }
    }

    if ($listName -eq "selectedApps" -and $selectionChanged) {
        $sync.WPFselectedAppsButton.Content = "Aplicativos selecionados: $($sync.selectedApps.Count)"
        $sync.selectedAppsstackPanel.Children.Clear()
        $sync.selectedApps | Sort-Object | ForEach-Object {
            Add-SelectedAppsMenuItem -name $sync.configs.applicationsHashtable.$_.Content -key $_
        }
    }
}
