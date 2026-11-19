function Step-WinUtilJob {
    <#
        .SYNOPSIS
            Avança um job para seu próximo ponto reportável, respeitando uma pausa ou parada no caminho

        .DESCRIPTION
            Todo laço chama isto, então é o único ponto por que uma execução passa com segurança entre etapas e
            portanto o único lugar onde pode ser retida ou encerrada sem interromper um comando em
            andamento. Ela bloqueia enquanto a execução está pausada e lança OperationCanceledException quando
            uma parada é solicitada, então chamá-la de um finally, ou de um catch que já relata
            uma falha, relança essa parada. A camada de job limpa as sinalizações antes de seu próprio
            relatório de conclusão, por esse motivo.

            Controla a barra de progresso e o item da barra de tarefas juntos e não faz nada sem janela,
            então os corpos de job não precisam de verificações de interface. A atualização é postada em vez de
            esperada: um job que reporta por item travaria na thread da interface a cada vez.

        .PARAMETER Status
            Texto para o rótulo de progresso

        .PARAMETER Percent
            Conclusão entre 0 e 100

        .PARAMETER State
            Estado da barra de tarefas. Normal enquanto trabalha, Error em falha, None ao concluir.

        .PARAMETER Overlay
            Ícone de sobreposição da barra de tarefas: logo, checkmark, warning ou None

        .PARAMETER Hide
            Limpa e oculta a barra de progresso. Usado ao deixar um job concluído para trás, em vez de
            durante a execução de um.
    #>
    param(
        [string]$Status,
        [int]$Percent = -1,
        [ValidateSet("Normal", "Error", "Paused", "Indeterminate", "None")]
        [string]$State,
        [string]$Overlay,
        [switch]$Hide
    )

    # Sem janela, toda atualização é descartada, e uma janela fechada sobre trabalho em execução conta
    # como nenhuma: seu dispatcher aceita postagens e as descarta. O console é o que resta.
    if (-not (Test-WinUtilUIAlive)) {
        if (-not $Hide) {
            Write-WinUtilConsoleProgress -Status $Status -Percent $Percent
        }
        return
    }

    Invoke-WPFUIThread -Async -Parameters @{
        Status = $Status
        Percent = [Math]::Min([Math]::Max($Percent, -1), 100)
        State = $State
        Overlay = $Overlay
        HideBar = [bool]$Hide
        HasStatus = $PSBoundParameters.ContainsKey('Status')
        HasState = $PSBoundParameters.ContainsKey('State')
        HasOverlay = $PSBoundParameters.ContainsKey('Overlay')
    } -ScriptBlock {
        param($Status, $Percent, $State, $Overlay, $HideBar, $HasStatus, $HasState, $HasOverlay)

        if ($HideBar) {
            $sync.WPFTweaksProgressBar.Visibility = [Windows.Visibility]::Collapsed
            $sync.WPFTweaksProgressLabel.Text = ""
            $sync.WPFTweaksProgressLabel.ToolTip = $null
            $sync.WPFTweaksProgressValue.Value = 0
            return
        }

        $hasPercent = $Percent -ge 0

        if ($HasStatus -or $hasPercent) {
            $sync.WPFTweaksProgressBar.Visibility = [Windows.Visibility]::Visible
        }
        if ($HasStatus) {
            $sync.WPFTweaksProgressLabel.Text = $Status
            $sync.WPFTweaksProgressLabel.ToolTip = $Status

            # As visualizações de trabalho das abas espelham o mesmo status abaixo do girador enquanto
            # exibidas. Com proteção: dispositivos de teste sem interface e outras abas não têm painel.
            foreach ($pair in @(
                @("WPFInstallWorkingPanel", "WPFInstallWorkingLabel"),
                @("WPFTweaksWorkingPanel", "WPFTweaksWorkingLabel")
            )) {
                $workingPanel = $sync[$pair[0]]
                $workingLabel = $sync[$pair[1]]
                if ($null -ne $workingPanel -and $null -ne $workingLabel -and "$($workingPanel.Visibility)" -eq "Visible") {
                    $workingLabel.Text = $Status
                }
            }
        }
        if ($hasPercent) {
            $sync.WPFTweaksProgressValue.Value = $Percent
            $sync.Form.TaskbarItemInfo.ProgressValue = $Percent / 100
        }
        if ($HasState) {
            # Pulsa no lugar no progresso já alcançado. IsIndeterminate faria o WPF
            # descartar Value e preencher a barra inteira, o que pareceria conclusão.
            $sync.WPFTweaksProgressValue.Tag = if ($State -eq "Indeterminate") { "Pulse" } else { $null }

            # Por referência de recurso em vez de um pincel fixo, para que a troca de tema o repinte
            $barColor = switch ($State) {
                "Error"  { "ProgressBarErrorColor" }
                "Paused" { "ProgressBarWarningColor" }
                default  { "ProgressBarForegroundColor" }
            }
            $sync.WPFTweaksProgressValue.SetResourceReference([Windows.Controls.Control]::ForegroundProperty, $barColor)

            Set-WinUtilTaskbaritem -state $State
        }
        if ($HasOverlay) {
            Set-WinUtilTaskbaritem -overlay $Overlay
        }
    }
}
