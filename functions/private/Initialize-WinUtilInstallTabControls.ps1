function Initialize-WinUtilInstallTabControls {
    <#
        .SYNOPSIS
            Conecta os controles da aba Instalar que são gerados a partir da configuração em vez de
            declarados no XAML

        .DESCRIPTION
            Os botões de rádio do gerenciador de pacotes e os botões de ação de instalação são criados por
            Invoke-WPFUIElements, então eles não existem até a aba Instalar ser construída. Configurá-los
            em qualquer lugar que não seja imediatamente após essa construção faz o código depender de
            quando a aba é criada.
    #>

    if ($sync.ChocoRadioButton) {
        $sync.ChocoRadioButton.Add_Checked({
            $sync.preferences.packagemanager = "Choco"
        })
    }
    if ($sync.WingetRadioButton) {
        $sync.WingetRadioButton.Add_Checked({
            $sync.preferences.packagemanager = "Winget"
        })
    }

    switch ($sync.preferences.packagemanager) {
        "Choco" { if ($sync.ChocoRadioButton) { $sync.ChocoRadioButton.IsChecked = $true }; break }
        "Winget" { if ($sync.WingetRadioButton) { $sync.WingetRadioButton.IsChecked = $true }; break }
    }

    if ($PARAM_OFFLINE) {
        foreach ($name in "WPFInstall", "WPFUninstall", "WPFInstallUpgrade", "WPFGetInstalled") {
            if ($sync.$name) { $sync.$name.IsEnabled = $false }
        }
    }
}
