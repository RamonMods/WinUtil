function Invoke-WinUtilISORefreshUSBDrives {
    $combo    = $sync["WPFWin11ISOUSBDriveComboBox"]
    $removable = @(Get-Disk | Where-Object { $_.BusType -eq "USB" } | Sort-Object Number)

    $combo.Items.Clear()

    if ($removable.Count -eq 0) {
        $combo.Items.Add("Nenhuma unidade USB detectada.")
        $combo.SelectedIndex = 0
        $sync["Win11ISOUSBDisks"] = @()
        Write-WinUtilISOLog "Nenhuma unidade USB detectada."
        return
    }

    foreach ($disk in $removable) {
        $sizeGB = [math]::Round($disk.Size / 1GB, 1)
        $combo.Items.Add("Disk $($disk.Number): $($disk.FriendlyName)  [$sizeGB GB] - $($disk.PartitionStyle)")
    }
    $combo.SelectedIndex = 0
    Write-WinUtilISOLog "Encontrada(s) $($removable.Count) unidade(s) USB."
    $sync["Win11ISOUSBDisks"] = $removable
}

function Get-WinUtilFreeDriveLetter {
    <#
    .SYNOPSIS
        Retorna a primeira letra de unidade não usada entre D e Z, ou $null quando não houver nenhuma.
    #>

    $used = (Get-PSDrive -PSProvider FileSystem).Name
    foreach ($c in [char[]](68..90)) {
        if ($used -notcontains [string]$c) { return $c }
    }
    return $null
}

function Invoke-WinUtilISOWriteUSB {
    $contentsDir = $sync["Win11ISOContentsDir"]
    $usbDisks    = $sync["Win11ISOUSBDisks"]

    if (-not $contentsDir -or -not (Test-Path $contentsDir)) {
        Show-WinUtilMessage -Message "Nenhum conteúdo de ISO modificado encontrado. Execute a etapa de modificação primeiro." -Title "Não Pronto" -Button "OK" -Icon "Warning" | Out-Null
        return
    }

    $installEsd = Join-Path $contentsDir "sources\install.esd"
    if (Test-Path $installEsd) {
        $esdSizeBytes = (Get-Item $installEsd).Length
        if ($esdSizeBytes -ge 4GB) {
            $esdSizeMB = [math]::Ceiling($esdSizeBytes / 1MB)
            Show-WinUtilMessage -Message "Esta ISO usa um arquivo install.esd de $esdSizeMB MB. O formato FAT32 para USB do WinUtil não comporta arquivos maiores que 4 GB.`n`nExporte uma ISO em vez disso ou use uma mídia com install.wim." -Title "Criação de USB Não Suportada" -Button "OK" -Icon "Warning" | Out-Null
            return
        }
    }

    $combo = $sync["WPFWin11ISOUSBDriveComboBox"]
    $selectedIndex = $combo.SelectedIndex
    $selectedItemText = [string]$combo.SelectedItem
    $usbDisks = @($usbDisks)

    $targetDisk = $null
    if ($selectedIndex -ge 0 -and $selectedIndex -lt $usbDisks.Count) {
        $targetDisk = $usbDisks[$selectedIndex]
    } elseif ($selectedItemText -match 'Disk\s+(\d+):') {
        $selectedDiskNum = [int]$matches[1]
        $targetDisk = $usbDisks | Where-Object { $_.Number -eq $selectedDiskNum } | Select-Object -First 1
    }

    if (-not $targetDisk) {
        Show-WinUtilMessage -Message "Selecione uma unidade USB na lista suspensa." -Title "Nenhuma Unidade Selecionada" -Button "OK" -Icon "Warning" | Out-Null
        return
    }

    $diskNum = $targetDisk.Number
    $sizeGB  = [math]::Round($targetDisk.Size / 1GB, 1)

    $confirm = Show-WinUtilMessage -Message "TODOS os dados do Disco $diskNum ($($targetDisk.FriendlyName), $sizeGB GB) serão APAGADOS PERMANENTEMENTE.`n`nTem certeza de que deseja continuar?" -Title "Confirmar Apagamento da USB" -Button "YesNo" -Icon "Warning"
    if ($confirm -ne "Yes") {
        Write-WinUtilISOLog "Gravação na USB cancelada pelo usuário."
        return
    }

    Start-WinUtilJob -Name "USB write" -Description "Gravando a unidade USB" -Parameters @{
        DiskNumber  = $diskNum
        ContentsDir = $contentsDir
    } -ScriptBlock {
        param($DiskNumber, $contentsDir)

        Invoke-WPFUIThread -ScriptBlock { $sync["WPFWin11ISOWriteUSBButton"].IsEnabled = $false }
        Set-WinUtilISOStep -Step "Working" -Label "Gravando a unidade USB"

        try {
            Write-WinUtilISOLog "Iniciando a gravação na USB do Disco $DiskNumber..."
            Step-WinUtilJob -Status "Formatando a unidade USB..." -Percent 10

            # Fase 1: Limpa o disco via diskpart (tenta novamente se a unidade ainda não estiver pronta)
            $dpFile1 = Join-Path $env:TEMP "winutil_diskpart_$(Get-Random).txt"
            "select disk $DiskNumber`nclean`nexit" | Set-Content -Path $dpFile1 -Encoding ASCII
            Write-WinUtilISOLog "Executando diskpart clean no Disco $DiskNumber..."
            $dpCleanOut = diskpart /s $dpFile1
            $dpCleanOut | Where-Object { $_ -match '\S' } | ForEach-Object { Write-WinUtilISOLog "  diskpart: $_" }
            Remove-Item $dpFile1 -Force

            if (($dpCleanOut -join ' ') -match 'device is not ready') {
                Write-WinUtilISOLog "O Disco $DiskNumber não estava pronto; aguardando 5 segundos e repetindo a limpeza..."
                Start-Sleep -Seconds 5
                Update-Disk -Number $DiskNumber
                $dpFile1b = Join-Path $env:TEMP "winutil_diskpart_$(Get-Random).txt"
                "select disk $DiskNumber`nclean`nexit" | Set-Content -Path $dpFile1b -Encoding ASCII
                diskpart /s $dpFile1b | Where-Object { $_ -match '\S' } | ForEach-Object { Write-WinUtilISOLog "  diskpart: $_" }
                Remove-Item $dpFile1b -Force
            }

            # Fase 2: Inicializar como GPT
            Start-Sleep -Seconds 2
            Update-Disk -Number $DiskNumber
            $diskObj = Get-Disk -Number $DiskNumber
            if ($diskObj.PartitionStyle -eq 'RAW') {
                Initialize-Disk -Number $DiskNumber -PartitionStyle GPT
                Write-WinUtilISOLog "Disco $DiskNumber inicializado como GPT."
            } else {
                Set-Disk -Number $DiskNumber -PartitionStyle GPT
                Write-WinUtilISOLog "Disco $DiskNumber convertido para GPT (antes era $($diskObj.PartitionStyle))."
            }

            # Fase 3: Cria a partição FAT32 via diskpart e depois formata com Format-Volume
            # (o comando 'format' do diskpart pode falhar com "no volume selected" em unidades novas/nunca formatadas)
            $volLabel = "W11-" + (Get-Date).ToString('yyMMdd')
            $dpFile2  = Join-Path $env:TEMP "winutil_diskpart2_$(Get-Random).txt"
            $maxFat32PartitionMB = 32768
            $diskSizeMB = [int][Math]::Floor((Get-Disk -Number $DiskNumber).Size / 1MB)
            $createPartitionCommand = "create partition primary"
            if ($diskSizeMB -gt $maxFat32PartitionMB) {
                $createPartitionCommand = "create partition primary size=$maxFat32PartitionMB"
                Write-WinUtilISOLog "O Disco $DiskNumber tem $diskSizeMB MB; criando partição FAT32 limitada a $maxFat32PartitionMB MB (32 GB)."
            }

            @(
                "select disk $DiskNumber"
                $createPartitionCommand
                "exit"
            ) | Set-Content -Path $dpFile2 -Encoding ASCII
            Write-WinUtilISOLog "Criando partições no Disco $DiskNumber..."
            diskpart /s $dpFile2 | Where-Object { $_ -match '\S' } | ForEach-Object { Write-WinUtilISOLog "  diskpart: $_" }
            Remove-Item $dpFile2 -Force

            Step-WinUtilJob -Status "Formatando a partição USB..." -Percent 25
            Start-Sleep -Seconds 3
            Update-Disk -Number $DiskNumber

            $partitions = Get-Partition -DiskNumber $DiskNumber
            Write-WinUtilISOLog "Partições no Disco $DiskNumber após a criação: $($partitions.Count)"
            foreach ($p in $partitions) {
                Write-WinUtilISOLog "  Partição $($p.PartitionNumber)  Tipo=$($p.Type)  Letra=$($p.DriveLetter)  Tamanho=$([math]::Round($p.Size/1MB))MB"
            }

            $winpePart = $partitions | Where-Object { $_.Type -eq "Basic" } | Select-Object -Last 1
            if (-not $winpePart) {
                throw "Não foi possível encontrar a partição Basic no Disco $DiskNumber após a criação."
            }

            # Formata com Format-Volume (confiável em unidades novas; o format do diskpart falha
            # com 'no volume selected' quando a partição nunca foi formatada antes)
            Write-WinUtilISOLog "Formatando a Partição $($winpePart.PartitionNumber) como FAT32 (rótulo: $volLabel)..."
            Get-Partition -DiskNumber $DiskNumber -PartitionNumber $winpePart.PartitionNumber |
                Format-Volume -FileSystem FAT32 -NewFileSystemLabel $volLabel -Force -Confirm:$false
            Write-WinUtilISOLog "Partição $($winpePart.PartitionNumber) formatada como FAT32."

            Step-WinUtilJob -Status "Atribuindo letras de unidade..." -Percent 30
            Start-Sleep -Seconds 2
            Update-Disk -Number $DiskNumber

            try { Remove-PartitionAccessPath -DiskNumber $DiskNumber -PartitionNumber $winpePart.PartitionNumber -AccessPath "$($winpePart.DriveLetter):" } catch { Write-WinUtilISOLog -Level "WARN" -Message "Não foi possível remover o caminho de acesso da partição existente: $_" }
            $usbLetter = Get-WinUtilFreeDriveLetter
            if (-not $usbLetter) { throw "Não há letras de unidade livres (D-Z) para atribuir à partição de dados da USB." }
            Set-Partition -DiskNumber $DiskNumber -PartitionNumber $winpePart.PartitionNumber -NewDriveLetter $usbLetter
            Write-WinUtilISOLog "Letra de unidade $usbLetter atribuída à partição WINPE (Partição $($winpePart.PartitionNumber))."
            Start-Sleep -Seconds 2

            $usbDrive = "${usbLetter}:"
            $retries = 0
            while (-not (Test-Path $usbDrive) -and $retries -lt 6) {
                $retries++
                Write-WinUtilISOLog "Aguardando $usbDrive ficar acessível (tentativa $retries/6)..."
                Start-Sleep -Seconds 2
            }
            if (-not (Test-Path $usbDrive)) { throw "A unidade $usbDrive não está acessível após a atribuição da letra." }
            Write-WinUtilISOLog "Partição de dados da USB: $usbDrive"

            $contentSizeBytes = (Get-ChildItem -LiteralPath $contentsDir -File -Recurse -Force | Measure-Object -Property Length -Sum).Sum
            if (-not $contentSizeBytes) { $contentSizeBytes = 0 }
            $usbVolume = Get-Volume -DriveLetter $usbLetter
            $partitionCapacityBytes = [int64]$usbVolume.Size
            $partitionFreeBytes = [int64]$usbVolume.SizeRemaining

            $contentSizeGB = [math]::Round($contentSizeBytes / 1GB, 2)
            $partitionCapacityGB = [math]::Round($partitionCapacityBytes / 1GB, 2)
            $partitionFreeGB = [math]::Round($partitionFreeBytes / 1GB, 2)

            Write-WinUtilISOLog "Tamanho do conteúdo de origem: $contentSizeGB GB. Capacidade da partição da USB: $partitionCapacityGB GB, livre: $partitionFreeGB GB."

            if ($contentSizeBytes -gt $partitionCapacityBytes) {
                throw "O conteúdo da ISO ($contentSizeGB GB) é maior que a capacidade da partição da USB ($partitionCapacityGB GB). Use uma USB maior ou reduza o tamanho da imagem."
            }

            if ($contentSizeBytes -gt $partitionFreeBytes) {
                throw "Espaço livre insuficiente na partição da USB. Necessário: $contentSizeGB GB, disponível: $partitionFreeGB GB."
            }

            Step-WinUtilJob -Status "Copiando os arquivos do Windows 11 para a USB..." -Percent 45

            # Copia os arquivos; divide o install.wim se ele tiver > 4 GB (limite do FAT32)
            $installWim = Join-Path $contentsDir "sources\install.wim"
            if (Test-Path $installWim) {
                $wimSizeMB = [math]::Round((Get-Item $installWim).Length / 1MB)
                if ($wimSizeMB -gt 3800) {
                    Write-WinUtilISOLog "O install.wim tem $wimSizeMB MB - dividindo para compatibilidade com FAT32... Isso pode levar vários minutos."
                    Set-ItemProperty -LiteralPath $installWim -Name IsReadOnly -Value $false
                    $splitDest = Join-Path $usbDrive "sources\install.swm"
                    New-Item -ItemType Directory -Path (Split-Path $splitDest) -Force | Out-Null
                    Split-WindowsImage -ImagePath $installWim -SplitImagePath $splitDest -FileSize 3800 -CheckIntegrity
                    Write-WinUtilISOLog "Divisão do install.wim concluída."
                    Write-WinUtilISOLog "Copiando os arquivos restantes para a USB..."
                    Invoke-WinUtilRobocopy -Source $contentsDir -Destination $usbDrive -Arguments @("/E","/XF","install.wim","/NFL","/NDL","/NJH","/NJS")
                } else {
                    Invoke-WinUtilRobocopy -Source $contentsDir -Destination $usbDrive -Arguments @("/E","/NFL","/NDL","/NJH","/NJS")
                }
            } else {
                Invoke-WinUtilRobocopy -Source $contentsDir -Destination $usbDrive -Arguments @("/E","/NFL","/NDL","/NJH","/NJS")
            }

            Step-WinUtilJob -Status "Finalizando a unidade USB..." -Percent 90
            Write-WinUtilISOLog "Arquivos copiados para a USB."
            Step-WinUtilJob -Status "Gravação na USB concluída" -Percent 100
            Write-WinUtilISOLog "A unidade USB está pronta para uso."

            Invoke-WPFUIThread -Parameters @{ DiskNumber = $DiskNumber } -ScriptBlock {
                param($DiskNumber)

                $sync["WPFWin11ISODoneLabel"].Text = "O disco $DiskNumber está pronto para inicializar."
                $sync["WPFWin11ISODonePanel"].Visibility = "Visible"
            }
            Set-WinUtilISOStep -Step "Output"
            Show-WinUtilMessage -Message "Unidade USB criada com sucesso!`n`nAgora você pode inicializar por ela para instalar o Windows 11." -Title "USB Pronta" -Button "OK" -Icon "Info" | Out-Null
        } catch {
            Write-WinUtilISOLog -Level "ERROR" -Message "A gravação na USB falhou: $_"
            $_.Exception.Data["WinUtilErrorReported"] = $true
            Set-WinUtilISOStep -Step "Output"
            Show-WinUtilMessage -Message "Falha na gravação da USB:`n`n$_" -Title "Erro de Gravação na USB" -Button "OK" -Icon "Error" | Out-Null
            throw
        } finally {
            Invoke-WPFUIThread -ScriptBlock {
                $sync["WPFWin11ISOWriteUSBButton"].IsEnabled = $true

                # O cancelamento ignora o catch, então a página de trabalho pode ainda estar ativa aqui
                if ($sync["WPFWin11ISOWorkingSection"].IsSelected) {
                    Set-WinUtilISOStep -Step "Output"
                }
            }
        }
    }
}
