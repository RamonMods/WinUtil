function Reset-WPFCheckBoxes {
    <#

    .SYNOPSIS
        Define as caixas de seleção do WinUtil para corresponder aos valores de $sync.selected.
        Só deve ser necessário executar se $sync.selected foi atualizado fora da interface (ou seja, predefinições ou importação)

    .PARAMETER doToggles
        Se deve ou não definir os interruptores da interface. AVISO: eles serão acionados se alterados

    .PARAMETER checkboxfilterpattern
        O padrão a usar ao filtrar as caixas de seleção; o padrão é "**"
        Usado para tornar a redefinição extremamente rápida.
    #>

    param (
        [Parameter(position=0)]
        [bool]$doToggles = $false,

        [Parameter(position=1)]
        [string]$checkboxfilterpattern = "**"
    )
    $selectedSet = [System.Collections.Generic.HashSet[string]]::new([string[]]@($sync.selectedApps + $sync.selectedTweaks + $sync.selectedFeatures + $sync.selectedAppx), [StringComparer]::OrdinalIgnoreCase)

    # Uma Hashtable sincronizada protege operações individuais, não a enumeração. Materialize o
    # snapshot sob seu bloqueio e libere-o antes que os handlers executem e alterem $sync.
    [System.Threading.Monitor]::Enter($sync.SyncRoot)
    try {
        $syncEntries = @($sync.GetEnumerator())
    } finally {
        [System.Threading.Monitor]::Exit($sync.SyncRoot)
    }
    foreach ($syncEntry in $syncEntries) {
        $checkBox = $syncEntry.Value
        if ($checkBox -is [System.Windows.Controls.CheckBox] -and -not $syncEntry.Key.StartsWith("WPFToggle") -and ($checkboxfilterpattern -eq "**" -or $syncEntry.Key -like $checkboxfilterpattern)) {
            # Atribuir a uma caixa o estado que ela já possui não é gratuito para as centenas de caixas que a
            # aba Instalar adiciona, portanto apenas as que diferem são tocadas
            $selected = $selectedSet.Contains($syncEntry.Key)
            if ($checkBox.IsChecked -ne $selected) {
                $checkBox.IsChecked = $selected
            }
        }
    }

    # Atualiza os valores da interface da aba Instalar. Eles são criados com a aba Instalar, e isso executa para
    # qualquer aba que seja criada primeiro: o modo offline começa em Ajustes, portanto eles ainda não existem.
    if ($sync.selectedAppsstackPanel) {
        $count = $sync.SelectedApps.Count
        $sync.WPFselectedAppsButton.Content = "Aplicativos selecionados: $count"
        # A cada alteração, remove todas as entradas dentro do Menu Popup. Isso é feito para manter a ordem alfabética mesmo que os elementos sejam selecionados de forma aleatória
        $sync.selectedAppsstackPanel.Children.Clear()
        $sync.selectedApps | Foreach-Object { Add-SelectedAppsMenuItem -name $($sync.configs.applicationsHashtable.$_.Content) -key $_ }
    }

    if($doToggles) {
        # Restaura os estados dos interruptores a partir da configuração importada.
        # Age apenas sobre os interruptores listados explicitamente na importação - os ausentes
        # no arquivo de exportação não faziam parte da configuração salva e devem manter qualquer
        # estado que o sistema ativo já tenha (definido durante a inicialização da interface via Get-WinUtilToggleStatus).
        $importedToggles = [System.Collections.Generic.HashSet[string]]::new([string[]]@($sync.selectedToggles), [StringComparer]::OrdinalIgnoreCase)
        [System.Threading.Monitor]::Enter($sync.SyncRoot)
        try {
            $toggleEntries = @($sync.GetEnumerator())
        } finally {
            [System.Threading.Monitor]::Exit($sync.SyncRoot)
        }
        foreach ($toggle in $toggleEntries) {
            if ($toggle.Key -like "WPFToggle*" -and $toggle.Value -is [System.Windows.Controls.CheckBox] -and $importedToggles.Contains($toggle.Key)) {
                $sync[$toggle.Key].IsChecked = $true
            }
            # Interruptores ausentes na importação são intencionalmente deixados intactos;
            # seu estado atual na interface já reflete o estado real do sistema.
        }
    }
}
