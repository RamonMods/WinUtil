function Invoke-WinUtilRobocopy {
    <#
        .SYNOPSIS
            Executa o robocopy e falha a tarefa quando algum arquivo não foi copiado

        .DESCRIPTION
            O robocopy informa o resultado pelo código de saída, em vez de lançar uma exceção, e códigos abaixo de 8
            significam sucesso: 1 indica que arquivos foram copiados, 3 indica copiados mais arquivos extras. 8 ou acima significam
            que pelo menos um arquivo não foi copiado, o que gera uma mídia que parece completa mas não inicializa.
    #>
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination,
        [string[]]$Arguments = @()
    )

    & robocopy $Source $Destination @Arguments
    $code = $LASTEXITCODE

    if ($code -ge 8) {
        throw "O robocopy não conseguiu copiar todos os arquivos de $Source para $Destination (código de saída $code)."
    }

    Write-WinUtilISOLog "robocopy concluído com código de saída $code."
}

function Write-WinUtilISOLog {
    <#
    .SYNOPSIS
        Acrescenta uma linha ao registro de status do Criar Win11 e ao log da sessão.

    .DESCRIPTION
        O registro de status é um controle da interface, então a inclusão é enviada à thread da interface
        em vez de ser aguardada. Sem uma janela, ele degrada para apenas o log da sessão, o que mantém
        os corpos das tarefas livres de verificações do tipo "existe uma interface".
    #>
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR")]
        [string]$Level = "INFO",
        [switch]$SkipSessionLog
    )

    if (-not $SkipSessionLog) {
        Write-WinUtilLog -Level $Level -Component "Win11Creator" -Message $Message
    }

    Invoke-WPFUIThread -Async -Parameters @{
        LogLine = "[$((Get-Date).ToString('HH:mm:ss'))] $Message"
    } -ScriptBlock {
        param($LogLine)

        $box = $sync["WPFWin11ISOStatusLog"]
        if ($null -eq $box) { return }

        if ($box.Text -eq "Pronto. Selecione uma ISO do Windows 11 para começar.") {
            $box.Text = $LogLine
        } else {
            $box.Text += "`n$LogLine"
        }
        $box.CaretIndex = $box.Text.Length
        $box.ScrollToEnd()
    }
}

function Set-WinUtilISOStep {
    <#
        .SYNOPSIS
            Escolhe uma página do assistente do Criar Win11 e define para quais páginas dá para voltar

        .PARAMETER Step
            Select, Modify, Working ou Output

        .PARAMETER Label
            Título exibido na página de trabalho enquanto uma operação longa é executada

        .PARAMETER Reverse
            Gira o ícone da página de trabalho ao contrário
    #>
    param(
        [Parameter(Mandatory)]
        [ValidateSet("Select", "Modify", "Working", "Output")]
        [string]$Step,

        [string]$Label,

        [switch]$Reverse
    )

    Invoke-WPFUIThread -Parameters @{ Step = $Step; Label = $Label; Reverse = [bool]$Reverse } -ScriptBlock {
        param($Step, $Label, $Reverse)

        if ($Label) { $sync["WPFWin11ISOWorkingLabel"].Text = $Label }

        $sync["WPFWin11ISOWorkingSpinner"].Tag = if ($Reverse) { "Reverse" } else { "Forward" }

        $sync["WPFWin11ISOSelectSection"].IsEnabled = $Step -in @("Select", "Modify")
        $sync["WPFWin11ISOModifySection"].IsEnabled = $Step -eq "Modify"
        $sync["WPFWin11ISOOutputSection"].IsEnabled = $Step -eq "Output"

        $sync["WPFWin11ISO$($Step)Section"].IsSelected = $true
    }
}

function Get-WinUtilEditionIdFromName {
    <#
    .SYNOPSIS
        Mapeia o nome de exibição de uma edição do Windows 11 para o id de edição usado pela instalação autônoma.
    #>
    param([string]$EditionName)

    $normalizedName = ($EditionName -replace '^Windows\s+11\s+', '').Trim()
    switch -Regex ($normalizedName) {
        '^Home Single Language$'      { return 'CoreSingleLanguage' }
        '^Home N$'                    { return 'CoreN' }
        '^Home$'                      { return 'Core' }
        '^Pro for Workstations N$'    { return 'ProfessionalWorkstationN' }
        '^Pro for Workstations$'      { return 'ProfessionalWorkstation' }
        '^Pro Education N$'           { return 'ProfessionalEducationN' }
        '^Pro Education$'             { return 'ProfessionalEducation' }
        '^Pro N$'                     { return 'ProfessionalN' }
        '^Pro$'                       { return 'Professional' }
        '^Education N$'               { return 'EducationN' }
        '^Education$'                 { return 'Education' }
        '^Enterprise LTSC N$'         { return 'EnterpriseSN' }
        '^Enterprise LTSC$'           { return 'EnterpriseS' }
        '^Enterprise N$'              { return 'EnterpriseN' }
        '^Enterprise$'                { return 'Enterprise' }
        default                       { return '' }
    }
}

function Get-WinUtilImageEditionId {
    <#
    .SYNOPSIS
        Resolve o id de edição de instalação independente do idioma para uma imagem do Windows.

    .DESCRIPTION
        Lê primeiramente o EditionId dos metadados da imagem, que reporta o mesmo
        valor canônico (Professional, Core, ...) em qualquer idioma de ISO, e
        usa como fallback o mapa de nomes de exibição em inglês quando os metadados não podem
        ser lidos. Nunca lança exceção: uma edição não resolvível resulta em uma string vazia para
        que o chamador ignore sources\ei.cfg em vez de gravar um valor errado.
    #>
    param(
        [Parameter(Mandatory)][string]$ImagePath,
        [Parameter(Mandatory)][int]$ImageIndex,
        [string]$EditionName
    )

    try {
        $detail = Get-WindowsImage -ImagePath $ImagePath -Index $ImageIndex -ErrorAction Stop
        if ($detail -and $detail.EditionId) {
            return [string]$detail.EditionId
        }
    } catch {
        Write-Verbose "Não foi possível ler os metadados da imagem para o índice ${ImageIndex}: $_"
    }

    return Get-WinUtilEditionIdFromName -EditionName $EditionName
}

function Invoke-WinUtilISOBrowse {
    Add-Type -AssemblyName System.Windows.Forms

    $dlg = [System.Windows.Forms.OpenFileDialog]::new()
    $dlg.Title            = "Selecionar ISO do Windows 11"
    $dlg.Filter           = "Arquivos ISO (*.iso)|*.iso|Todos os arquivos (*.*)|*.*"
    $dlg.InitialDirectory = [System.Environment]::GetFolderPath("Desktop")

    if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }

    $isoPath    = $dlg.FileName
    $fileSizeGB = [math]::Round((Get-Item $isoPath).Length / 1GB, 2)

    $sync["WPFWin11ISOPath"].Text           = $isoPath
    $sync["WPFWin11ISOFileInfo"].Text       = "Tamanho do arquivo: $fileSizeGB GB"
    $sync["WPFWin11ISOFileInfo"].Visibility = "Visible"
    $sync["WPFWin11ISOVerifyResultPanel"].Visibility  = "Collapsed"

    Set-WinUtilISOStep -Step "Select"

    Write-WinUtilISOLog "ISO selecionada: $isoPath  ($fileSizeGB GB)"
}

function Invoke-WinUtilISOMountAndVerify {
    $isoPath = $sync["WPFWin11ISOPath"].Text

    if ([string]::IsNullOrWhiteSpace($isoPath) -or $isoPath -eq "No ISO selected...") {
        Show-WinUtilMessage -Message "Selecione um arquivo ISO primeiro." -Title "Nenhuma ISO Selecionada" -Button "OK" -Icon "Warning" | Out-Null
        return
    }

    Start-WinUtilJob -Name "ISO mount" -Description "Montando ISO" -Parameters @{
        IsoPath = $isoPath
    } -ScriptBlock {
        param($isoPath)

        Invoke-WPFUIThread -ScriptBlock {
            $sync["WPFWin11ISOBrowseButton"].IsEnabled = $false
            $sync["WPFWin11ISOMountButton"].IsEnabled = $false
            $sync["WPFWin11ISOModifyButton"].IsEnabled = $false
            $sync["WPFWin11ISOVerifyResultPanel"].Visibility = "Collapsed"
        }
        Set-WinUtilISOStep -Step "Working" -Label "Montando e verificando a ISO"

        $verified = $false
        $mountedByThisRun = $false

        try {
            $previous = $sync["Win11ISOImagePath"]
            if ($previous -and $previous -ne $isoPath -and (Get-DiskImage -ImagePath $previous -ErrorAction SilentlyContinue).Attached) {
                try {
                    Dismount-DiskImage -ImagePath $previous -ErrorAction Stop
                    Write-WinUtilISOLog "ISO verificada anteriormente desmontada: $previous"
                } catch {
                    Write-WinUtilISOLog -Level "ERROR" -Message "Não foi possível desmontar a ISO verificada anteriormente ${previous}: $_"
                    Show-WinUtilMessage -Message "A ISO verificada anteriormente ainda está montada e não pôde ser desmontada:`n`n$previous`n`nDesmonte-a manualmente e selecione uma ISO novamente." -Title "ISO Anterior Ainda Montada" -Button "OK" -Icon "Error" | Out-Null
                    $stillMounted = [System.InvalidOperationException]::new("Não foi possível desmontar a ISO verificada anteriormente $previous.")
                    $stillMounted.Data["WinUtilErrorReported"] = $true
                    throw $stillMounted
                }
            }

            $sync["Win11ISOImageInfo"] = $null
            $sync["Win11ISODriveLetter"] = $null
            $sync["Win11ISOWimPath"] = $null
            $sync["Win11ISOImagePath"] = $null

            Write-WinUtilISOLog "Montando ISO: $isoPath"
            Step-WinUtilJob -Status "Montando ISO..." -Percent 10

            Mount-DiskImage -ImagePath $isoPath -ErrorAction Stop
            $mountedByThisRun = $true

            # Com limite, porque uma imagem danificada ou já montada pode nunca apresentar uma letra
            # de unidade. A camada de tarefas executa uma por vez, então esperar aqui para sempre bloquearia
            # todas as outras ações e a espera de encerramento do restante da sessão.
            $letter = $null
            $mountClock = [System.Diagnostics.Stopwatch]::StartNew()
            while (-not $letter -and $mountClock.Elapsed.TotalSeconds -lt 60) {
                Start-Sleep -Milliseconds 500
                $letter = (Get-DiskImage -ImagePath $isoPath | Get-Volume).DriveLetter
            }

            if (-not $letter) {
                throw "A ISO foi montada, mas nenhuma letra de unidade apareceu em 60 segundos: $isoPath"
            }

            $driveLetter = "${letter}:"
            Write-WinUtilISOLog "Montada na unidade $driveLetter"

            Step-WinUtilJob -Status "Verificando o conteúdo da ISO..." -Percent 30

            $wimPath = Join-Path $driveLetter "sources\install.wim"
            $esdPath = Join-Path $driveLetter "sources\install.esd"

            if (-not (Test-Path $wimPath) -and -not (Test-Path $esdPath)) {
                Write-WinUtilISOLog -Level "ERROR" -Message "install.wim/install.esd não encontrado - não é uma ISO válida do Windows."
                Show-WinUtilMessage -Message "Isso não parece ser uma ISO válida do Windows.`n`ninstall.wim / install.esd não foi encontrado." -Title "ISO Inválida" -Button "OK" -Icon "Error" | Out-Null
                # Retornar aqui faria a camada de tarefas relatar a execução como concluída
                $exception = [System.InvalidOperationException]::new("install.wim / install.esd não foi encontrado em $isoPath.")
                $exception.Data["WinUtilErrorReported"] = $true
                throw $exception
            }

            $activeWim = if (Test-Path $wimPath) { $wimPath } else { $esdPath }

            Step-WinUtilJob -Status "Lendo metadados da imagem..." -Percent 55
            $imageInfo = Get-WindowsImage -ImagePath $activeWim | Select-Object ImageIndex, ImageName

            if (-not ($imageInfo | Where-Object { $_.ImageName -match "Windows 11" })) {
                Write-WinUtilISOLog -Level "ERROR" -Message "Nenhuma edição do 'Windows 11' encontrada na imagem."
                Show-WinUtilMessage -Message "Nenhuma edição do Windows 11 foi encontrada nesta ISO.`n`nApenas ISOs oficiais do Windows 11 são suportadas." -Title "Não é uma ISO do Windows 11" -Button "OK" -Icon "Error" | Out-Null
                $exception = [System.InvalidOperationException]::new("Nenhuma edição do Windows 11 foi encontrada em $isoPath.")
                $exception.Data["WinUtilErrorReported"] = $true
                throw $exception
            }

            $sync["Win11ISOImageInfo"] = $imageInfo
            $sync["Win11ISODriveLetter"] = $driveLetter
            $sync["Win11ISOWimPath"]     = $activeWim
            $sync["Win11ISOImagePath"]   = $isoPath

            # Resolve a edição padrão aqui, fora da thread da interface: os metadados da imagem
            # contêm o EditionId independente do idioma, então uma imagem
            # francesa "Professionnel" ainda pré-seleciona Pro em vez de usar como fallback
            # o índice 0 (Famille). A correspondência pelo nome de exibição em inglês permanece como
            # fallback para imagens cujos metadados não podem ser lidos.
            $defaultEditionListIndex = 0
            $listIndex = 0
            foreach ($img in @($imageInfo)) {
                $candidateId = Get-WinUtilImageEditionId -ImagePath $activeWim -ImageIndex $img.ImageIndex -EditionName $img.ImageName
                $candidateItem = "$($img.ImageIndex): $($img.ImageName)"
                if (($candidateId -eq 'Professional') -or ([string]::IsNullOrEmpty($candidateId) -and $candidateItem -match "Windows 11 Pro(?![\w ])")) {
                    $defaultEditionListIndex = $listIndex
                    break
                }
                $listIndex++
            }

            Invoke-WPFUIThread -Parameters @{
                DriveLetter = $driveLetter
                ImageFileName = Split-Path $activeWim -Leaf
                ImageInfo = $imageInfo
                DefaultEditionListIndex = $defaultEditionListIndex
            } -ScriptBlock {
                param($DriveLetter, $ImageFileName, $imageInfo, $DefaultEditionListIndex)

                $sync["WPFWin11ISOMountDriveLetter"].Text = $DriveLetter
                $sync["WPFWin11ISOImageFile"].Text        = $ImageFileName
                $sync["WPFWin11ISOEditionComboBox"].Items.Clear()
                foreach ($img in $imageInfo) {
                    [void]$sync["WPFWin11ISOEditionComboBox"].Items.Add("$($img.ImageIndex): $($img.ImageName)")
                }
                if ($sync["WPFWin11ISOEditionComboBox"].Items.Count -gt 0) {
                    $sync["WPFWin11ISOEditionComboBox"].SelectedIndex = [Math]::Min($DefaultEditionListIndex, $sync["WPFWin11ISOEditionComboBox"].Items.Count - 1)
                }
                $sync["WPFWin11ISOVerifyResultPanel"].Visibility = "Visible"
                Set-WinUtilISOStep -Step "Modify"
            }

            $verified = $true
            Write-WinUtilISOLog "ISO verificada com sucesso.  Edições encontradas: $($imageInfo.Count)"
        } finally {
            # Um pipeline do PowerShell interrompido ignora os blocos catch, mas ainda executa o finally. Mantenha a
            # limpeza da ISO de origem aqui para que fechar o WinUtil durante a verificação não a deixe
            # montada.
            if (-not $verified -and $mountedByThisRun) {
                try {
                    Write-WinUtilISOLog "A verificação falhou; desmontando a ISO de origem."
                    Dismount-DiskImage -ImagePath $isoPath -ErrorAction Stop
                } catch {
                    Write-WinUtilISOLog -Level "WARN" -Message "Não foi possível desmontar a ISO após a falha na verificação: $_"
                }
            }

            Invoke-WPFUIThread -Parameters @{ Verified = $verified } -ScriptBlock {
                param($Verified)

                $sync["WPFWin11ISOBrowseButton"].IsEnabled = $true
                $sync["WPFWin11ISOMountButton"].IsEnabled = $true
                $sync["WPFWin11ISOModifyButton"].IsEnabled = [bool]$Verified

                if ($sync["WPFWin11ISOWorkingSection"].IsSelected) {
                    Set-WinUtilISOStep -Step "Select"
                }
            }
        }
    }
}

function Invoke-WinUtilISOModify {
    $isoPath     = $sync["Win11ISOImagePath"]
    $driveLetter = $sync["Win11ISODriveLetter"]
    $wimPath     = $sync["Win11ISOWimPath"]

    if (-not $isoPath) {
        Show-WinUtilMessage -Message "Nenhuma ISO verificada encontrada. Selecione e verifique uma ISO primeiro." -Title "Não Pronto" -Button "OK" -Icon "Warning" | Out-Null
        return
    }

    $selectedItem     = $sync["WPFWin11ISOEditionComboBox"].SelectedItem
    $selectedWimIndex = 1
    if ($selectedItem -and $selectedItem -match '^(\d+):') {
        $selectedWimIndex = [int]$Matches[1]
    } elseif ($sync["Win11ISOImageInfo"]) {
        $selectedWimIndex = $sync["Win11ISOImageInfo"][0].ImageIndex
    }
    $selectedEditionName = if ($selectedItem) { ($selectedItem -replace '^\d+:\s*', '') } else { "Desconhecida" }

    # Um diretório de trabalho novo a cada execução; a detecção de trabalho existente serve apenas para retomar uma exportação
    $workDir = Join-Path $env:TEMP "WinUtil_Win11ISO_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    if (Test-Path $workDir) {
        $workDir = "$($workDir)_$(([guid]::NewGuid()).ToString('N').Substring(0, 8))"
    }

    $autounattendContent = if ($WinUtilAutounattendXml) {
        $WinUtilAutounattendXml
    } else {
        $toolsXml = Join-Path $PSScriptRoot "..\..\tools\autounattend.xml"
        if (Test-Path $toolsXml) { Get-Content $toolsXml -Raw } else { "" }
    }

    Start-WinUtilJob -Name "ISO modify" -Description "Modificando ISO" -Parameters @{
        IsoPath             = $isoPath
        DriveLetter         = $driveLetter
        WimPath             = $wimPath
        WorkDir             = $workDir
        SelectedWimIndex    = $selectedWimIndex
        SelectedEditionName = $selectedEditionName
        AutounattendContent = $autounattendContent
        InjectDrivers       = $sync["WPFWin11ISOInjectDrivers"].IsChecked -eq $true
    } -ScriptBlock {
        param($isoPath, $DriveLetter, $WimPath, $workDir, $SelectedWimIndex, $SelectedEditionName, $AutounattendContent, $InjectDrivers)

        Invoke-WPFUIThread -ScriptBlock {
            $sync["WPFWin11ISOModifyButton"].IsEnabled = $false
        }
        $workingLabel = if ($InjectDrivers) { "Modificando install.wim" } else { "Preparando a mídia de instalação" }
        Set-WinUtilISOStep -Step "Working" -Label $workingLabel

        $modified = $false
        try {
            Write-WinUtilISOLog "Edição selecionada: $SelectedEditionName (Índice $SelectedWimIndex)"
            Write-WinUtilISOLog "Criando diretório de trabalho: $workDir"

            $isoContents = Join-Path $workDir "iso_contents"
            New-Item -ItemType Directory -Path $isoContents -Force | Out-Null
            Step-WinUtilJob -Status "Copiando o conteúdo da ISO..." -Percent 10

            Write-WinUtilISOLog "Copiando o conteúdo da ISO de $DriveLetter para $isoContents..."
            Invoke-WinUtilRobocopy -Source $DriveLetter -Destination $isoContents -Arguments @("/E","/NFL","/NDL","/NJH","/NJS")
            Write-WinUtilISOLog "Conteúdo da ISO copiado."
            Step-WinUtilJob -Status "Preparando a mídia de instalação..." -Percent 25

            $sourceImageFileName = Split-Path $WimPath -Leaf
            $localWim = Join-Path $isoContents "sources\$sourceImageFileName"
            if (-not (Test-Path $localWim)) {
                throw "Arquivo de imagem da ISO copiado não encontrado: sources\$sourceImageFileName"
            }

            Write-WinUtilISOLog "Gravando autounattend.xml e a seleção de edição..."
            $driversInjected = [ref]$false
            Invoke-WinUtilISOScript -ISOContentsDir $isoContents `
                -AutoUnattendXml $AutounattendContent `
                -InjectCurrentSystemDrivers $InjectDrivers `
                -InstallImagePath $localWim `
                -InstallImageIndex $SelectedWimIndex `
                -InstallEditionId (Get-WinUtilImageEditionId -ImagePath $localWim -ImageIndex $SelectedWimIndex -EditionName $SelectedEditionName) `
                -Log {
                    param($m)
                    if ($m -like "Warning:*") {
                        # O wrapper de tarefas registra a saída WarningRecord no log da sessão. Aqui
                        # apenas acrescentamos ao controle de status da ISO para que o mesmo aviso não seja duplicado.
                        Write-WinUtilISOLog -Level "WARN" -Message $m -SkipSessionLog
                        Write-Warning $m
                    } else {
                        Write-WinUtilISOLog $m
                    }
                } `
                -DriversInjected $driversInjected

            if ($driversInjected.Value) {
                Step-WinUtilJob -Status "Finalizando a imagem de instalação..." -Percent 70
                Write-WinUtilISOLog "Drivers do sistema atual adicionados a $sourceImageFileName índice $SelectedWimIndex."
            } elseif ($InjectDrivers) {
                Step-WinUtilJob -Status "Preservando a imagem de instalação..." -Percent 70
                Write-WinUtilISOLog "Nenhum driver do sistema atual foi injetado em $sourceImageFileName índice $SelectedWimIndex; o install.wim foi deixado inalterado. Consulte as entradas de aviso no log para detalhes."
            } else {
                Step-WinUtilJob -Status "Preservando a imagem de instalação..." -Percent 70
                Write-WinUtilISOLog "O $sourceImageFileName original foi preservado sem montagem, exportação ou modificação."
            }

            Step-WinUtilJob -Status "Desmontando a ISO de origem..." -Percent 80
            Write-WinUtilISOLog "Desmontando a ISO original..."
            Dismount-DiskImage -ImagePath $isoPath -ErrorAction Stop

            $sync["Win11ISOWorkDir"]     = $workDir
            $sync["Win11ISOContentsDir"] = $isoContents

            Step-WinUtilJob -Status "Modificação concluída" -Percent 100
            Write-WinUtilISOLog "Modificação do install.wim concluída. Escolha uma opção de saída na última etapa."

            Set-WinUtilISOStep -Step "Output"
            $modified = $true
        } catch {
            Write-WinUtilISOLog -Level "ERROR" -Message "Falha na modificação: $_"
            $_.Exception.Data["WinUtilErrorReported"] = $true

            Show-WinUtilMessage -Message "Ocorreu um erro durante a modificação do install.wim:`n`n$_" -Title "Erro de Modificação" -Button "OK" -Icon "Error" | Out-Null

            throw
        } finally {
            # BeginStop ignora o catch, então a limpeza tanto de falhas quanto de cancelamento pelo usuário precisa ficar no finally.
            if (-not $modified) {
                try {
                    $mountedISO = Get-DiskImage -ImagePath $isoPath
                    if ($mountedISO -and $mountedISO.Attached) {
                        Write-WinUtilISOLog "Limpando: desmontando a ISO de origem..."
                        Dismount-DiskImage -ImagePath $isoPath -ErrorAction Stop
                    }
                } catch { Write-WinUtilISOLog -Level "WARN" -Message "Não foi possível desmontar a ISO durante a limpeza: $_" }

                try {
                    if (Test-Path $workDir) {
                        Write-WinUtilISOLog "Limpando: removendo o diretório temporário $workDir..."
                        Remove-Item -Path $workDir -Recurse -Force
                    }
                } catch { Write-WinUtilISOLog -Level "WARN" -Message "Não foi possível remover o diretório temporário durante a limpeza: $_" }

                $sync["Win11ISOImageInfo"] = $null
                $sync["Win11ISODriveLetter"] = $null
                $sync["Win11ISOWimPath"] = $null
                $sync["Win11ISOImagePath"] = $null
            }

            Invoke-WPFUIThread -Parameters @{ Modified = $modified } -ScriptBlock {
                param($Modified)

                $sync["WPFWin11ISOModifyButton"].IsEnabled = [bool]$Modified

                if ($sync["WPFWin11ISOWorkingSection"].IsSelected) {
                    Set-WinUtilISOStep -Step "Select"
                }
            }
        }
    }
}

function Invoke-WinUtilISOCheckExistingWork {
    if ($sync["Win11ISOContentsDir"] -and (Test-Path $sync["Win11ISOContentsDir"])) { return }

    # Nada a retomar enquanto uma modificação ainda está produzindo o diretório de trabalho. A aba
    # é inicializada apenas uma vez, então agende outra verificação em vez de perder definitivamente um trabalho que
    # aparece depois desta primeira chamada.
    if ($sync.ActiveJob) {
        if (-not $sync["Win11ISOExistingWorkRetryPending"]) {
            $sync["Win11ISOExistingWorkRetryPending"] = $true
            Invoke-WinUtilWhenIdle -DelayMilliseconds 500 -Callback {
                $sync["Win11ISOExistingWorkRetryPending"] = $false
                Invoke-WinUtilISOCheckExistingWork
            }
        }
        return
    }
    $sync["Win11ISOExistingWorkRetryPending"] = $false

    $existingWorkDir = Get-Item -Path (Join-Path $env:TEMP "WinUtil_Win11ISO*") |
        Where-Object { $_.PSIsContainer } | Sort-Object LastWriteTime -Descending | Select-Object -First 1

    if (-not $existingWorkDir) { return }

    $isoContents = Join-Path $existingWorkDir.FullName "iso_contents"
    if (-not (Test-Path $isoContents)) { return }

    $sync["Win11ISOWorkDir"]     = $existingWorkDir.FullName
    $sync["Win11ISOContentsDir"] = $isoContents

    Set-WinUtilISOStep -Step "Output"

    $modified = $existingWorkDir.LastWriteTime.ToString("yyyy-MM-dd HH:mm")
    Write-WinUtilISOLog "Diretório de trabalho existente encontrado: $($existingWorkDir.FullName)"
    Write-WinUtilISOLog "Última modificação: $modified - Ignorando as etapas anteriores e retomando na etapa de saída."
    Write-WinUtilISOLog "Clique em 'Começar de Novo' se quiser recomeçar com uma nova ISO."

    Show-WinUtilMessage -Message "Foi encontrado um diretório de trabalho anterior do WinUtil ISO:`n`n$($existingWorkDir.FullName)`n`n(Última modificação: $modified)`n`nA etapa de saída foi restaurada para que você possa salvar a imagem já modificada.`n`nClique em 'Começar de Novo' lá se quiser recomeçar." -Title "Trabalho Existente Encontrado" -Button "OK" -Icon "Info" | Out-Null
}

function Invoke-WinUtilISOCleanAndReset {
    $workDir = $sync["Win11ISOWorkDir"]

    if ($workDir -and (Test-Path $workDir)) {
        $confirm = Show-WinUtilMessage -Message "Isso excluirá o diretório de trabalho temporário:`n`n$workDir`n`nE redefinirá a interface de volta ao início.`n`nContinuar?" -Title "Começar de Novo" -Button "YesNo" -Icon "Warning"
        if ($confirm -ne "Yes") { return }
    }

    Start-WinUtilJob -Name "ISO cleanup" -Description "Limpando" -Parameters @{
        WorkDir = $workDir
    } -ScriptBlock {
        param($workDir)

        Invoke-WPFUIThread -ScriptBlock { $sync["WPFWin11ISOCleanResetButton"].IsEnabled = $false }
        Set-WinUtilISOStep -Step "Working" -Label "Recomeçando" -Reverse

        try {
            if ($workDir) {
                $mountDir = Join-Path $workDir "wim_mount"
                try {
                    $mountedImages = Get-WindowsImage -Mounted | Where-Object { $_.Path -like "$workDir*" }
                    if ($mountedImages) {
                        foreach ($img in $mountedImages) {
                            Write-WinUtilISOLog "Desmontando o WIM em: $($img.Path) (descartando alterações)..."
                            Step-WinUtilJob -Status "Desmontando a imagem WIM..." -Percent 3
                            Dismount-WindowsImage -Path $img.Path -Discard
                            Write-WinUtilISOLog "WIM desmontado com sucesso."
                        }
                    } elseif (Test-Path $mountDir) {
                        Write-WinUtilISOLog "Nenhum WIM montado relatado por Get-WindowsImage. Executando DISM /Cleanup-Wim como precaução..."
                        Step-WinUtilJob -Status "Executando limpeza do DISM..." -Percent 3
                        & dism /English /Cleanup-Wim | ForEach-Object { Write-WinUtilISOLog $_ }
                    }
                } catch {
                    Write-WinUtilISOLog -Level "WARN" -Message "Não foi possível desmontar o WIM corretamente. Tentando o fallback DISM /Cleanup-Wim: $_"
                    try { & dism /English /Cleanup-Wim | ForEach-Object { Write-WinUtilISOLog $_ } }
                    catch { Write-WinUtilISOLog -Level "WARN" -Message "DISM /Cleanup-Wim também falhou: $_" }
                }
            }

            if ($workDir -and (Test-Path $workDir)) {
                Write-WinUtilISOLog "Verificando arquivos a excluir em: $workDir"
                Step-WinUtilJob -Status "Verificando arquivos..." -Percent 5

                $allFiles = @(Get-ChildItem -Path $workDir -File -Recurse -Force)
                $allDirs  = @(Get-ChildItem -Path $workDir -Directory -Recurse -Force |
                    Sort-Object { $_.FullName.Length } -Descending)
                $total   = $allFiles.Count
                $deleted = 0

                Write-WinUtilISOLog "Encontrados $total arquivos para excluir."

                foreach ($f in $allFiles) {
                    try { Remove-Item -Path $f.FullName -Force } catch { Write-WinUtilISOLog -Level "WARN" -Message "Não foi possível excluir $($f.FullName): $_" }
                    $deleted++
                    if ($deleted % 100 -eq 0 -or $deleted -eq $total) {
                        $pct = [math]::Round(($deleted / [Math]::Max($total, 1)) * 85) + 5
                        Step-WinUtilJob -Status "Excluindo arquivos em $($f.Directory.Name)... ($deleted / $total)" -Percent $pct
                    }
                }

                foreach ($d in $allDirs) {
                    try { Remove-Item -Path $d.FullName -Force } catch { Write-WinUtilISOLog -Level "WARN" -Message "Não foi possível excluir $($d.FullName): $_" }
                }

                try { Remove-Item -Path $workDir -Recurse -Force } catch { Write-WinUtilISOLog -Level "WARN" -Message "Não foi possível excluir o diretório temporário ${WorkDir}: $_" }

                if (Test-Path $workDir) {
                    Write-WinUtilISOLog -Level "WARN" -Message "Alguns itens não puderam ser excluídos em $workDir"
                } else {
                    Write-WinUtilISOLog "Diretório temporário excluído com sucesso."
                }
            } else {
                Write-WinUtilISOLog "Nenhum diretório temporário encontrado - redefinindo a interface."
            }

            Step-WinUtilJob -Status "Redefinindo a interface..." -Percent 95
            Write-WinUtilISOLog "Redefinindo a interface..."

            $sync["Win11ISOWorkDir"]     = $null
            $sync["Win11ISOContentsDir"] = $null
            $sync["Win11ISOImagePath"]   = $null
            $sync["Win11ISODriveLetter"] = $null
            $sync["Win11ISOWimPath"]     = $null
            $sync["Win11ISOImageInfo"]   = $null
            $sync["Win11ISOUSBDisks"]    = $null

            Invoke-WPFUIThread -ScriptBlock {
                $sync["WPFWin11ISOPath"].Text                    = "Nenhuma ISO selecionada..."
                $sync["WPFWin11ISOFileInfo"].Visibility          = "Hidden"
                $sync["WPFWin11ISOVerifyResultPanel"].Visibility = "Collapsed"
                $sync["WPFWin11ISOOptionUSB"].Visibility         = "Collapsed"
                $sync["WPFWin11ISODonePanel"].Visibility         = "Collapsed"
                $sync["WPFWin11ISOModifyButton"].IsEnabled       = $true
                $sync["WPFWin11ISOStatusLog"].Text               = "Pronto. Selecione uma ISO do Windows 11 para começar."
                Set-WinUtilISOStep -Step "Select"
            }
            Step-WinUtilJob -Hide
        } finally {
            Invoke-WPFUIThread -ScriptBlock {
                $sync["WPFWin11ISOCleanResetButton"].IsEnabled = $true

                if ($sync["WPFWin11ISOWorkingSection"].IsSelected) {
                    Set-WinUtilISOStep -Step "Select"
                }
            }
        }
    }
}

function Invoke-WinUtilISOExport {
    $contentsDir = $sync["Win11ISOContentsDir"]

    if (-not $contentsDir -or -not (Test-Path $contentsDir)) {
        Show-WinUtilMessage -Message "Nenhum conteúdo de ISO modificado encontrado.  Execute a etapa de modificação primeiro." -Title "Não Pronto" -Button "OK" -Icon "Warning" | Out-Null
        return
    }

    Add-Type -AssemblyName System.Windows.Forms

    $dlg = [System.Windows.Forms.SaveFileDialog]::new()
    $dlg.Title            = "Salvar ISO do Windows 11 Modificada"
    $dlg.Filter           = "Arquivos ISO (*.iso)|*.iso"
    $dlg.FileName         = "Win11_Modified_$(Get-Date -Format 'yyyyMMdd').iso"
    $dlg.InitialDirectory = [System.Environment]::GetFolderPath("Desktop")

    if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }

    Start-WinUtilJob -Name "ISO export" -Description "Criando ISO" -Parameters @{
        ContentsDir = $contentsDir
        OutputISO   = $dlg.FileName
    } -ScriptBlock {
        param($contentsDir, $outputISO)

        Invoke-WPFUIThread -ScriptBlock { $sync["WPFWin11ISOChooseISOButton"].IsEnabled = $false }
        Set-WinUtilISOStep -Step "Working" -Label "Criando o arquivo ISO"

        try {
            $oscdimg = Get-WinUtilOscdimgPath
            if (-not $oscdimg) {
                Set-WinUtilISOStep -Step "Output"
                Show-WinUtilMessage -Message "oscdimg.exe não foi encontrado nem pôde ser instalado automaticamente.`n`nInstale-o manualmente:`n  winget install -e --id Microsoft.OSCDIMG`n`nOu instale o Windows ADK em:`nhttps://learn.microsoft.com/windows-hardware/get-started/adk-install" -Title "oscdimg Não Encontrado" -Button "OK" -Icon "Warning" | Out-Null
                throw "oscdimg.exe não foi encontrado nem pôde ser instalado automaticamente."
            }

            Write-WinUtilISOLog "Exportando para ISO: $outputISO"
            Step-WinUtilJob -Status "Criando ISO..." -Percent 10

            $bootData    = "2#p0,e,b`"$contentsDir\boot\etfsboot.com`"#pEF,e,b`"$contentsDir\efi\microsoft\boot\efisys.bin`""
            $oscdimgArgs = @("-m", "-o", "-u2", "-udfver102", "-bootdata:$bootData", "-l`"CTOS_MODIFIED`"", "`"$contentsDir`"", "`"$outputISO`"")

            Write-WinUtilISOLog "Executando oscdimg..."

            $psi = [System.Diagnostics.ProcessStartInfo]::new()
            $psi.FileName               = $oscdimg
            $psi.Arguments              = $oscdimgArgs -join " "
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError  = $true
            $psi.UseShellExecute        = $false
            $psi.CreateNoWindow         = $true

            $proc = [System.Diagnostics.Process]::new()
            $proc.StartInfo = $psi

            # O stderr é coletado conforme chega, e não após a saída do processo. Lê-lo
            # por último causa travamento: quando o pipe de stderr enche, o oscdimg bloqueia na gravação e para
            # de produzir stdout, enquanto este loop espera um stdout que nunca virá.
            $stderrLines = [System.Collections.ArrayList]::Synchronized([System.Collections.ArrayList]::new())
            $proc.EnableRaisingEvents = $true
            $errorHandler = Register-ObjectEvent -InputObject $proc -EventName ErrorDataReceived -Action {
                if ($EventArgs.Data) { $null = $Event.MessageData.Add($EventArgs.Data) }
            } -MessageData $stderrLines

            try {
                $proc.Start() | Out-Null
                $proc.BeginErrorReadLine()

                # Transmite a saída padrão linha a linha enquanto o oscdimg é executado
                while (-not $proc.StandardOutput.EndOfStream) {
                    $line = $proc.StandardOutput.ReadLine()
                    if ($line.Trim()) { Write-WinUtilISOLog $line }
                }

                $proc.WaitForExit()
            } finally {
                Unregister-Event -SourceIdentifier $errorHandler.Name -ErrorAction SilentlyContinue
                $errorHandler | Remove-Job -Force -ErrorAction SilentlyContinue
            }

            foreach ($line in @($stderrLines)) {
                if ($line.Trim()) { Write-WinUtilISOLog -Level "WARN" -Message "[stderr]$line" }
            }

            if ($proc.ExitCode -ne 0) {
                throw "O oscdimg terminou com o código $($proc.ExitCode). Consulte o registro de status para detalhes."
            }

            Step-WinUtilJob -Status "ISO exportada" -Percent 100
            Write-WinUtilISOLog "ISO exportada com sucesso: $outputISO"
            Invoke-WPFUIThread -Parameters @{ OutputISO = $outputISO } -ScriptBlock {
                param($OutputISO)

                $sync["WPFWin11ISODoneLabel"].Text        = "ISO salva em $OutputISO"
                $sync["WPFWin11ISODonePanel"].Visibility  = "Visible"
            }
            Set-WinUtilISOStep -Step "Output"
            Show-WinUtilMessage -Message "ISO exportada com sucesso!`n`n$outputISO" -Title "Exportação Concluída" -Button "OK" -Icon "Info" | Out-Null
        } catch {
            Write-WinUtilISOLog -Level "ERROR" -Message "A exportação da ISO falhou: $_"
            $_.Exception.Data["WinUtilErrorReported"] = $true
            Set-WinUtilISOStep -Step "Output"
            Show-WinUtilMessage -Message "A exportação da ISO falhou:`n`n$_" -Title "Erro" -Button "OK" -Icon "Error" | Out-Null
            throw
        } finally {
            Invoke-WPFUIThread -ScriptBlock {
                $sync["WPFWin11ISOChooseISOButton"].IsEnabled = $true

                # O cancelamento ignora o catch, então a página de trabalho pode ainda estar ativa aqui
                if ($sync["WPFWin11ISOWorkingSection"].IsSelected) {
                    Set-WinUtilISOStep -Step "Output"
                }
            }
        }
    }
}

function Find-WinUtilOscdimg {
    <#
    .SYNOPSIS
        Procura o oscdimg.exe em todos os locais onde ele costuma ser instalado

    .DESCRIPTION
        Primeiro o PATH, pois isso cobre um ADK instalado em qualquer lugar e uma cópia manual, depois o
        local padrão do ADK e, por fim, os locais do WinGet por usuário e por computador. Usado tanto
        antes quanto depois da tentativa de instalação para que o processo atual não precise atualizar o PATH.
    #>

    $onPath = Get-Command oscdimg.exe -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }

    foreach ($root in @(
            "${env:ProgramFiles(x86)}\Windows Kits",
            "$env:ProgramFiles\Windows Kits",
            "$env:LOCALAPPDATA\Microsoft\WinGet\Packages",
            "$env:ProgramFiles\WinGet\Packages")) {

        if (-not $root -or -not (Test-Path $root)) { continue }

        $found = Get-ChildItem $root -Recurse -Filter "oscdimg.exe" -ErrorAction SilentlyContinue |
                 Select-Object -First 1 -ExpandProperty FullName
        if ($found) { return $found }
    }

    foreach ($link in @(
            "$env:LOCALAPPDATA\Microsoft\WinGet\Links\oscdimg.exe",
            "$env:ProgramFiles\WinGet\Links\oscdimg.exe")) {
        if ($link -and (Test-Path -LiteralPath $link)) { return $link }
    }

    return $null
}

function Get-WinUtilOscdimgPath {
    <#
    .SYNOPSIS
        Retorna o caminho do oscdimg.exe, instalando-o via winget quando ele estiver ausente.
    #>

    $oscdimg = Find-WinUtilOscdimg
    if ($oscdimg) { return $oscdimg }

    Write-WinUtilISOLog "oscdimg.exe não encontrado. Tentando instalar via winget..."
    try {
        # Primeiro, garante que o winget esteja instalado e funcionando
        Install-WinUtilWinget

        $winget = Get-Command winget
        $result = & $winget install -e --id Microsoft.OSCDIMG --accept-package-agreements --accept-source-agreements
        Write-WinUtilISOLog "Saída do winget: $result"

        # A mesma busca feita antes da instalação: o winget respeita o escopo e a raiz de pacotes
        # configurados, então o arquivo não necessariamente fica no diretório de pacotes por usuário
        $oscdimg = Find-WinUtilOscdimg
    } catch {
        Write-WinUtilISOLog -Level "WARN" -Message "winget não disponível ou falha na instalação: $_"
    }

    if ($oscdimg) {
        Write-WinUtilISOLog "oscdimg.exe instalado com sucesso."
    } else {
        # O chamador da exportação transforma isso em um erro terminal contabilizado. Mantenha este
        # contexto visível sem registrar o mesmo executável ausente como um segundo erro.
        Write-WinUtilISOLog -Level "WARN" -Message "oscdimg.exe ainda não encontrado após a tentativa de instalação."
    }
    return $oscdimg
}
