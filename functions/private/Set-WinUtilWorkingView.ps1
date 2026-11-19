function Set-WinUtilWorkingView {
    <#
        .SYNOPSIS
            Mostra ou oculta a visão de trabalho de uma aba (spinner + status ao vivo)

        .DESCRIPTION
            Enquanto uma execução longa está em andamento, o conteúdo da aba é substituído
            pela seta giratória centralizada e pelo status atual abaixo dela, espelhando
            a página de trabalho do Criar Win11. A barra de progresso inferior continua
            reportando como antes.

            As áreas mapeiam nomes de job para abas: Install cobre Install/Uninstall/
            Upgrade, Tweaks cobre Tweaks/Undo. Adicionar uma nova área é um novo
            painel XAML mais uma entrada no mapa abaixo.

            Não faz nada sem uma janela, então o corpo dos jobs fica livre de verificações de UI.
    #>
    param(
        [Parameter(Mandatory)]
        [ValidateSet("Install", "Tweaks")]
        [string]$Area,

        [Parameter(Mandatory)]
        [bool]$Working,

        [string]$Label
    )

    Invoke-WPFUIThread -Parameters @{ Area = $Area; Working = $Working; Label = $Label } -ScriptBlock {
        param($Area, $Working, $Label)

        # Resolvido aqui em vez de pelo chamador: o bloco é reconstruído a partir do seu
        # texto na thread da interface, então apenas valores simples viajam de forma confiável.
        if ([string]::IsNullOrEmpty($Area)) { return }
        $controls = @{
            Install = @{
                Panel   = "WPFInstallWorkingPanel"
                Content = @("WPFInstallContentGrid", "WPFSearchChips")
                Label   = "WPFInstallWorkingLabel"
            }
            Tweaks  = @{
                Panel   = "WPFTweaksWorkingPanel"
                Content = @("WPFTweaksContentScroll", "WPFTweaksActionBar")
                Label   = "WPFTweaksWorkingLabel"
            }
        }[$Area]
        if ($null -eq $controls) { return }

        $panel = $sync[$controls.Panel]
        if ($null -eq $panel) { return }

        if ($Working) {
            $labelControl = $sync[$controls.Label]
            if ($Label -and $null -ne $labelControl) { $labelControl.Text = $Label }

            foreach ($name in $controls.Content) {
                $content = $sync[$name]
                if ($null -ne $content) { $content.Visibility = "Collapsed" }
            }

            $panel.Visibility = "Visible"
        } else {
            $panel.Visibility = "Collapsed"

            foreach ($name in $controls.Content) {
                $content = $sync[$name]
                if ($null -ne $content) { $content.Visibility = "Visible" }
            }
        }
    }
}
