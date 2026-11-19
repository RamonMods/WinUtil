function Invoke-WPFButton {

    <#

    .SYNOPSIS
        Roteia o pressionamento de um botão, decidindo se é trabalho de interface ou um job

    .DESCRIPTION
        Este é o único lugar que classifica um botão. Tudo o que altera o sistema passa pelo
        Start-WinUtilJob, o que significa que recebe o sinalizador de ocupado, a barra de progresso,
        o item da barra de tarefas, o banner do console e as linhas de log sem que cada fluxo de
        trabalho precise organizar isso por conta própria. Tudo o que apenas altera o que a
        interface mostra é executado aqui e agora, porque enviar isso a um worker só o tornaria mais lento.

    .PARAMETER Button
        O nome do botão que foi clicado

    #>

    Param ([string]$Button)

    # Limpa o progresso deixado pelo job anterior, mas nunca enquanto um estiver em execução
    if (-not $sync.ActiveJob) {
        Step-WinUtilJob -Hide
    }

    # Botões controlados por switch que alteram o sistema. Tudo o que está no feature.json também conta. As
    # entradas WPFPanel* são a exceção apenas quando transferem para um applet do Windows, o que é
    # o que significa uma função ausente; as duas que possuem uma alteram o sistema elas mesmas e
    # caso contrário executariam suas esperas na thread de interface sem nada para reportá-las.
    #
    # Esta é uma lista de permissões de propósito: os elementos da janela e os alternadores de popup também chegam aqui, porque
    # todo Button em $sync é conectado a esta função, e eles não devem se tornar jobs.
    $workButtons = @(
        "WPFInstallUpgrade", "WPFAddUltPerf", "WPFRemoveUltPerf",
        "WPFUpdatesdefault", "WPFUpdatesdisable", "WPFUpdatessecurity",
        "WPFGetInstalledAppx"
    )

    $featureEntry = $sync.configs.feature.$Button
    # A instalação de recursos cuida da própria validação da seleção e a captura antes de
    # iniciar um job. Englobá-la aqui transformaria seu retorno de "nada selecionado" em sucesso do job.
    $isConfigWork = $featureEntry -and $Button -ne "WPFFeatureInstall" -and
        ($Button -notlike "WPFPanel*" -or $featureEntry.function)

    if ($isConfigWork -or $workButtons -contains $Button) {
        $updatesDisableConfirmed = $false
        if ($Button -eq "WPFUpdatesdisable") {
            $updatesDisableConfirmed = Confirm-WPFUpdatesdisable
            if (-not $updatesDisableConfirmed) {
                return
            }
        }

        $jobParameters = @{
            Button = $Button
            UpdatesDisableConfirmed = $updatesDisableConfirmed
        }
        if ($Button -eq "WPFInstallUpgrade") {
            $jobParameters.ManagerPreference = $sync.preferences.packagemanager
        }
        Start-WinUtilJob -Name (Get-WinUtilButtonLabel -Button $Button) -QueueIfBusy -Parameters $jobParameters -ScriptBlock {
            param($Button, $UpdatesDisableConfirmed, $ManagerPreference)

            Invoke-WPFButtonAction -Button $Button -UpdatesDisableConfirmed:$UpdatesDisableConfirmed -ManagerPreference $ManagerPreference
        }
        return
    }

    # Um manipulador que lança uma exceção na thread de interface chegaria ao usuário como uma mensagem
    # simples, sem indicar qual controle a produziu
    try {
        Invoke-WPFButtonAction -Button $Button
    } catch {
        Write-WinUtilErrorRecord -ErrorRecord $_ -Component "UI" -Context "Botão '$Button'"
    }
}

function Get-WinUtilButtonLabel {
    <#
    .SYNOPSIS
        Retorna o nome sob o qual o job de um botão deve ser reportado.

    .DESCRIPTION
        O que o botão diz é o que a barra de progresso, o banner e o log dizem, para que a
        redação nunca se afaste da interface e não haja uma segunda lista para manter. Usa
        o nome do botão como fallback quando não há nada para ler.
    #>
    param([string]$Button)

    $content = $sync.configs.feature.$Button.Content
    if (-not [string]::IsNullOrWhiteSpace($content)) {
        return $content
    }

    $control = $sync.$Button
    if ($control -and $control.Content) {
        $text = if ($control.Content -is [string]) { $control.Content } else { $control.Content.Text }
        if (-not [string]::IsNullOrWhiteSpace($text)) {
            return ([string]$text).Trim()
        }
    }

    $fallback = ($Button -replace '^WPF', '')
    if ([string]::IsNullOrWhiteSpace($fallback)) {
        return "WinUtil"
    }
    return $fallback
}

function Invoke-WPFButtonAction {

    <#

    .SYNOPSIS
        Invoca a função associada ao botão clicado

    .DESCRIPTION
        O trabalho em si. Chamado por Invoke-WPFButton, diretamente ou de dentro de um job, portanto
        não deve se preocupar com progresso, estado de ocupado ou banners.

    .PARAMETER Button
        O nome do botão que foi clicado

    #>

    Param (
        [string]$Button,
        [switch]$UpdatesDisableConfirmed,
        [string]$ManagerPreference = $sync.preferences.packagemanager
    )

    # Verifica se o botão está definido na configuração de recursos com function ou InvokeScript
    if ($sync.configs.feature.$Button) {
        $buttonConfig = $sync.configs.feature.$Button

        # Se o botão tiver uma function definida, chama-a
        if ($buttonConfig.function) {
            $functionName = $buttonConfig.function
            if (Get-Command $functionName -ErrorAction SilentlyContinue) {
                & $functionName
                return
            }
        }

        # Se o botão tiver InvokeScript definido, executa os scripts
        if ($buttonConfig.InvokeScript -and $buttonConfig.InvokeScript.Count -gt 0) {
            foreach ($script in $buttonConfig.InvokeScript) {
                if (-not [string]::IsNullOrWhiteSpace($script)) {
                    Invoke-Command -ScriptBlock ([scriptblock]::Create($script)) -ErrorAction Stop
                }
            }
            return
        }
    }

    # Usa como fallback o switch codificado para botões que não estão no feature.json
    Switch -Wildcard ($Button) {
        "WPFTab?BT" {Invoke-WPFTab $Button}
        "WPFInstall" {Invoke-WPFInstall}
        "WPFUninstall" {Invoke-WPFUnInstall}
        "WPFInstallUpgrade" {Invoke-WPFInstallUpgrade -ManagerPreference $ManagerPreference}
        "WPFCollapseAllCategories" {Invoke-WPFToggleAllCategories -Action "Collapse"}
        "WPFExpandAllCategories" {Invoke-WPFToggleAllCategories -Action "Expand"}
        "WPFStandard" {Invoke-WPFPresets "Standard" -checkboxfilterpattern "WPFTweak*"}
        "WPFMinimal" {Invoke-WPFPresets "Minimal" -checkboxfilterpattern "WPFTweak*"}
        "WPFAdvanced" {Invoke-WPFPresets "Advanced" -checkboxfilterpattern "WPFTweak*"}
        "WPFClearTweaksSelection" {Invoke-WPFPresets -imported $true -checkboxfilterpattern "WPFTweak*"}
        "WPFClearInstallSelection" {Invoke-WPFPresets -imported $true -checkboxfilterpattern "WPFInstall*"}
        "WPFtweaksbutton" {Invoke-WPFtweaksbutton}
        "WPFOOSUbutton" {Invoke-WPFOOSU}
        "WPFAddUltPerf" {Invoke-WPFUltimatePerformance -Enable}
        "WPFRemoveUltPerf" {Invoke-WPFUltimatePerformance}
        "WPFundoall" {Invoke-WPFundoall}
        "WPFUpdatesdefault" {Invoke-WPFUpdatesdefault}
        "WPFUpdatesdisable" {Invoke-WPFUpdatesdisable -Confirmed:$UpdatesDisableConfirmed}
        "WPFUpdatessecurity" {Invoke-WPFUpdatessecurity}
        "WPFGetInstalled" {Invoke-WPFGetInstalled -CheckBox "winget"}
        "WPFGetInstalledTweaks" {Invoke-WPFGetInstalled -CheckBox "tweaks"}
        "WPFAppxRemoval" {Invoke-WPFTab "WPFTab6BT"}
        "WPFBackToTweaks" {Invoke-WPFTab "WPFTab2BT"}
        "WPFInstallSelectedAppx" {Invoke-WPFAppxInstall}
        "WPFRemoveSelectedAppx" {Invoke-WPFAppxRemoval}
        "WPFDefaultAppxSelection" {Invoke-WPFPresets "AppxDefault" -checkboxfilterpattern "WPFAppx*"}
        "WPFSelectAllAppx" {
            $sync.configs.appxHashtable.Keys | ForEach-Object {$sync.$_.IsChecked = $true}
        }
        "WPFClearAppxSelection" {
            $sync.configs.appxHashtable.Keys | ForEach-Object {$sync.$_.IsChecked = $false}
        }
        "WPFGetInstalledAppx" {
            $installedAppxPackages = Get-WinUtilInstalledAPPX
            Invoke-WPFUIThread -Parameters @{ Installed = $installedAppxPackages } -ScriptBlock {
                param($Installed)
                foreach ($appx in $sync.configs.appxHashtable.GetEnumerator()) {
                    if ($appx.Value.PackageId -in $Installed) {
                        $sync.$($appx.Key).IsChecked = $true
                    }
                }
            }
        }
        # O fechamento pode ser recusado, ou deixar um job em execução que sobrevive à janela, então a
        # despedida fica no ponto em que o processo realmente termina, e não aqui
        "WPFCloseButton" {$sync.Form.Close()}
        "WPFMinimizeButton" {[Windows.SystemCommands]::MinimizeWindow($sync.Form)}
        "WPFMaximizeButton" {
            if ($sync.Form.WindowState -eq [Windows.WindowState]::Normal) {
                [Windows.SystemCommands]::MaximizeWindow($sync.Form)
            } else {
                [Windows.SystemCommands]::RestoreWindow($sync.Form)
            }
        }
        "WPFselectedAppsButton" {$sync.selectedAppsPopup.IsOpen = -not $sync.selectedAppsPopup.IsOpen}
    }
}
