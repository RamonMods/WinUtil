function Invoke-WinUtilISOScript {
    <#
    .SYNOPSIS
        Prepara a mídia de instalação do Windows copiada sem modificar sua imagem de instalação.

    .DESCRIPTION
        Prepara a remoção de AppX, os ajustes de registro e a limpeza de tarefas agendadas do WinUtil
        no arquivo de resposta para o primeiro logon, grava sources\ei.cfg para a edição
        selecionada e, opcionalmente, adiciona drivers do sistema atual ao boot.wim índice 2 e
        a um índice do install.wim.

    .PARAMETER ISOContentsDir
        Diretório raiz do conteúdo da ISO copiada.

    .PARAMETER AutoUnattendXml
        Conteúdo XML completo do autounattend.xml.

    .PARAMETER InstallEditionId
        EditionID de instalação do Windows para sources\ei.cfg, por exemplo Professional ou Core.

    .PARAMETER InstallImagePath
        install.wim copiado a ser servido quando a injeção de drivers do sistema atual estiver habilitada.

    .PARAMETER InstallImageIndex
        Índice da edição selecionada no install.wim.

    .PARAMETER Log
        ScriptBlock opcional para registro de progresso/status. Recebe um único argumento [string].

    .PARAMETER DriversInjected
        [ref] opcional definido como $true somente se a injeção de drivers realmente montou e confirmou
        o install.wim; permanece $false se a injeção foi ignorada ou nenhum pacote foi adicionado com sucesso.
    #>
    param (
        [Parameter(Mandatory)][string]$ISOContentsDir,
        [string]$AutoUnattendXml = "",
        [bool]$InjectCurrentSystemDrivers = $false,
        [string]$InstallEditionId = "",
        [string]$InstallImagePath = "",
        [int]$InstallImageIndex = 1,
        [scriptblock]$Log = { param($m) Write-Output $m },
        [ref]$DriversInjected = [ref]$false
    )

    function Add-WinUtilISOStagedDrivers {
        param (
            [Parameter(Mandatory)][string]$ContentRoot,
            [Parameter(Mandatory)][string]$InstallImagePath,
            [Parameter(Mandatory)][int]$InstallImageIndex,
            [scriptblock]$Logger,
            [ref]$DriversInjected = [ref]$false
        )
        $DriversInjected.Value = $false

        function Test-WinUtilISOStorageDriver {
            param ([Parameter(Mandatory)][System.IO.FileInfo]$InfFile)

            try {
                return (Get-Content -LiteralPath $InfFile.FullName -Raw -ErrorAction Stop) -match '(?im)^\s*Class\s*=\s*(SCSIAdapter|HDC)\s*(?:;.*)?$'
            } catch {
                & $Logger "Warning: não foi possível classificar o driver de armazenamento '$($InfFile.FullName)': $_"
                return $false
            }
        }

        function Get-WinUtilISODriverPackageVersion {
            param ([Parameter(Mandatory)][System.IO.FileInfo]$InfFile)

            try {
                $infText = Get-Content -LiteralPath $InfFile.FullName -Raw -ErrorAction Stop
            } catch {
                $null = & $Logger "Warning: não foi possível ler '$($InfFile.FullName)' para determinar a versão do driver: $_"
                return $null
            }

            # O componente de versão do DriverVer é opcional conforme a especificação INF (entradas
            # somente com data são válidas); trate uma versão ausente como 0.0 para que essas entradas ainda sejam
            # classificadas corretamente, em vez de descartadas como ilegíveis.
            $match = [regex]::Match($infText, '(?im)^\s*DriverVer\s*=\s*(?<date>\d{1,2}/\d{1,2}/\d{4})\s*(?:,\s*(?<version>\d+(?:\.\d+){0,3}))?\s*(?:;.*)?$')
            if (-not $match.Success) {
                return $null
            }

            try {
                $date = [datetime]::ParseExact($match.Groups['date'].Value, 'M/d/yyyy', [System.Globalization.CultureInfo]::InvariantCulture)
                $versionText = if ($match.Groups['version'].Success) { $match.Groups['version'].Value } else { '0' }
                if (($versionText.Split('.')).Count -lt 2) {
                    $versionText = "$versionText.0"
                }
                $version = [version]$versionText
            } catch {
                $null = & $Logger "Warning: não foi possível interpretar o DriverVer '$($match.Value.Trim())' em '$($InfFile.FullName)': $_"
                return $null
            }

            return [pscustomobject]@{
                Date    = $date
                Version = $version
                Raw     = if ($match.Groups['version'].Success) { "$($match.Groups['date'].Value),$($match.Groups['version'].Value)" } else { $match.Groups['date'].Value }
            }
        }

        function Get-WinUtilISODriverProvider {
            param ([Parameter(Mandatory)][System.IO.FileInfo]$InfFile)

            try {
                $infText = Get-Content -LiteralPath $InfFile.FullName -Raw -ErrorAction Stop
            } catch {
                $null = & $Logger "Warning: não foi possível ler '$($InfFile.FullName)' para determinar seu fornecedor: $_"
                return ''
            }

            $match = [regex]::Match($infText, '(?im)^\s*Provider\s*=\s*(?<provider>.+?)\s*(?:;.*)?$')
            if (-not $match.Success) {
                return ''
            }
            return $match.Groups['provider'].Value.ToLowerInvariant()
        }

        function Select-WinUtilISOStagedDriverPackages {
            param (
                [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$DriverFolderGroups,
                [scriptblock]$Logger
            )

            $survivingFolders = [System.Collections.Generic.List[string]]::new()
            $dedupGroups = @{}

            foreach ($driverFolderGroup in $DriverFolderGroups) {
                $driverFolder = [string]$driverFolderGroup.Name

                # O DISM nomeia as pastas de pacotes exportados como <infname>_<arch>_<hash>; agrupar por infname+arch
                # (sem o hash) é o que nos permite reconhecer duas exportações do mesmo driver. Quando uma
                # pasta não corresponde a esse padrão, use o caminho completo em vez do nome final:
                # duas pastas sem relação em níveis diferentes (ex.: group_a\duplicate e group_b\duplicate)
                # podem ter o mesmo nome final, e o caminho completo é garantidamente único por grupo.
                $leafName = Split-Path -Path $driverFolder -Leaf
                $dedupKey = $driverFolder
                $nameMatch = [regex]::Match($leafName, '(?i)^(?<infname>.+)_(?<arch>x86|amd64|arm64|arm|wow)_[0-9a-f]{16}$')
                if ($nameMatch.Success) {
                    $provider = Get-WinUtilISODriverProvider -InfFile $driverFolderGroup.Group[0]
                    $dedupKey = "$($nameMatch.Groups['infname'].Value.ToLowerInvariant())_$($nameMatch.Groups['arch'].Value.ToLowerInvariant())_$provider"
                }

                if (-not $dedupGroups.ContainsKey($dedupKey)) {
                    $dedupGroups[$dedupKey] = [System.Collections.Generic.List[object]]::new()
                }
                $dedupGroups[$dedupKey].Add($driverFolderGroup)
            }

            foreach ($dedupKey in $dedupGroups.Keys) {
                $candidates = $dedupGroups[$dedupKey]
                if ($candidates.Count -eq 1) {
                    $survivingFolders.Add([string]$candidates[0].Name)
                    continue
                }

                $ranked = @($candidates | ForEach-Object {
                    $primaryVersion = ($_.Group | ForEach-Object { Get-WinUtilISODriverPackageVersion -InfFile $_ } | Where-Object { $_ }) |
                        Sort-Object -Property Date, Version -Descending | Select-Object -First 1
                    [pscustomobject]@{ Folder = [string]$_.Name; Version = $primaryVersion }
                })

                $withVersion = @($ranked | Where-Object { $_.Version })
                if ($withVersion.Count -eq 0) {
                    $null = & $Logger "Warning: não foi possível determinar o DriverVer de nenhuma duplicata de '$dedupKey'; mantendo todos os $($ranked.Count) pacote(s) em vez de adivinhar."
                    foreach ($candidate in $ranked) {
                        $survivingFolders.Add($candidate.Folder)
                    }
                    continue
                }

                $kept = $withVersion | Sort-Object -Property @{ Expression = { $_.Version.Date } }, @{ Expression = { $_.Version.Version } } -Descending | Select-Object -First 1
                $survivingFolders.Add($kept.Folder)

                foreach ($candidate in $ranked) {
                    if ($candidate.Folder -eq $kept.Folder) {
                        continue
                    }
                    $droppedVersion = if ($candidate.Version) { $candidate.Version.Raw } else { 'desconhecida' }
                    $null = & $Logger "Excluindo o pacote de driver duplicado e desatualizado '$($candidate.Folder)' (DriverVer $droppedVersion), substituído por '$($kept.Folder)' (DriverVer $($kept.Version.Raw))."
                }
            }

            return @($survivingFolders)
        }

        $knownExitCode = @{
            112 = "Disco cheio"
            5 = "Acesso negado"
            2 = "Arquivo não encontrado"
            3 = "Caminho não encontrado"
            87 = "Parâmetro inválido"
            1168 = "Elemento não encontrado"
            1392 = "Arquivo ou diretório corrompido"
            32 = "Arquivo em uso / violação de compartilhamento"
            21 = "Dispositivo não pronto"
            1460 = "Tempo limite da operação"
            1223 = "Operação cancelada pelo usuário"
            50 = "Solicitação não suportada"
        }

        function Invoke-WinUtilISODism {
            param (
                [Parameter(Mandatory)][string[]]$Arguments,
                [Parameter(Mandatory)][string]$Operation
            )

            $output = @(& dism.exe @Arguments 2>&1)
            $exitCode = $LASTEXITCODE
            if ($exitCode -ne 0) {
                foreach ($line in @($output | Select-Object -Last 20)) {
                    if (-not [string]::IsNullOrWhiteSpace([string]$line)) {
                        & $Logger "  dism[$Operation]: $line"
                    }
                }
                if ($knownExitCode.ContainsKey($exitCode)) {
                    throw "DISM $Operation falhou com o código de saída $exitCode ($($knownExitCode[$exitCode]))."
                } else {
                    throw "DISM $Operation falhou com o código de saída $exitCode."
                }
            }
            if ($Operation -ne 'metadata') {
                & $Logger "DISM $Operation concluído."
            }
            return $output
        }

        function Get-WinUtilISOWimMetadata {
            param ([Parameter(Mandatory)][string]$ImagePath, [Parameter(Mandatory)][int]$Index)

            $metadata = @{}
            $output = Invoke-WinUtilISODism -Arguments @('/English', '/Get-WimInfo', "/WimFile:$ImagePath", "/Index:$Index") -Operation 'metadata'
            foreach ($line in $output) {
                if ([string]$line -match '^\s*([^:]+?)\s*:\s*(.*?)\s*$') {
                    $metadata[$Matches[1].Trim()] = $Matches[2].Trim()
                }
            }
            return $metadata
        }

        function Assert-WinUtilISOWimMetadata {
            param (
                [Parameter(Mandatory)][hashtable]$Before,
                [hashtable]$After
            )

            foreach ($key in 'Languages', 'Installation', 'Edition', 'ProductSuite', 'ProductType') {
                $beforeValue = [string]$Before[$key]
                if ($beforeValue -eq '<undefined>' -or ($key -in 'Installation', 'Edition', 'ProductType' -and [string]::IsNullOrWhiteSpace($beforeValue))) {
                    throw "Os metadados do install.wim já são inválidos: $key não está definido. A injeção de drivers não foi tentada."
                }
                if ($After) {
                    $afterValue = [string]$After[$key]
                    if ($afterValue -eq '<undefined>' -or ($beforeValue -and $afterValue -ne $beforeValue)) {
                        throw "A validação dos metadados do install.wim falhou após a injeção de drivers: $key mudou de '$beforeValue' para '$afterValue'."
                    }
                }
            }
        }

        function Test-WinUtilISOMountedImage {
            param ([Parameter(Mandatory)][string]$Path)

            return @(& dism.exe /English /Get-MountedImageInfo 2>$null) -match [regex]::Escape($Path)
        }

        function Get-WinUtilISODriverFolderName {
            param ([Parameter(Mandatory)][string]$DriverFolder)

            if ($DriverFolder.StartsWith($driverExportRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
                return $DriverFolder.Substring($driverExportRoot.Length).TrimStart('\')
            }
            return $DriverFolder
        }

        function Get-WinUtilISORootDriverFolders {
            param ([Parameter(Mandatory)][AllowEmptyCollection()][string[]]$DriverFolders)

            return @($DriverFolders | Where-Object {
                $candidate = $_
                -not ($DriverFolders | Where-Object { $candidate.StartsWith("$_\", [System.StringComparison]::OrdinalIgnoreCase) })
            })
        }

        function Add-WinUtilISODriversToImage {
            param (
                [Parameter(Mandatory)][string]$ImagePath,
                [Parameter(Mandatory)][int]$ImageIndex,
                [Parameter(Mandatory)][string]$MountDir,
                [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$DriverFolders,
                [Parameter(Mandatory)][string]$ImageLabel,
                [Parameter(Mandatory)][ref]$ImageMounted
            )

            if ($DriverFolders.Count -eq 0) {
                & $Logger "Nenhum pacote de driver a adicionar a ${ImageLabel}."
                return 0
            }

            Set-ItemProperty -LiteralPath $ImagePath -Name IsReadOnly -Value $false
            New-Item -Path $MountDir -ItemType Directory -Force | Out-Null

            $remainingDriverFolders = @($DriverFolders)
            while ($remainingDriverFolders.Count -gt 0) {
                & $Logger "Montando $ImageLabel índice $ImageIndex para injeção de drivers..."
                Invoke-WinUtilISODism -Arguments @('/English', '/Mount-Image', "/ImageFile:$ImagePath", "/Index:$ImageIndex", "/MountDir:$MountDir") -Operation 'mount' | Out-Null
                $ImageMounted.Value = $true

                $failedDriverFolder = $null
                $driverName = $null
                foreach ($driverFolder in $remainingDriverFolders) {
                    $driverName = Get-WinUtilISODriverFolderName -DriverFolder $driverFolder
                    try {
                        Invoke-WinUtilISODism -Arguments @('/English', "/Image:$MountDir", '/Add-Driver', "/Driver:$driverFolder", '/Recurse') -Operation "add-driver:$driverName" | Out-Null
                    } catch {
                        & $Logger "Warning: falha ao adicionar o pacote de driver '$driverName': $_"
                        $failedDriverFolder = $driverFolder
                        break
                    }
                }

                if (-not $failedDriverFolder) {
                    break
                }

                & $Logger "Descartando a montagem potencialmente parcial de $ImageLabel antes de continuar sem '$driverName'."
                try {
                    Invoke-WinUtilISODism -Arguments @('/English', '/Unmount-Image', "/MountDir:$MountDir", '/Discard') -Operation 'discard' | Out-Null
                    $ImageMounted.Value = $false
                } catch {
                    throw "Falha ao descartar a montagem potencialmente parcial de $ImageLabel após a falha do pacote de driver '$driverName': $_"
                }

                $remainingDriverFolders = @($remainingDriverFolders | Where-Object { $_ -ne $failedDriverFolder })
            }

            $addedCount = $remainingDriverFolders.Count
            if ($addedCount -eq 0) {
                if ($ImageLabel -eq 'install.wim') {
                    & $Logger "Warning: nenhum dos $($DriverFolders.Count) pacotes de driver exportados pôde ser adicionado; continuando com um install.wim não modificado."
                } else {
                    & $Logger "Warning: nenhum dos $($DriverFolders.Count) pacotes de driver pôde ser adicionado a ${ImageLabel}."
                }
                return 0
            }

            & $Logger "Adicionados $addedCount de $($DriverFolders.Count) pacotes de driver a ${ImageLabel}."
            & $Logger "Confirmando a alteração somente de drivers em $ImageLabel..."
            Invoke-WinUtilISODism -Arguments @('/English', '/Unmount-Image', "/MountDir:$MountDir", '/Commit') -Operation 'commit' | Out-Null
            $ImageMounted.Value = $false
            return $addedCount
        }

        if ([IO.Path]::GetExtension($InstallImagePath) -ne '.wim') {
            throw 'A injeção de drivers do sistema atual requer install.wim; install.esd não pode ser servido no local.'
        }
        if (-not (Test-Path -LiteralPath $InstallImagePath)) {
            throw "install.wim não foi encontrado: $InstallImagePath"
        }
        if ($InstallImageIndex -lt 1) {
            throw 'A injeção de drivers do sistema atual requer um índice de imagem válido no install.wim.'
        }

        $driverExportRoot = Join-Path $env:TEMP "WinUtil_DriverExport_$(Get-Date -Format 'yyyyMMdd_HHmmss')_$(([guid]::NewGuid()).ToString('N').Substring(0, 8))"
        $mountDir = Join-Path (Split-Path -Path $ContentRoot -Parent) 'wim_mount'
        New-Item -Path $driverExportRoot -ItemType Directory -Force | Out-Null

        # %TEMP% pode ser um alias 8.3, mas o Get-ChildItem abaixo relata caminhos longos, então as
        # pastas exportadas não compartilhariam este prefixo a menos que ele seja expandido primeiro.
        $driverExportRoot = (Get-Item -LiteralPath $driverExportRoot).FullName
        $imageMounted = $false

        try {
            & $Logger "Exportando os drivers do sistema atual antes da injeção de drivers no WIM..."
            $dismLog = Join-Path $env:TEMP "WinUtil_DismDriverExport_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
            Invoke-WinUtilISODism -Arguments @('/English', '/Online', '/Export-Driver', "/Destination:$driverExportRoot", "/LogPath:$dismLog") -Operation 'export-driver' | Out-Null

            $driverInfs = @(Get-ChildItem -LiteralPath $driverExportRoot -Filter '*.inf' -Recurse -File)
            if ($driverInfs.Count -eq 0) {
                throw 'O DISM não exportou nenhum arquivo INF de driver.'
            }
            $driverFolders = @($driverInfs | Group-Object { $_.Directory.FullName })
            $stagedDriverFolders = @(Select-WinUtilISOStagedDriverPackages -DriverFolderGroups $driverFolders -Logger $Logger)
            $metadataBefore = Get-WinUtilISOWimMetadata -ImagePath $InstallImagePath -Index $InstallImageIndex
            Assert-WinUtilISOWimMetadata -Before $metadataBefore

            $excludedDriverFolderGroups = @($driverFolders | Where-Object { $_.Name -notin $stagedDriverFolders })
            foreach ($excludedDriverFolderGroup in $excludedDriverFolderGroups) {
                $excludedFolder = [string]$excludedDriverFolderGroup.Name
                $hasRetainedDescendant = [bool]@($stagedDriverFolders | Where-Object {
                    $_.StartsWith("$excludedFolder\", [System.StringComparison]::OrdinalIgnoreCase)
                }).Count
                if ($hasRetainedDescendant) {
                    try {
                        foreach ($excludedInf in $excludedDriverFolderGroup.Group) {
                            Remove-Item -LiteralPath $excludedInf.FullName -Force -ErrorAction Stop
                        }
                    } catch {
                        throw "Falha ao remover os arquivos INF de driver excluídos do pacote '$excludedFolder' antes da injeção: $_"
                    }

                    & $Logger "Mantendo o diretório do pacote de driver excluído '$excludedFolder' porque ele contém um pacote aninhado retido, após remover seus arquivos INF excluídos."
                    continue
                }

                try {
                    Remove-Item -LiteralPath $excludedFolder -Recurse -Force -ErrorAction Stop
                } catch {
                    throw "Falha ao remover o pacote de driver excluído '$excludedFolder' antes da injeção: $_"
                }
            }

            & $Logger "Exportados $($stagedDriverFolders.Count) de $($driverFolders.Count) pacotes de driver ($($excludedDriverFolderGroups.Count) excluídos)."

            # Os drivers de armazenamento para a Instalação vêm do mesmo conjunto sobrevivente do install.wim, então
            # duplicatas desatualizadas nunca chegam ao boot.wim.
            $storageFolders = @(
                $driverFolders |
                    Where-Object { $_.Name -in $stagedDriverFolders } |
                    Where-Object { @($_.Group | Where-Object { Test-WinUtilISOStorageDriver -InfFile $_ }).Count -gt 0 } |
                    ForEach-Object { [string]$_.Name }
            )
            $storageRootFolders = @(Get-WinUtilISORootDriverFolders -DriverFolders $storageFolders)
            $rootPackageFolders = @(Get-WinUtilISORootDriverFolders -DriverFolders $stagedDriverFolders)
            $imageMountedRef = [ref]$imageMounted

            $bootWim = Join-Path $ContentRoot 'sources\boot.wim'
            if ($storageRootFolders.Count -gt 0) {
                if (Test-Path -LiteralPath $bootWim) {
                    & $Logger "Adicionando $($storageRootFolders.Count) pacotes de driver de armazenamento raiz ao boot.wim."
                    $null = Add-WinUtilISODriversToImage -ImagePath $bootWim -ImageIndex 2 -MountDir $mountDir -DriverFolders $storageRootFolders -ImageLabel 'boot.wim' -ImageMounted $imageMountedRef
                } else {
                    & $Logger 'Warning: boot.wim não foi encontrado; a Instalação do Windows não terá drivers de armazenamento injetados.'
                }
            }

            & $Logger "Adicionando $($rootPackageFolders.Count) pacotes de driver raiz ao install.wim."
            $addedCount = Add-WinUtilISODriversToImage -ImagePath $InstallImagePath -ImageIndex $InstallImageIndex -MountDir $mountDir -DriverFolders $rootPackageFolders -ImageLabel 'install.wim' -ImageMounted $imageMountedRef
            if ($addedCount -gt 0) {
                $metadataAfter = Get-WinUtilISOWimMetadata -ImagePath $InstallImagePath -Index $InstallImageIndex
                Assert-WinUtilISOWimMetadata -Before $metadataBefore -After $metadataAfter
                & $Logger 'Injeção de drivers concluída; a validação dos metadados do install.wim passou.'
                $DriversInjected.Value = $true
            }
        } finally {
            if ($imageMounted -or (Test-WinUtilISOMountedImage -Path $mountDir)) {
                try {
                    Invoke-WinUtilISODism -Arguments @('/English', '/Unmount-Image', "/MountDir:$mountDir", '/Discard') -Operation 'discard' | Out-Null
                } catch {
                    & $Logger "Warning: não foi possível descartar a montagem falha do WIM: $_"
                }
            }
            Remove-Item -LiteralPath $mountDir -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $driverExportRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    function Write-WinUtilISOEditionConfig {
        param (
            [Parameter(Mandatory)][string]$ContentRoot,
            [string]$EditionId,
            [scriptblock]$Logger
        )

        $sourcesDir = Join-Path $ContentRoot "sources"
        New-Item -Path $sourcesDir -ItemType Directory -Force | Out-Null

        $pidPath = Join-Path $sourcesDir "PID.txt"
        if (Test-Path $pidPath) {
            Remove-Item -Path $pidPath -Force
            & $Logger "Removido sources\PID.txt para que a instalação não force uma chave de produto desatualizada ou incompatível."
        }

        if ([string]::IsNullOrWhiteSpace($EditionId)) {
            & $Logger "Warning: o ID da edição selecionada é desconhecido - ignorando o fallback de sources\ei.cfg."
            return
        }

        $eiCfgPath = Join-Path $sourcesDir "ei.cfg"
        $eiCfg = @"
[EditionID]
$EditionId
[Channel]
Retail
[VL]
0
"@.Trim()

        Set-Content -Path $eiCfgPath -Value $eiCfg -Encoding ASCII -Force
        & $Logger "Gravado sources\ei.cfg para o EditionID '$EditionId'."
    }

    function Add-WinUtilISOSetupCustomizations {
        param (
            [Parameter(Mandatory)][string]$XmlContent,
            [Parameter(Mandatory)][int]$InstallImageIndex,
            [scriptblock]$Logger
        )

        $appxPackages = @(
            'Clipchamp.Clipchamp', 'Microsoft.BingNews', 'Microsoft.BingSearch',
            'Microsoft.BingWeather', 'Microsoft.GetHelp', 'Microsoft.MicrosoftOfficeHub',
            'Microsoft.MicrosoftSolitaireCollection', 'Microsoft.MicrosoftStickyNotes',
            'Microsoft.OutlookForWindows', 'Microsoft.Paint', 'Microsoft.PowerAutomateDesktop',
            'Microsoft.StartExperiencesApp', 'Microsoft.Todos', 'Microsoft.Windows.DevHome',
            'Microsoft.WindowsFeedbackHub', 'Microsoft.WindowsSoundRecorder',
            'Microsoft.ZuneMusic', 'MicrosoftCorporationII.QuickAssist', 'MSTeams'
        )

        $appxList = ($appxPackages | ForEach-Object { "    '$_'" }) -join "`r`n"
        $postInstallScript = @"
`$ErrorActionPreference = 'Continue'
`$logPath = 'C:\Windows\Setup\Scripts\WinUtil-PostInstall.log'
Start-Transcript -Path `$logPath -Append -ErrorAction SilentlyContinue

try {
    Write-Host 'WinUtil: Removendo pacotes AppX provisionados...'
    `$packages = @(
$appxList
    )
    foreach (`$package in `$packages) {
        Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
            Where-Object { `$_.DisplayName -like "*`$package*" } |
            ForEach-Object { Remove-AppxProvisionedPackage -Online -PackageName `$_.PackageName -ErrorAction SilentlyContinue | Out-Null }
        Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue |
            Where-Object { `$_.Name -like "*`$package*" } |
            ForEach-Object { Remove-AppxPackage -AllUsers -Package `$_.PackageFullName -ErrorAction SilentlyContinue | Out-Null }
    }

    function Set-WinUtilRegistryValue([string]`$Path, [string]`$Name, [string]`$Type, [string]`$Value) {
        reg.exe add `$Path /v `$Name /t `$Type /d `$Value /f 2>&1 | Out-Null
    }

    function Set-WinUtilContentDeliveryManagerValues([string]`$HiveRoot) {
        `$contentDeliveryManager = "`$HiveRoot\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
        Set-WinUtilRegistryValue `$contentDeliveryManager 'OemPreInstalledAppsEnabled' 'REG_DWORD' '0'
        Set-WinUtilRegistryValue `$contentDeliveryManager 'PreInstalledAppsEnabled' 'REG_DWORD' '0'
        Set-WinUtilRegistryValue `$contentDeliveryManager 'SilentInstalledAppsEnabled' 'REG_DWORD' '0'
        Set-WinUtilRegistryValue `$contentDeliveryManager 'ContentDeliveryAllowed' 'REG_DWORD' '0'
        Set-WinUtilRegistryValue `$contentDeliveryManager 'FeatureManagementEnabled' 'REG_DWORD' '0'
        Set-WinUtilRegistryValue `$contentDeliveryManager 'PreInstalledAppsEverEnabled' 'REG_DWORD' '0'
        Set-WinUtilRegistryValue `$contentDeliveryManager 'SoftLandingEnabled' 'REG_DWORD' '0'
        Set-WinUtilRegistryValue `$contentDeliveryManager 'SubscribedContentEnabled' 'REG_DWORD' '0'
        Set-WinUtilRegistryValue `$contentDeliveryManager 'SubscribedContent-310093Enabled' 'REG_DWORD' '0'
        Set-WinUtilRegistryValue `$contentDeliveryManager 'SubscribedContent-338388Enabled' 'REG_DWORD' '0'
        Set-WinUtilRegistryValue `$contentDeliveryManager 'SubscribedContent-338389Enabled' 'REG_DWORD' '0'
        Set-WinUtilRegistryValue `$contentDeliveryManager 'SubscribedContent-338393Enabled' 'REG_DWORD' '0'
        Set-WinUtilRegistryValue `$contentDeliveryManager 'SubscribedContent-353694Enabled' 'REG_DWORD' '0'
        Set-WinUtilRegistryValue `$contentDeliveryManager 'SubscribedContent-353696Enabled' 'REG_DWORD' '0'
        Set-WinUtilRegistryValue `$contentDeliveryManager 'SystemPaneSuggestionsEnabled' 'REG_DWORD' '0'
        reg.exe delete "`$contentDeliveryManager\Subscriptions" /f 2>&1 | Out-Null
        reg.exe delete "`$contentDeliveryManager\SuggestedApps" /f 2>&1 | Out-Null
    }

    Write-Host 'WinUtil: Aplicando ajustes de registro...'
    Set-WinUtilRegistryValue 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\ReserveManager' 'ShippedWithReserves' 'REG_DWORD' '0'
    Set-WinUtilRegistryValue 'HKLM\SYSTEM\CurrentControlSet\Control\BitLocker' 'PreventDeviceEncryption' 'REG_DWORD' '1'
    Set-WinUtilRegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Chat' 'ChatIcon' 'REG_DWORD' '3'
    Set-WinUtilRegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' 'REG_DWORD' '0'
    Set-WinUtilRegistryValue 'HKLM\SYSTEM\CurrentControlSet\Services\dmwappushservice' 'Start' 'REG_DWORD' '4'
    Set-WinUtilRegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 'REG_DWORD' '1'
    Set-WinUtilRegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\Edge' 'HubsSidebarEnabled' 'REG_DWORD' '0'
    Set-WinUtilRegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' 'REG_DWORD' '1'
    Set-WinUtilRegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\Teams' 'DisableInstallation' 'REG_DWORD' '1'
    Set-WinUtilRegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Mail' 'PreventRun' 'REG_DWORD' '1'
    Set-WinUtilRegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsConsumerFeatures' 'REG_DWORD' '1'
    Set-WinUtilRegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableConsumerAccountStateContent' 'REG_DWORD' '1'
    Set-WinUtilRegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableCloudOptimizedContent' 'REG_DWORD' '1'
    Set-WinUtilRegistryValue 'HKLM\SOFTWARE\Microsoft\PolicyManager\current\device\Start' 'ConfigureStartPins' 'REG_SZ' '{"pinnedList": [{}]}'
    Set-WinUtilRegistryValue 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE' 'BypassNRO' 'REG_DWORD' '1'
    Set-WinUtilRegistryValue 'HKLM\SYSTEM\Setup\LabConfig' 'BypassCPUCheck' 'REG_DWORD' '1'
    Set-WinUtilRegistryValue 'HKLM\SYSTEM\Setup\LabConfig' 'BypassRAMCheck' 'REG_DWORD' '1'
    Set-WinUtilRegistryValue 'HKLM\SYSTEM\Setup\LabConfig' 'BypassSecureBootCheck' 'REG_DWORD' '1'
    Set-WinUtilRegistryValue 'HKLM\SYSTEM\Setup\LabConfig' 'BypassStorageCheck' 'REG_DWORD' '1'
    Set-WinUtilRegistryValue 'HKLM\SYSTEM\Setup\LabConfig' 'BypassTPMCheck' 'REG_DWORD' '1'
    Set-WinUtilRegistryValue 'HKLM\SYSTEM\Setup\MoSetup' 'AllowUpgradesWithUnsupportedTPMOrCPU' 'REG_DWORD' '1'
    Set-WinUtilRegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\PushToInstall' 'DisablePushToInstall' 'REG_DWORD' '1'
    Set-WinUtilRegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\MRT' 'DontOfferThroughWUAU' 'REG_DWORD' '1'
    Set-WinUtilRegistryValue 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\UScheduler_Oobe\OutlookUpdate' 'workCompleted' 'REG_DWORD' '1'
    Set-WinUtilRegistryValue 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\UScheduler\OutlookUpdate' 'workCompleted' 'REG_DWORD' '1'
    Set-WinUtilRegistryValue 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\UScheduler\DevHomeUpdate' 'workCompleted' 'REG_DWORD' '1'
    reg.exe delete 'HKLM\SOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\OutlookUpdate' /f 2>&1 | Out-Null
    reg.exe delete 'HKLM\SOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\DevHomeUpdate' /f 2>&1 | Out-Null
    Set-WinUtilRegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' 'NoAutoUpdate' 'REG_DWORD' '1'
    Set-WinUtilRegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' 'AUOptions' 'REG_DWORD' '1'
    Set-WinUtilRegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' 'UseWUServer' 'REG_DWORD' '1'
    Set-WinUtilRegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' 'DisableWindowsUpdateAccess' 'REG_DWORD' '1'
    Set-WinUtilRegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' 'WUServer' 'REG_SZ' 'http://localhost:8080'
    Set-WinUtilRegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' 'WUStatusServer' 'REG_SZ' 'http://localhost:8080'
    Set-WinUtilRegistryValue 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\UScheduler_Oobe\WindowsUpdate' 'workCompleted' 'REG_DWORD' '1'
    reg.exe delete 'HKLM\SOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\WindowsUpdate' /f 2>&1 | Out-Null
    Set-WinUtilRegistryValue 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config' 'DODownloadMode' 'REG_DWORD' '0'
    Set-WinUtilRegistryValue 'HKLM\SYSTEM\CurrentControlSet\Services\BITS' 'Start' 'REG_DWORD' '4'
    Set-WinUtilRegistryValue 'HKLM\SYSTEM\CurrentControlSet\Services\wuauserv' 'Start' 'REG_DWORD' '4'
    Set-WinUtilRegistryValue 'HKLM\SYSTEM\CurrentControlSet\Services\UsoSvc' 'Start' 'REG_DWORD' '4'
    Set-WinUtilRegistryValue 'HKLM\SYSTEM\CurrentControlSet\Services\WaaSMedicSvc' 'Start' 'REG_DWORD' '4'

    `$defaultHive = 'HKU\WinUtilDefault'
    reg.exe load `$defaultHive 'C:\Users\Default\NTUSER.DAT' 2>&1 | Out-Null
    if (`$LASTEXITCODE -eq 0) {
        Set-WinUtilRegistryValue "`$defaultHive\Control Panel\UnsupportedHardwareNotificationCache" 'SV1' 'REG_DWORD' '0'
        Set-WinUtilRegistryValue "`$defaultHive\Control Panel\UnsupportedHardwareNotificationCache" 'SV2' 'REG_DWORD' '0'
        Set-WinUtilContentDeliveryManagerValues `$defaultHive
        Set-WinUtilRegistryValue "`$defaultHive\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" 'Enabled' 'REG_DWORD' '0'
        Set-WinUtilRegistryValue "`$defaultHive\Software\Microsoft\Windows\CurrentVersion\Privacy" 'TailoredExperiencesWithDiagnosticDataEnabled' 'REG_DWORD' '0'
        Set-WinUtilRegistryValue "`$defaultHive\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy" 'HasAccepted' 'REG_DWORD' '0'
        Set-WinUtilRegistryValue "`$defaultHive\Software\Microsoft\Input\TIPC" 'Enabled' 'REG_DWORD' '0'
        Set-WinUtilRegistryValue "`$defaultHive\Software\Microsoft\InputPersonalization" 'RestrictImplicitInkCollection' 'REG_DWORD' '1'
        Set-WinUtilRegistryValue "`$defaultHive\Software\Microsoft\InputPersonalization" 'RestrictImplicitTextCollection' 'REG_DWORD' '1'
        Set-WinUtilRegistryValue "`$defaultHive\Software\Microsoft\InputPersonalization\TrainedDataStore" 'HarvestContacts' 'REG_DWORD' '0'
        Set-WinUtilRegistryValue "`$defaultHive\Software\Microsoft\Personalization\Settings" 'AcceptedPrivacyPolicy' 'REG_DWORD' '0'
        reg.exe unload `$defaultHive 2>&1 | Out-Null
    }

    Set-WinUtilContentDeliveryManagerValues 'HKCU'
    Set-WinUtilRegistryValue 'HKCU\Control Panel\UnsupportedHardwareNotificationCache' 'SV1' 'REG_DWORD' '0'
    Set-WinUtilRegistryValue 'HKCU\Control Panel\UnsupportedHardwareNotificationCache' 'SV2' 'REG_DWORD' '0'
    Set-WinUtilRegistryValue 'HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarMn' 'REG_DWORD' '0'
    Set-WinUtilRegistryValue 'HKCU\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 'REG_DWORD' '0'
    Set-WinUtilRegistryValue 'HKCU\Software\Microsoft\Windows\CurrentVersion\Privacy' 'TailoredExperiencesWithDiagnosticDataEnabled' 'REG_DWORD' '0'
    Set-WinUtilRegistryValue 'HKCU\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy' 'HasAccepted' 'REG_DWORD' '0'
    Set-WinUtilRegistryValue 'HKCU\Software\Microsoft\Input\TIPC' 'Enabled' 'REG_DWORD' '0'
    Set-WinUtilRegistryValue 'HKCU\Software\Microsoft\InputPersonalization' 'RestrictImplicitInkCollection' 'REG_DWORD' '1'
    Set-WinUtilRegistryValue 'HKCU\Software\Microsoft\InputPersonalization' 'RestrictImplicitTextCollection' 'REG_DWORD' '1'
    Set-WinUtilRegistryValue 'HKCU\Software\Microsoft\InputPersonalization\TrainedDataStore' 'HarvestContacts' 'REG_DWORD' '0'
    Set-WinUtilRegistryValue 'HKCU\Software\Microsoft\Personalization\Settings' 'AcceptedPrivacyPolicy' 'REG_DWORD' '0'

    Write-Host 'WinUtil: Removendo definições de tarefas agendadas...'
    `$taskPaths = @(
        'C:\Windows\System32\Tasks\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser',
        'C:\Windows\System32\Tasks\Microsoft\Windows\Customer Experience Improvement Program',
        'C:\Windows\System32\Tasks\Microsoft\Windows\Application Experience\ProgramDataUpdater',
        'C:\Windows\System32\Tasks\Microsoft\Windows\Chkdsk\Proxy',
        'C:\Windows\System32\Tasks\Microsoft\Windows\Windows Error Reporting\QueueReporting',
        'C:\Windows\System32\Tasks\Microsoft\Windows\InstallService',
        'C:\Windows\System32\Tasks\Microsoft\Windows\UpdateOrchestrator',
        'C:\Windows\System32\Tasks\Microsoft\Windows\UpdateAssistant',
        'C:\Windows\System32\Tasks\Microsoft\Windows\WaaSMedic',
        'C:\Windows\System32\Tasks\Microsoft\Windows\WindowsUpdate',
        'C:\Windows\System32\Tasks\Microsoft\WindowsUpdate'
    )
    foreach (`$taskPath in `$taskPaths) { Remove-Item -LiteralPath `$taskPath -Recurse -Force -ErrorAction SilentlyContinue }

    Start-Process -FilePath 'C:\Windows\System32\OneDriveSetup.exe' -ArgumentList '/uninstall' -Wait -ErrorAction SilentlyContinue
    Write-Host 'WinUtil: Personalização pós-instalação concluída.'
} finally {
    Stop-Transcript -ErrorAction SilentlyContinue
}
"@

        $xmlDoc = [xml]::new()
        $xmlDoc.PreserveWhitespace = $true
        $xmlDoc.LoadXml($XmlContent)
        $nsMgr = New-Object System.Xml.XmlNamespaceManager($xmlDoc.NameTable)
        $nsMgr.AddNamespace('u', 'urn:schemas-microsoft-com:unattend')
        $nsMgr.AddNamespace('sg', 'https://schneegans.de/windows/unattend-generator/')

        $setupComponent = $xmlDoc.SelectSingleNode('/u:unattend/u:settings[@pass="windowsPE"]/u:component[@name="Microsoft-Windows-Setup"]', $nsMgr)
        $extensions = $xmlDoc.SelectSingleNode('//sg:Extensions', $nsMgr)
        $firstLogonFile = $xmlDoc.SelectSingleNode('//sg:File[@path="C:\Windows\Setup\Scripts\FirstLogon.ps1"]', $nsMgr)
        if (-not $setupComponent -or -not $extensions -or -not $firstLogonFile) {
            throw 'autounattend.xml está sem um nó obrigatório de Windows Setup, Extensions ou FirstLogon.ps1.'
        }

        $imageInstall = $setupComponent.SelectSingleNode('u:ImageInstall', $nsMgr)
        if (-not $imageInstall) {
            $imageInstall = $xmlDoc.CreateElement('ImageInstall', $setupComponent.NamespaceURI)
            [void]$setupComponent.AppendChild($imageInstall)
        }
        $osImage = $imageInstall.SelectSingleNode('u:OSImage', $nsMgr)
        if (-not $osImage) {
            $osImage = $xmlDoc.CreateElement('OSImage', $setupComponent.NamespaceURI)
            [void]$imageInstall.AppendChild($osImage)
        }
        $installFrom = $osImage.SelectSingleNode('u:InstallFrom', $nsMgr)
        if (-not $installFrom) {
            $installFrom = $xmlDoc.CreateElement('InstallFrom', $setupComponent.NamespaceURI)
            [void]$osImage.AppendChild($installFrom)
        }
        foreach ($existingMetadata in @($installFrom.SelectNodes('u:MetaData', $nsMgr))) {
            [void]$installFrom.RemoveChild($existingMetadata)
        }
        $metadata = $xmlDoc.CreateElement('MetaData', $setupComponent.NamespaceURI)
        $action = $xmlDoc.CreateAttribute('wcm', 'action', 'http://schemas.microsoft.com/WMIConfig/2002/State')
        $action.Value = 'add'
        [void]$metadata.Attributes.Append($action)
        $key = $xmlDoc.CreateElement('Key', $setupComponent.NamespaceURI)
        $key.InnerText = '/IMAGE/INDEX'
        [void]$metadata.AppendChild($key)
        $value = $xmlDoc.CreateElement('Value', $setupComponent.NamespaceURI)
        $value.InnerText = [string]$InstallImageIndex
        [void]$metadata.AppendChild($value)
        [void]$installFrom.AppendChild($metadata)

        $postInstallFile = $xmlDoc.CreateElement('File', $extensions.NamespaceURI)
        $postInstallFile.SetAttribute('path', 'C:\Windows\Setup\Scripts\WinUtil-PostInstall.ps1')
        $postInstallFile.InnerText = $postInstallScript
        [void]$extensions.AppendChild($postInstallFile)

        $firstLogonFile.InnerText = "& 'C:\Windows\Setup\Scripts\WinUtil-PostInstall.ps1';`r`n`r`n$($firstLogonFile.InnerText.Trim())"

        $null = & $Logger 'Adicionadas as personalizações pós-instalação do WinUtil (AppX, registro e tarefas agendadas) ao autounattend.xml.'
        return $xmlDoc.OuterXml
    }

    function Add-WinUtilISOSetupScriptFallback {
        param (
            [Parameter(Mandatory)][string]$ContentRoot,
            [Parameter(Mandatory)][string]$XmlContent,
            [scriptblock]$Logger
        )

        $xmlDoc = [xml]::new()
        $xmlDoc.PreserveWhitespace = $true
        $xmlDoc.LoadXml($XmlContent)
        $nsMgr = New-Object System.Xml.XmlNamespaceManager($xmlDoc.NameTable)
        $nsMgr.AddNamespace('u', 'urn:schemas-microsoft-com:unattend')
        $nsMgr.AddNamespace('sg', 'https://schneegans.de/windows/unattend-generator/')

        $setupScriptsRoot = Join-Path $ContentRoot 'sources\$OEM$\$$\Setup\Scripts'
        $stagedCount = 0
        foreach ($file in $xmlDoc.SelectNodes('//sg:File', $nsMgr)) {
            $path = $file.GetAttribute('path')
            if (-not $path.StartsWith('C:\Windows\Setup\Scripts\', [System.StringComparison]::OrdinalIgnoreCase)) {
                continue
            }

            $relativePath = $path.Substring('C:\Windows\Setup\Scripts\'.Length)
            $targetPath = Join-Path $setupScriptsRoot $relativePath
            New-Item -Path (Split-Path $targetPath -Parent) -ItemType Directory -Force | Out-Null

            $encoding = switch ([System.IO.Path]::GetExtension($targetPath)) {
                { $_ -in '.ps1', '.xml' } { [System.Text.Encoding]::UTF8; break }
                { $_ -in '.reg', '.vbs', '.js' } { [System.Text.UnicodeEncoding]::new($false, $true); break }
                default { [System.Text.Encoding]::Default }
            }
            $bytes = $encoding.GetPreamble() + $encoding.GetBytes($file.InnerText.Trim())
            [System.IO.File]::WriteAllBytes($targetPath, $bytes)
            $stagedCount++
        }

        $useConfigurationSet = $xmlDoc.SelectSingleNode('/u:unattend/u:settings[@pass="windowsPE"]/u:component[@name="Microsoft-Windows-Setup"]/u:UseConfigurationSet', $nsMgr)
        if ($useConfigurationSet) {
            $useConfigurationSet.InnerText = 'true'
            [System.IO.File]::WriteAllText((Join-Path $ContentRoot 'autounattend.xml'), $xmlDoc.OuterXml, [System.Text.UTF8Encoding]::new($false))
        }
        & $Logger "Preparados $stagedCount arquivos de fallback de script de instalação do WinUtil em '$setupScriptsRoot'."
    }

    if (-not (Test-Path $ISOContentsDir)) {
        throw "O diretório de conteúdo da ISO não existe: $ISOContentsDir"
    }

    if ([string]::IsNullOrWhiteSpace($AutoUnattendXml)) {
        throw "O conteúdo do autounattend.xml é necessário para preparar a mídia de instalação."
    }

    $preparedAutoUnattendXml = Add-WinUtilISOSetupCustomizations -XmlContent $AutoUnattendXml -InstallImageIndex $InstallImageIndex -Logger $Log
    $unattendPath = Join-Path $ISOContentsDir "autounattend.xml"
    [System.IO.File]::WriteAllText($unattendPath, $preparedAutoUnattendXml, [System.Text.UTF8Encoding]::new($false))
    & $Log "Gravado autounattend.xml com as personalizações de instalação do WinUtil na raiz da ISO ($unattendPath)."
    Add-WinUtilISOSetupScriptFallback -ContentRoot $ISOContentsDir -XmlContent $preparedAutoUnattendXml -Logger $Log

    Write-WinUtilISOEditionConfig -ContentRoot $ISOContentsDir -EditionId $InstallEditionId -Logger $Log

    if ($InjectCurrentSystemDrivers) {
        Add-WinUtilISOStagedDrivers -ContentRoot $ISOContentsDir -Logger $Log -InstallImagePath $InstallImagePath -InstallImageIndex $InstallImageIndex -DriversInjected $DriversInjected
    }
}
