function Initialize-WinUtilTabContent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TabName,

        # Constrói em lotes, deixando a interface responder entre eles. Usado pelo aquecimento, que
        # ninguém está aguardando. Uma aba que o usuário acabou de clicar é construída de uma vez.
        [switch]$Yield
    )

    if ($null -eq $sync.InitializedTabs) {
        $sync.InitializedTabs = @{}
    }

    if ($sync.InitializedTabs[$TabName]) {
        return
    }

    # Reservado antes de construir, não depois: uma construção que cede a vez deixa um clique passar, e esse clique
    # começaria a construir a mesma aba uma segunda vez.
    $sync.InitializedTabs[$TabName] = $true

    try {
        switch ($TabName) {
            "Install" {
                Measure-WinUtilStep -Scope "UI" -Name "Aba Instalar: área de categorias" -ScriptBlock {
                    Initialize-WPFUI -targetGridName "appscategory"
                }
                Measure-WinUtilStep -Scope "UI" -Name "Aba Instalar: área de apps" -ScriptBlock {
                    Initialize-WPFUI -targetGridName "appspanel"
                }
                Initialize-WinUtilInstallTabControls
            }
            "Tweaks" {
                Invoke-WPFUIElements -configVariable $sync.configs.tweaks -targetGridName "tweakspanel" -columncount 2 -Yield:$Yield
            }
            "Config" {
                Invoke-WPFUIElements -configVariable $sync.configs.feature -targetGridName "featurespanel" -columncount 2 -Yield:$Yield
            }
            "AppX" {
                Invoke-WPFUIElements -configVariable $sync.configs.appx -targetGridName "appxpanel" -columncount 2 -Yield:$Yield
            }
            "Win11ISO" {
                if (Test-WinUtilUIAlive) {
                    $sync.Form.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, [action]{ Invoke-WinUtilISOCheckExistingWork }) | Out-Null
                }
            }
        }
        # Controles recém-construídos começam desmarcados, então o que já foi escolhido por uma importação ou
        # predefinição precisa ser aplicado a eles depois que existirem
        Reset-WPFCheckBoxes -doToggles $true
    } catch {
        # Uma aba construída pela metade deve poder ser reconstruída em vez de ficar vazia para sempre
        $sync.InitializedTabs[$TabName] = $false
        throw
    }
}
