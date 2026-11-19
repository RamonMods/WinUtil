function Start-WinUtilUserInterface {
    <#
        .SYNOPSIS
            Monta a janela do WinUtil, conecta seus manipuladores de evento e a executa até o fim

        .DESCRIPTION
            Esta é a interface inteira. Ela roda no runspace STA dedicado à interface que o
            main.ps1 inicia, então a thread que é dona da janela não faz nada além de desenhar e
            distribuir: toda operação longa vai para o pool de workers através de Start-WinUtilJob.

            A chamada bloqueia até a janela ser fechada, e o runspace da interface é o único
            lugar autorizado a tocar os controles diretamente.
    #>

    $buildClock = [System.Diagnostics.Stopwatch]::StartNew()

    Measure-WinUtilStep -Scope "UI" -Name "carregar assemblies do WPF" -ScriptBlock {
        [void][System.Reflection.Assembly]::LoadWithPartialName('presentationframework')
    }

    [xml]$XAML = $inputXML

    # Lê o arquivo XAML
    $readerOperationSuccessful = $false # Há mais casos de falha do que de sucesso.
    $readerFailure = $null
    $reader = (New-Object System.Xml.XmlNodeReader $xaml)
    try {
        Measure-WinUtilStep -Scope "UI" -Name "analisar XAML" -ScriptBlock {
            $sync["Form"] = [Windows.Markup.XamlReader]::Load( $reader )
        }
        $readerOperationSuccessful = $true
    } catch [System.Management.Automation.MethodInvocationException] {
        $readerFailure = $_
        Write-Host "Encontramos um problema com o código XAML.  Verifique a sintaxe deste controle..." -ForegroundColor Red
        Write-Host $error[0].Exception.Message -ForegroundColor Red

        If ($error[0].Exception.Message -like "*button*") {
            write-Host "Garanta que seu &lt;button no `$inputXML NÃO tenha uma propriedade Click=ButtonClick.  O PS não consegue lidar com isso`n`n`n`n" -ForegroundColor Red
        }
    } catch {
        $readerFailure = $_
        Write-Host "Não foi possível carregar Windows.Markup.XamlReader. Verifique a sintaxe e confirme que o .NET está instalado." -ForegroundColor Red
    }

    if (-NOT ($readerOperationSuccessful)) {
        Write-Host "Falha ao analisar o conteúdo XAML usando o método Load de Windows.Markup.XamlReader." -ForegroundColor Red
        Write-Host "Saindo do WinUtil..." -ForegroundColor Red
        Write-WinUtilLog -Level "ERROR" -Component "UI" -Message "Falha ao analisar o conteúdo XAML. O WinUtil não pode iniciar."
        throw [System.InvalidOperationException]::new("Falha ao analisar o conteúdo XAML. O WinUtil não pode iniciar.", $readerFailure.Exception)
    }

    # Configura a janela para acompanhar eventos de mudança de tema do Windows e atualizar o tema do winutil
    # lógica de limite necessária, porque o Windows parece enviar mais de um evento de mudança de tema por alteração
    $themeState = @{ LastChange = [datetime]::MinValue }
    $debounceInterval = [timespan]::FromSeconds(2)
    $sync.Form.Add_Loaded({
        $interopHelper = New-Object System.Windows.Interop.WindowInteropHelper $sync.Form
        $hwndSource = [System.Windows.Interop.HwndSource]::FromHwnd($interopHelper.Handle)
        $hwndSource.AddHook({
            param (
                [System.IntPtr]$hwnd,
                [int]$msg,
                [System.IntPtr]$wParam,
                [System.IntPtr]$lParam,
                [ref]$handled
            )
            $null = $hwnd, $wParam, $lParam
            if ($msg -eq 0x001A) { Request-WinUtilWindowInsets }
            # Verifica o evento WM_SETTINGCHANGE (0x1001A) e confirma que o botão mostra o ícone de "Auto" => [char]0xF08C
            if (($msg -eq 0x001A) -and $sync.ThemeButton.Content -eq [char]0xF08C) {
                $currentTime = [datetime]::Now
                if ($currentTime - $themeState.LastChange -gt $debounceInterval) {
                    Invoke-WinutilThemeChange -theme "Auto"
                    $themeState.LastChange = $currentTime
                    # [ref] é parâmetro de saída: atribuir a $handled apenas substituiria a
                    $handled.Value = $true
                }
            }
            return 0
        })
    })

    Measure-WinUtilStep -Scope "UI" -Name "aplicar tema" -ScriptBlock {
        Invoke-WinutilThemeChange -theme $sync.preferences.theme
    }

    # O conteúdo da aba é construído quando ela é ativada: a aba padrão logo antes de a janela ser
    # exibida, as demais quando são abertas ou aquecidas.
    $sync.InitializedTabs = @{}

    #===========================================================================
    # Armazena os objetos do formulário no PowerShell
    #===========================================================================

    Measure-WinUtilStep -Scope "UI" -Name "mapear controles nomeados" -ScriptBlock {
        $xaml.SelectNodes("//*[@Name]") | ForEach-Object {$sync["$("$($psitem.Name)")"] = $sync["Form"].FindName($psitem.Name)}
    }

    $sync.WindowInsetsPending = $false
    $sync.WindowInsetsUpdate = [action]{
        $sync.WindowInsetsPending = $false
        if (Test-WinUtilUIAlive) { Update-WinUtilWindowInsets }
    }
    $sync.Form.Add_Loaded({ Request-WinUtilWindowInsets })
    $sync.Form.Add_StateChanged({ Request-WinUtilWindowInsets })
    $sync.Form.Add_SizeChanged({ Request-WinUtilWindowInsets })
    $sync.Form.Add_LocationChanged({ Request-WinUtilWindowInsets })
    $sync.Form.Add_DpiChanged({ Request-WinUtilWindowInsets })

    # Construído aqui para carregar o estado de sessão deste runspace: o trabalho postado roda então como
    # código comum da interface, e não como um pipeline aninhado entre runspaces, muito mais lento. Invoke-WPFUIThread é a
    # parte voltada ao chamador.
    $sync.UIDispatchDelegate = [System.Func[object, object]]{
        param($Work)

        try {
            $body = [scriptblock]::Create($Work.Body)
            $parameters = $Work.Parameters
            if ($parameters -and $parameters.Count -gt 0) {
                & $body @parameters
            } else {
                & $body
            }
        } catch {
            if ($Work.PropagateErrors) {
                throw
            }
            # Trabalho disparar-e-esquecer não tem chamador aguardando para relatar sua falha.
            Write-WinUtilErrorRecord -ErrorRecord $_ -Component "UI" -Context "Trabalho da interface"
        }
    }

    Measure-WinUtilStep -Scope "UI" -Name "conectar cliques estáticos de botões" -ScriptBlock {
        # CheckBox e RadioButton também derivam de ButtonBase, então o nome exato do tipo é o que
        # decide, e não -is
        $clickableTypes = [System.Collections.Generic.HashSet[string]]::new([string[]]@("Button", "ToggleButton"), [StringComparer]::OrdinalIgnoreCase)
        $alreadyWired = [System.Collections.Generic.HashSet[string]]::new([string[]]@($sync.Buttons), [StringComparer]::OrdinalIgnoreCase)

        $clickHandler = {
            [System.Object]$Sender = $args[0]
            Invoke-WPFButton $Sender.name
        }

        foreach ($entry in @($sync.GetEnumerator())) {
            $control = $entry.Value
            if ($null -eq $control -or -not $clickableTypes.Contains($control.GetType().Name)) {
                continue
            }
            if (-not $alreadyWired.Add([string]$entry.Key)) {
                continue
            }

            $control.Add_Click($clickHandler)
            $sync.Buttons.Add($entry.Key) | Out-Null
        }
    }

    #===========================================================================
    # Configura e exibe o formulário
    #===========================================================================

    # Barra de progresso no taskbaritem > Set-WinUtilProgressbar
    $sync["Form"].TaskbarItemInfo = New-Object System.Windows.Shell.TaskbarItemInfo
    Set-WinUtilTaskbaritem -state "None"

    # Conectado antes de a janela ser exibida, para que o trabalho enfileirado na inicialização já saiba abrir
    # espaço para qualquer ação do usuário
    Register-WinUtilInputWatch

    # Define a barra de título
    $sync["Form"].title = $sync["Form"].title + " " + $sync.version
    # Define os comandos que serão executados quando o formulário for fechado
    $sync["Form"].Add_Closing({
        param($eventSender, $closingArgs)
        $null = $eventSender

        # O pool não pode ser desmontado enquanto ainda há trabalho rodando: o erro de runspace que
        # se segue não é tratado e encerra o processo
        if (($sync.ActiveJob -or $sync.JobQueue.Count -gt 0) -and -not $sync.ForceClose) {
            $closingArgs.Cancel = $true
            $runningJob = if ($sync.ActiveJob) { $sync.ActiveJob } else { "Operações na fila" }
            Invoke-WinUtilCloseRequest -RunningJob $runningJob -QueuedCount $sync.JobQueue.Count
            return
        }

        # Após o aviso, a janela está fechando definitivamente, e nada enfileirado pode iniciar depois
        $null = Clear-WinUtilJobQueue

        # Trabalho que deve sobreviver à janela precisa do pool em que está rodando. main.ps1
        # espera por ele e desliga o pool quando terminar.
        if ($sync.FinishInConsole) {
            Write-WinUtilLog -Component "UI" -Message "Janela fechando, deixando $($sync.ActiveJob) terminar no console."
            return
        }

        # main.ps1 cuida do desligamento do pool após o fechamento da janela. Fazer isso deste
        # retorno do dispatcher pode causar deadlock com um worker em seu bloco de limpeza da thread da interface.
        Write-WinUtilLog -Component "UI" -Message "Janela fechando; a thread principal desligará o pool de workers."
    })

    # Anexa o manipulador de evento ao evento Click
    $sync.SearchBarClearButton.Add_Click({
        $sync.SearchBar.Text = ""
        $sync.SearchBarClearButton.Visibility = "Collapsed"

        # Foca a barra de busca após limpar o texto
        $sync.SearchBar.Focus()
        $sync.SearchBar.SelectAll()
    })

    # adiciona alguns atalhos para quem não gosta de clicar
    function Invoke-WinUtilFontScaleStep([double]$Step) { $sync.FontScalingSlider.Value = [math]::Max(0.75, [math]::Min(2.0, $sync.FontScalingSlider.Value + $Step)); Invoke-WinUtilFontScaling -ScaleFactor $sync.FontScalingSlider.Value }

    $commonKeyEvents = {
        if ($sync.ActiveJob) {
            return
        }

        # Trata teclas pressionadas individualmente
        switch ($_.Key) {
            "Escape" { $sync.SearchBar.Text = "" }
        }
        # Trata combinações com Alt para navegação
        if ($_.KeyboardDevice.Modifiers -eq "Alt") {
            $keyEventArgs = $_
            switch ($_.SystemKey) {
                "I" { Invoke-WPFButton "WPFTab1BT"; $keyEventArgs.Handled = $true } # Navega para a aba Instalar e suprime o som de aviso do Windows
                "T" { Invoke-WPFButton "WPFTab2BT"; $keyEventArgs.Handled = $true } # Navega para a aba Ajustes
                "C" { Invoke-WPFButton "WPFTab3BT"; $keyEventArgs.Handled = $true } # Navega para a aba Configurações
                "U" { Invoke-WPFButton "WPFTab4BT"; $keyEventArgs.Handled = $true } # Navega para a aba Atualizações
                "W" { Invoke-WPFButton "WPFTab5BT"; $keyEventArgs.Handled = $true } # Navega para a aba Win11ISO
            }
        }
        # Trata combinações com Ctrl para ações específicas
        if ($_.KeyboardDevice.Modifiers -eq "Ctrl") {
            $keyEventArgs = $_
            switch ($_.Key) {
                "F" { $sync.SearchBar.Focus() } # Foca a barra de busca
                "Q" { $this.Close() } # Fecha o aplicativo
            }
        }
        $ctrlShiftModifiers = [Windows.Input.ModifierKeys]::Control -bor [Windows.Input.ModifierKeys]::Shift
        if ($_.KeyboardDevice.Modifiers -eq "Ctrl" -or $_.KeyboardDevice.Modifiers -eq $ctrlShiftModifiers) {
            $keyEventArgs = $_
            switch ($_.Key) {
                { $_ -in "OemPlus", "Add" } { Invoke-WinUtilFontScaleStep 0.05; $keyEventArgs.Handled = $true }
                { $_ -in "OemMinus", "Subtract" } { Invoke-WinUtilFontScaleStep -0.05; $keyEventArgs.Handled = $true }
            }
        }
    }
    $sync["Form"].Add_PreViewKeyDown($commonKeyEvents)
    $sync["Form"].Add_PreviewMouseWheel({
        if ([Windows.Input.Keyboard]::Modifiers -eq "Ctrl") { Invoke-WinUtilFontScaleStep $(if ($_.Delta -gt 0) { 0.05 } else { -0.05 }); $_.Handled = $true }
    })

    $sync["Form"].Add_MouseLeftButtonDown({
        Invoke-WPFPopup -Action "Hide" -Popups @("Settings", "Theme", "FontScaling")
        $sync["Form"].DragMove()
    })

    $sync["Form"].Add_MouseDoubleClick({
        if ($_.OriginalSource.Name -eq "NavDockPanel" -or
            $_.OriginalSource.Name -eq "GridBesideNavDockPanel") {
                if ($sync["Form"].WindowState -eq [Windows.WindowState]::Normal) {
                    [Windows.SystemCommands]::MaximizeWindow($sync.Form)
                }
                else{
                    [Windows.SystemCommands]::RestoreWindow($sync.Form)
                }
        }
    })

    $sync["Form"].Add_Deactivated({
        Invoke-WPFPopup -Action "Hide" -Popups @("Settings", "Theme", "FontScaling")
    })

    $sync["Form"].Add_ContentRendered({
        # Carrega o assembly do Windows Forms
        Add-Type -AssemblyName System.Windows.Forms
        $primaryScreen = [System.Windows.Forms.Screen]::PrimaryScreen
        # Verifica se o monitor principal foi encontrado
        if ($primaryScreen) {
            # Extrai a largura e a altura da tela do monitor principal
            $screenWidth = $primaryScreen.Bounds.Width
            $screenHeight = $primaryScreen.Bounds.Height
            $sync.Form.MinWidth = [Math]::Min([double]$sync.Form.MinWidth, [double]$screenWidth)

            # Compara com o tamanho do monitor principal
            if ($sync.Form.ActualWidth -gt $screenWidth -or $sync.Form.ActualHeight -gt $screenHeight) {
                $sync.Form.Left = 0
                $sync.Form.Top = 0
                $sync.Form.Width = $screenWidth
                $sync.Form.Height = $screenHeight
            }
        }

        if ($PARAM_OFFLINE) {
            # Exibe o banner de offline
            $sync.WPFOfflineBanner.Visibility = [System.Windows.Visibility]::Visible

            # Desabilita a aba Instalar
            $sync.WPFTab1BT.IsEnabled = $false
            $sync.WPFTab1BT.Opacity = 0.5
            $sync.WPFTab1BT.ToolTip = "É necessária conexão com a internet para instalar aplicativos."

            # Os botões de ação de instalação são gerados com a aba Instalar, então
            # Initialize-WinUtilInstallTabControls os desabilita quando essa aba é construída

            # Exibe o indicador de offline
            Write-Host "Modo offline detectado - aba Instalar desabilitada." -ForegroundColor Yellow

            # Opcionalmente muda para outra aba se a aba Instalar fosse a padrão
            Invoke-WPFTab "WPFTab2BT" -Yield  # Muda para a aba Ajustes
        }
        else {
            # Online - garante que a aba Instalar esteja habilitada
            $sync.WPFTab1BT.IsEnabled = $true
            $sync.WPFTab1BT.Opacity = 1.0
            $sync.WPFTab1BT.ToolTip = $null
            Invoke-WPFTab "WPFTab1BT" -Yield  # Usa a aba Instalar como padrão
        }

        $sync["Form"].Focus()
        $sync["Form"].Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, [action]{ Initialize-WinUtilRunspacePool | Out-Null }) | Out-Null
        $sync["Form"].Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, [action]{
            Set-WinUtilTaskbaritem -overlay "logo"
        }) | Out-Null
        $sync["Form"].Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, [action]{ Start-WinUtilTabWarmup }) | Out-Null
    })

    # O SearchBarTimer serve para atrasar a busca até que o usuário pare de digitar por um curto período
    # Isso evita que a interface engasgue quando o usuário digita rápido, pois não é preciso atualizá-la a cada tecla

    $searchBarTimer = New-Object System.Windows.Threading.DispatcherTimer
    $searchBarTimer.Interval = [TimeSpan]::FromMilliseconds(300)
    $searchBarTimer.IsEnabled = $false

    $searchBarTimer.add_Tick({
        $searchBarTimer.Stop()
        switch ($sync.currentTab) {
            "Install" {
                Find-AppsByNameOrDescription -SearchString $sync.SearchBar.Text -Categories $sync.SelectedAppCategories.ToArray()
            }
            "Tweaks" {
                Find-TweaksByNameOrDescription -SearchString $sync.SearchBar.Text
            }
            "AppX" {
                Find-TweaksByNameOrDescription -SearchString $sync.SearchBar.Text
            }
        }
    })
    $sync["SearchBar"].Add_TextChanged({
        if ($sync.SearchBar.Text -ne "") {
            $sync.SearchBarClearButton.Visibility = "Visible"
            $sync.SearchBarIcon.Visibility = "Collapsed"
        } else {
            $sync.SearchBarClearButton.Visibility = "Collapsed"
            $sync.SearchBarIcon.Visibility = "Visible"
        }

        if ($searchBarTimer.IsEnabled) {
            $searchBarTimer.Stop()
        }
        $searchBarTimer.Start()
    })

    # Filtros de categoria em chips. Cada chip leva sua categoria em Tag, então um manipulador cobre todos.
    $sync.AppCategoryChips = @(
        @{ Name = "WPFSearchChipAll";             Category = "" }
        @{ Name = "WPFSearchChipBrowsers";        Category = "Navegadores" }
        @{ Name = "WPFSearchChipCommunications";  Category = "Comunicação" }
        @{ Name = "WPFSearchChipDevelopment";     Category = "Desenvolvimento" }
        @{ Name = "WPFSearchChipDocument";        Category = "Documentos" }
        @{ Name = "WPFSearchChipGames";           Category = "Jogos" }
        @{ Name = "WPFSearchChipMicrosoftTools";  Category = "Ferramentas da Microsoft" }
        @{ Name = "WPFSearchChipMultimediaTools"; Category = "Multimídia" }
        @{ Name = "WPFSearchChipProTools";        Category = "Ferramentas Profissionais" }
        @{ Name = "WPFSearchChipSelfhostedTools"; Category = "Ferramentas Auto-hospedadas" }
        @{ Name = "WPFSearchChipUtilities";       Category = "Utilitários" }
    )
    $sync.SelectedAppCategories = [System.Collections.Generic.List[string]]::new()

    foreach ($appCategoryChip in $sync.AppCategoryChips) {
        $sync[$appCategoryChip.Name].Tag = $appCategoryChip.Category
        $sync[$appCategoryChip.Name].Add_Click({ Invoke-WinUtilAppCategoryChip -Chip $this })
    }

    $sync["Form"].Add_Loaded({
        param($e)
        $null = $e
        $sync.Form.MinWidth = "1150"
        $sync["Form"].MaxWidth = [Double]::PositiveInfinity
        $sync["Form"].MaxHeight = [Double]::PositiveInfinity
    })

    Measure-WinUtilStep -Scope "UI" -Name "construir logotipo de navegação" -ScriptBlock {
        $NavLogoPanel = $sync["Form"].FindName("NavLogoPanel")
        $NavLogoPanel.Children.Add((Invoke-WinUtilAssets -Type "logo" -Size 25)) | Out-Null
    }

    $sync["Form"].Add_Activated({
        Set-WinUtilTaskbaritem -overlay "logo"
    })

    $sync["ThemeButton"].Add_Click({
        Invoke-WPFPopup -PopupActionTable @{ "Settings" = "Hide"; "Theme" = "Toggle"; "FontScaling" = "Hide" }
    })
    $sync["AutoThemeMenuItem"].Add_Click({
        Invoke-WPFPopup -Action "Hide" -Popups @("Theme")
        Invoke-WinutilThemeChange -theme "Auto"
    })
    $sync["DarkThemeMenuItem"].Add_Click({
        Invoke-WPFPopup -Action "Hide" -Popups @("Theme")
        Invoke-WinutilThemeChange -theme "Dark"
    })
    $sync["LightThemeMenuItem"].Add_Click({
        Invoke-WPFPopup -Action "Hide" -Popups @("Theme")
        Invoke-WinutilThemeChange -theme "Light"
    })

    # Um popup que fecha com cliques fora também fecha no clique que o alternaria, o que
    # o reabriria em seguida, então um clique logo após o fechamento é esse mesmo clique
    $sync.JobQueuePopupClosedAt = [DateTime]::MinValue
    $sync["JobQueuePopup"].Add_Closed({ $sync.JobQueuePopupClosedAt = [DateTime]::UtcNow })
    $sync["JobQueuePopup"].Add_Opened({ Update-WinUtilJobQueueUI })
    $sync["JobQueueButton"].Add_Click({
        if (([DateTime]::UtcNow - $sync.JobQueuePopupClosedAt).TotalMilliseconds -lt 300) { return }
        Invoke-WPFPopup -PopupActionTable @{ "Settings" = "Hide"; "Theme" = "Hide"; "FontScaling" = "Hide"; "JobQueue" = "Show" }
    })

    $sync["SettingsButton"].Add_Click({
        Invoke-WPFPopup -PopupActionTable @{ "Settings" = "Toggle"; "Theme" = "Hide"; "FontScaling" = "Hide" }
    })
    $sync["ImportMenuItem"].Add_Click({
        Invoke-WPFPopup -Action "Hide" -Popups @("Settings")
        Invoke-WPFImpex -type "import"
    })
    $sync["ExportMenuItem"].Add_Click({
        Invoke-WPFPopup -Action "Hide" -Popups @("Settings")
        Invoke-WPFImpex -type "export"
    })
    $sync["ExportEnvironmentReportMenuItem"].Add_Click({
        Invoke-WPFPopup -Action "Hide" -Popups @("Settings")
        Invoke-WPFExportEnvironmentReport
    })
    $sync["AboutMenuItem"].Add_Click({
        Invoke-WPFPopup -Action "Hide" -Popups @("Settings")

        $authorInfo = @"
Autor    : <a href="https://github.com/RamonMods">@RamonMods</a>
UI       : <a href="https://github.com/MyDrift-user">@MyDrift-user</a>, <a href="https://github.com/Marterich">@Marterich</a>
Runspace : <a href="https://github.com/DeveloperDurp">@DeveloperDurp</a>, <a href="https://github.com/Marterich">@Marterich</a>
GitHub   : <a href="https://github.com/RamonMods/WinUtil">RamonMods/winutil</a>
Versão   : <a href="https://github.com/RamonMods/WinUtil/releases/tag/$($sync.version)">$($sync.version)</a>
"@
        Show-CustomDialog -Title "Sobre" -Message $authorInfo
    })
    $sync["DocumentationMenuItem"].Add_Click({
        Invoke-WPFPopup -Action "Hide" -Popups @("Settings")
        Start-Process "https://github.com/RamonMods/WinUtil/"
    })
    $sync["SponsorMenuItem"].Add_Click({
        Invoke-WPFPopup -Action "Hide" -Popups @("Settings")

        $authorInfo = @"
<a href="https://github.com/sponsors/RamonMods">Patrocinadores atuais do RamonMods:</a>
"@
        $authorInfo += "`n"
        try {
            $sponsors = Invoke-WinUtilSponsors
            foreach ($sponsor in $sponsors) {
                $authorInfo += "<a href=`"https://github.com/sponsors/RamonMods`">$sponsor</a>`n"
            }
        } catch {
            $authorInfo += "Ocorreu um erro ao buscar ou processar os patrocinadores: $_`n"
        }
        Show-CustomDialog -Title "Patrocinadores" -Message $authorInfo -EnableScroll $true
    })

    # Manipuladores de eventos de escala de fonte
    $sync["FontScalingButton"].Add_Click({
        Invoke-WPFPopup -PopupActionTable @{ "Settings" = "Hide"; "Theme" = "Hide"; "FontScaling" = "Toggle" }
    })

    $sync["FontScalingSlider"].Add_ValueChanged({
        param($slider)
        $percentage = [math]::Round($slider.Value * 100)
        $sync.FontScalingValue.Text = "$percentage%"
    })

    $sync["FontScalingResetButton"].Add_Click({
        $sync.FontScalingSlider.Value = 1.0
        $sync.FontScalingValue.Text = "100%"
    })

    $sync["FontScalingApplyButton"].Add_Click({
        $scaleFactor = $sync.FontScalingSlider.Value
        Invoke-WinUtilFontScaling -ScaleFactor $scaleFactor
        Invoke-WPFPopup -Action "Hide" -Popups @("FontScaling")
    })

    # Manipuladores de botões da aba Win11ISO
    $sync["WPFWin11ISOBrowseButton"].Add_Click({
        Invoke-WinUtilISOBrowse
    })

    $sync["WPFWin11ISODownloadLink"].Add_Click({
        Start-Process "https://www.microsoft.com/software-download/windows11"
    })

    $sync["WPFWin11ISOMountButton"].Add_Click({
        Invoke-WinUtilISOMountAndVerify
    })

    $sync["WPFWin11ISOModifyButton"].Add_Click({
        Invoke-WinUtilISOModify
    })

    $sync["WPFWin11ISOChooseISOButton"].Add_Click({
        $sync["WPFWin11ISOOptionUSB"].Visibility = "Collapsed"
        Invoke-WinUtilISOExport
    })

    $sync["WPFWin11ISOChooseUSBButton"].Add_Click({
        $sync["WPFWin11ISOOptionUSB"].Visibility = "Visible"
        Invoke-WinUtilISORefreshUSBDrives
    })

    $sync["WPFWin11ISORefreshUSBButton"].Add_Click({
        Invoke-WinUtilISORefreshUSBDrives
    })

    $sync["WPFWin11ISOWriteUSBButton"].Add_Click({
        Invoke-WinUtilISOWriteUSB
    })

    $sync["WPFWin11ISOCleanResetButton"].Add_Click({
        Invoke-WinUtilISOCleanAndReset
    })

    $sync["WPFWin11ISOBackButton"].Add_Click({
        $sync["WPFWin11ISOSelectSection"].IsSelected = $true
    })

    $sync["WPFWin11ISOForwardButton"].Add_Click({
        $sync["WPFWin11ISOModifySection"].IsSelected = $true
    })

    $buildClock.Stop()
    Write-WinUtilLog -Level "DEBUG" -Component "UI" -Message "Interface construída em $($buildClock.ElapsedMilliseconds) ms, exibindo a janela."
    Write-WinUtilTimingSummary -Scope "UI" -TotalMilliseconds $buildClock.ElapsedMilliseconds

    # A prioridade de entrada roda atrás de tudo que já está enfileirado, então isto dispara no primeiro
    # momento em que a janela realmente poderia atender a um clique
    $sync["Form"].Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Input, [action]{
        $sinceStart = [int]((Get-Date) - $sync.StartedAt).TotalMilliseconds
        Write-WinUtilLog -Level "DEBUG" -Component "UI" -Message "tempo: interface pronta para entrada $sinceStart ms após o início."
    }) | Out-Null

    # A aba padrão é construída antes de a janela ser exibida, em uma passagem que ninguém espera, para que
    # ela abra com a lista de aplicativos pronta em vez de preencher aos poucos. Offline começa em outra aba.
    if (-not $PARAM_OFFLINE) {
        $sync.BuildingBeforeShow = $true
        try {
            Measure-WinUtilStep -Scope "UI" -Name "construir aba padrão antes de exibir" -ScriptBlock { Invoke-WPFTab "WPFTab1BT" }
        } finally {
            $sync.BuildingBeforeShow = $false
        }
    }

    $sync["Form"].ShowDialog() | Out-Null

    # ShowDialog retorna quando a janela desaparece; para o dispatcher para que este runspace possa fechar
    [System.Windows.Threading.Dispatcher]::CurrentDispatcher.InvokeShutdown()
}
