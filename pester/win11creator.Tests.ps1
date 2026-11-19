#===========================================================================
# Testes - Criador do Win11

Describe "Mídia de configuração do Criador do Win11" {
    BeforeAll {
        $script:repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
        $script:isoWorkflowPath = Join-Path $script:repoRoot "functions\private\Invoke-WinUtilISO.ps1"
        $script:isoUsbWorkflowPath = Join-Path $script:repoRoot "functions\private\Invoke-WinUtilISOUSB.ps1"
        $script:isoScriptPath = Join-Path $script:repoRoot "functions\private\Invoke-WinUtilISOScript.ps1"
        $script:autoUnattendPath = Join-Path $script:repoRoot "tools\autounattend.xml"

        function Get-WinUtilFunctionText {
            param (
                [Parameter(Mandatory)][string]$Path,
                [Parameter(Mandatory)][string]$FunctionName
            )

            $tokens = $null
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $Path), [ref]$tokens, [ref]$errors)
            if ($errors.Count -gt 0) {
                throw "Unable to parse $Path`: $($errors[0].Message)"
            }

            $functionAst = $ast.Find({
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                    $node.Name -eq $FunctionName
            }, $true)

            if (-not $functionAst) {
                throw "Unable to find function $FunctionName in $Path."
            }

            return $functionAst.Extent.Text
        }

        # Pastas de pacote raiz produzidas pela fixture abaixo, após nested_pkg\x64 ser incorporada à
        # sua pasta pai. Escritas explicitamente em vez de derivadas, para que uma deduplicação quebrada falhe as asserções
        # em vez de mover silenciosamente a expectativa junto com ela.
        $script:expectedRootPackages = 8
        $script:resilienceDriverFixtures = @(
            @{ Path = 'system_pkg'; Name = 'chipset.inf'; Class = 'System' },
            @{ Path = 'storage_pkg'; Name = 'iaStorAC.inf'; Class = 'System' },
            @{ Path = 'scsi_pkg'; Name = 'controller.inf'; Class = 'SCSIAdapter' },
            @{ Path = 'net_pkg'; Name = 'network.inf'; Class = 'Net' },
            @{ Path = 'group_a\duplicate'; Name = 'audio.inf'; Class = 'Media' },
            @{ Path = 'group_b\duplicate'; Name = 'extension.inf'; Class = 'Media' },
            @{ Path = 'nested_pkg'; Name = 'main.inf'; Class = 'Net' },
            @{ Path = 'nested_pkg\x64'; Name = 'extra.inf'; Class = 'Net' },
            @{ Path = 'net_pkg_v2'; Name = 'network2.inf'; Class = 'Net' }
        )

        # Substitui `dism /Online /Export-Driver`, que o script ISO agora invoca
        # por meio de Invoke-WinUtilISODism em vez de Start-Process. Os dois nomes-folha `duplicate`
        # cobrem o registro de falhas por pacote, que deve permanecer inequívoco; `nested_pkg`
        # cobre um pacote com INFs na raiz e em uma subpasta; e `net_pkg_v2` é um
        # irmão cujo nome começa com `net_pkg`, que a deduplicação não deve engolir.
        function Export-WinUtilTestDriverPackage {
            param (
                [Parameter(Mandatory)][string[]]$Arguments,
                [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Fixtures
            )

            $destination = @($Arguments | Where-Object { $_ -like '/Destination:*' })
            if ($destination.Count -ne 1) {
                throw "Expected exactly one /Destination argument in the mocked DISM export: $($Arguments -join ' ')"
            }

            $exportRoot = $destination[0].Substring('/Destination:'.Length)
            $script:driverExportRoot = $exportRoot

            # APIs de arquivo do .NET em vez dos cmdlets: o -Encoding de Set-Content vem do
            # provedor FileSystem, e um caractere curinga em $exportRoot impede que o provedor
            # resolva, então o parâmetro desaparece.
            foreach ($fixture in $fixtures) {
                $fixturePath = Join-Path $exportRoot $fixture.Path
                [void][System.IO.Directory]::CreateDirectory($fixturePath)
                [System.IO.File]::WriteAllText(
                    (Join-Path $fixturePath $fixture.Name),
                    (@(
                        '[Version]'
                        "Class=$($fixture.Class)"
                        if ($fixture.Provider) { "Provider=$($fixture.Provider)" }
                        if ($fixture.DriverVer) {
                            $versionKeyword = if ($fixture.VersionKeyword) { $fixture.VersionKeyword } else { 'DriverVer' }
                            "$versionKeyword=$($fixture.DriverVer)"
                        }
                    ) -join "`r`n"),
                    [System.Text.Encoding]::ASCII)
            }
        }

        function New-WinUtilDriverExportHarness {
            param (
                [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Fixtures,
                [string]$FailedDriverPath,
                [switch]$FailAllAddDrivers,
                [switch]$FailDiscard
            )

            $script:dismCalls = [System.Collections.Generic.List[string]]::new()
            $script:driverExportRoot = $null
            $script:driverExportFixtures = $Fixtures
            $script:failedDriverPath = $FailedDriverPath
            $script:failAllAddDrivers = $FailAllAddDrivers
            $script:failDiscard = $FailDiscard
            $script:exportedInfsAtAddDriver = $null

            Set-Item -Path function:global:dism.exe -Value {
                param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)

                $script:dismCalls.Add(($Arguments -join '|'))
                $global:LASTEXITCODE = 0
                if ($Arguments -contains '/Get-WimInfo') {
                    'Languages : en-US'
                    'Installation : Client'
                    'Edition : Professional'
                    'ProductSuite : Terminal Server'
                    'ProductType : WinNT'
                } elseif ($Arguments -contains '/Mount-Image') {
                    '[==========================100.0%==========================]'
                } elseif ($Arguments -contains '/Export-Driver') {
                    Export-WinUtilTestDriverPackage -Arguments $Arguments -Fixtures $script:driverExportFixtures
                } elseif ($Arguments -contains '/Add-Driver') {
                    # Captura o que ainda está em disco exatamente quando o DISM faria /Recurse nele: este é o
                    # único ponto em que se pode provar que as pastas excluídas sumiram, já que o SUT apaga toda a
                    # raiz de exportação em sua própria limpeza assim que Invoke-WinUtilISOScript retorna.
                    $script:exportRootAtAddDriver = @(Get-ChildItem -LiteralPath $script:driverExportRoot -Directory -Recurse -ErrorAction SilentlyContinue | ForEach-Object FullName)
                    $script:exportedInfsAtAddDriver = @(Get-ChildItem -LiteralPath $script:driverExportRoot -Filter '*.inf' -File -Recurse -ErrorAction SilentlyContinue | ForEach-Object FullName)
                    if ($script:failAllAddDrivers -or ($script:failedDriverPath -and @($Arguments | Where-Object { $_ -like "*$($script:failedDriverPath)" }).Count -gt 0)) {
                        $global:LASTEXITCODE = 13
                        'Error: 13'
                    }
                } elseif ($Arguments -contains '/Discard' -and $script:failDiscard) {
                    $global:LASTEXITCODE = 50
                    'Discard failed'
                }
            }
        }

        $script:modifyFunction = Get-WinUtilFunctionText -Path $script:isoWorkflowPath -FunctionName "Invoke-WinUtilISOModify"
        $script:mountAndVerifyFunction = Get-WinUtilFunctionText -Path $script:isoWorkflowPath -FunctionName "Invoke-WinUtilISOMountAndVerify"
        $script:checkExistingWorkFunction = Get-WinUtilFunctionText -Path $script:isoWorkflowPath -FunctionName "Invoke-WinUtilISOCheckExistingWork"
        $script:cleanAndResetFunction = Get-WinUtilFunctionText -Path $script:isoWorkflowPath -FunctionName "Invoke-WinUtilISOCleanAndReset"
        $script:exportFunction = Get-WinUtilFunctionText -Path $script:isoWorkflowPath -FunctionName "Invoke-WinUtilISOExport"
        $script:writeUsbFunction = Get-WinUtilFunctionText -Path $script:isoUsbWorkflowPath -FunctionName "Invoke-WinUtilISOWriteUSB"
        $script:editionIdFunction = Get-WinUtilFunctionText -Path $script:isoWorkflowPath -FunctionName "Get-WinUtilEditionIdFromName"
        $script:imageEditionIdFunction = Get-WinUtilFunctionText -Path $script:isoWorkflowPath -FunctionName "Get-WinUtilImageEditionId"
        $script:wimMetadataAssertionFunction = Get-WinUtilFunctionText -Path $script:isoScriptPath -FunctionName "Assert-WinUtilISOWimMetadata"
    }

    It "o modelo autounattend não força uma chave de produto" {
        [xml]$xml = Get-Content -Path $script:autoUnattendPath -Raw
        $nsMgr = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
        $nsMgr.AddNamespace("u", "urn:schemas-microsoft-com:unattend")

        $productKeyCount = $xml.SelectNodes("//u:ProductKey", $nsMgr).Count
        if ($productKeyCount -ne 0) {
            throw "Expected no ProductKey nodes, found $productKeyCount."
        }
    }

    It "define todas as omissões de hardware antes de a Instalação do Windows verificar os requisitos" {
        [xml]$xml = Get-Content -Path $script:autoUnattendPath -Raw
        $nsMgr = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
        $nsMgr.AddNamespace("u", "urn:schemas-microsoft-com:unattend")
        $paths = @($xml.SelectNodes('/u:unattend/u:settings[@pass="windowsPE"]/u:component[@name="Microsoft-Windows-Setup"]/u:RunSynchronous/u:RunSynchronousCommand/u:Path', $nsMgr) | ForEach-Object InnerText) -join "`n"

        foreach ($bypass in 'BypassTPMCheck', 'BypassSecureBootCheck', 'BypassRAMCheck', 'BypassCPUCheck', 'BypassStorageCheck') {
            $paths | Should -Match ([regex]::Escape($bypass))
        }
    }

    It "define valores sensíveis do registro para o OOBE antes de ele começar" {
        [xml]$xml = Get-Content -Path $script:autoUnattendPath -Raw
        $nsMgr = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
        $nsMgr.AddNamespace("u", "urn:schemas-microsoft-com:unattend")
        $paths = @($xml.SelectNodes('/u:unattend/u:settings[@pass="specialize"]/u:component[@name="Microsoft-Windows-Deployment"]/u:RunSynchronous/u:RunSynchronousCommand/u:Path', $nsMgr) | ForEach-Object InnerText) -join "`n"

        foreach ($valueName in 'BypassNRO', 'PreventDeviceEncryption', 'ShippedWithReserves') {
            $paths | Should -Match ([regex]::Escape($valueName))
        }
    }

    It "o script ISO aceita a edição selecionada e metadados de manutenção do WIM apenas com drivers" {
        $isoScriptPath = Join-Path $PSScriptRoot "..\functions\private\Invoke-WinUtilISOScript.ps1"
        $content = Get-Content -Path $isoScriptPath -Raw

        foreach ($pattern in @(
            '\[string\]\$InstallEditionId',
            '\[string\]\$InstallImagePath',
            '\[int\]\$InstallImageIndex',
            'sources\\ei\.cfg',
            'PID\.txt'
        )) {
            if ($content -notmatch $pattern) {
                throw "Expected Invoke-WinUtilISOScript.ps1 to match pattern: $pattern"
            }
        }
    }

    It "inicia cada nova modificação do ISO em um diretório de trabalho novo" {
        foreach ($expectedText in @(
            '$workDir = Join-Path $env:TEMP "WinUtil_Win11ISO_$(Get-Date -Format ''yyyyMMdd_HHmmss'')"',
            '$workDir = "$($workDir)_$(([guid]::NewGuid()).ToString(''N'').Substring(0, 8))"'
        )) {
            $script:modifyFunction | Should -Match ([regex]::Escape($expectedText))
        }

        $script:modifyFunction | Should -Not -Match ([regex]::Escape("Reusing existing temp directory"))
    }

    It "converte mensagens de aviso do script ISO em avisos do job" {
        $script:modifyFunction | Should -Match 'if \(\$m -like "Warning:\*"\)[\s\S]*Write-WinUtilISOLog -Level "WARN" -Message \$m -SkipSessionLog[\s\S]*Write-Warning \$m'
    }

    It "mantém a manutenção do WIM limitada ao DISM Add-Driver, sem exportação ou limpeza de imagem" {
        $isoScriptContent = Get-Content -Path $script:isoScriptPath -Raw

        foreach ($expectedText in @(
            "'/Mount-Image'",
            "'/Add-Driver'",
            "'/Commit'",
            "`$mountDir = Join-Path (Split-Path -Path `$ContentRoot -Parent) 'wim_mount'",
            'validação dos metadados do install.wim passou',
            "Join-Path `$ContentRoot 'sources\boot.wim'"
        )) {
            $isoScriptContent | Should -Match ([regex]::Escape($expectedText))
        }

        foreach ($forbiddenText in @(
            'Mount-WindowsImage',
            'Dismount-WindowsImage',
            'Export-WindowsImage',
            'Set-WindowsImage',
            '/ResetBase',
            '/Cleanup-Image',
            '$WinpeDriver$'
        )) {
            $isoScriptContent | Should -Not -Match ([regex]::Escape($forbiddenText))
        }
    }

    It "injeta apenas drivers de armazenamento SCSIAdapter ou HDC no boot.wim" {
        $isoScriptContent = Get-Content -Path $script:isoScriptPath -Raw

        $isoScriptContent | Should -Match 'SCSIAdapter\|HDC'
        $isoScriptContent | Should -Match ([regex]::Escape("Join-Path `$ContentRoot 'sources\boot.wim'"))
        $isoScriptContent | Should -Not -Match ([regex]::Escape("Join-Path `$ContentRoot '`$WinpeDriver$'"))
        $isoScriptContent | Should -Not -Match ([regex]::Escape('sources\$OEM$\$$\Drivers'))
        $isoScriptContent | Should -Not -Match ([regex]::Escape('WinUtil-InstallDrivers.ps1'))
        $isoScriptContent | Should -Not -Match ([regex]::Escape('SetupComplete.cmd'))
    }

    It "rejeita metadados inválidos do WIM antes e depois da injeção de drivers" {
        . ([scriptblock]::Create($script:wimMetadataAssertionFunction))

        $valid = @{ Languages = 'en-US'; Installation = 'Client'; Edition = 'Professional'; ProductSuite = 'Terminal Server'; ProductType = 'WinNT' }
        $invalidBefore = $valid.Clone()
        $invalidBefore.Edition = '<undefined>'
        $invalidAfter = $valid.Clone()
        $invalidAfter.ProductType = '<undefined>'

        { Assert-WinUtilISOWimMetadata -Before $invalidBefore } | Should -Throw '*já são inválidos*'
        { Assert-WinUtilISOWimMetadata -Before $valid -After $invalidAfter } | Should -Throw '*validação dos metadados do install.wim falhou*'
    }

    It "executa todos os fluxos de ISO em segundo plano pela camada de jobs compartilhada" {
        $jobNames = @{
            mountAndVerify = "ISO mount"
            modify         = "ISO modify"
            cleanAndReset  = "ISO cleanup"
            export         = "ISO export"
            writeUsb       = "USB write"
        }

        foreach ($entry in @(
            @{ Text = $script:mountAndVerifyFunction; Name = $jobNames.mountAndVerify },
            @{ Text = $script:modifyFunction; Name = $jobNames.modify },
            @{ Text = $script:cleanAndResetFunction; Name = $jobNames.cleanAndReset },
            @{ Text = $script:exportFunction; Name = $jobNames.export },
            @{ Text = $script:writeUsbFunction; Name = $jobNames.writeUsb }
        )) {
            $entry.Text | Should -Match ([regex]::Escape("Start-WinUtilJob -Name `"$($entry.Name)`""))
            # A camada de jobs controla o estado de ocupação, a barra de progresso e o item da barra de tarefas
            $entry.Text | Should -Not -Match ([regex]::Escape('Win11ISOProcessRunning'))
            $entry.Text | Should -Not -Match ([regex]::Escape('RunspaceFactory]::CreateRunspace()'))
            $entry.Text | Should -Not -Match ([regex]::Escape('SessionStateProxy.SetVariable'))
            $entry.Text | Should -Not -Match ([regex]::Escape('[System.Windows.MessageBox]::Show'))
        }
    }

    It "executa a montagem e a verificação do ISO fora da thread da interface" {
        $script:mountAndVerifyFunction | Should -Match ([regex]::Escape('Start-WinUtilJob -Name "ISO mount"'))
        $script:mountAndVerifyFunction | Should -Match ([regex]::Escape('IsoPath = $isoPath'))
        $script:mountAndVerifyFunction | Should -Match ([regex]::Escape('Invoke-WPFUIThread -ScriptBlock {'))
        $script:mountAndVerifyFunction | Should -Match ([regex]::Escape('Write-WinUtilISOLog'))
        $script:mountAndVerifyFunction | Should -Not -Match ([regex]::Escape('Write-Win11ISOLog'))
        $script:mountAndVerifyFunction | Should -Match ([regex]::Escape('$sync["WPFWin11ISOBrowseButton"].IsEnabled = $false'))
        $script:mountAndVerifyFunction | Should -Match ([regex]::Escape('$sync["WPFWin11ISOBrowseButton"].IsEnabled = $true'))
        $script:mountAndVerifyFunction | Should -Match ([regex]::Escape('$sync["WPFWin11ISOMountButton"].IsEnabled = $false'))
        $script:mountAndVerifyFunction | Should -Match ([regex]::Escape('$sync["WPFWin11ISOMountButton"].IsEnabled = $true'))
        $script:mountAndVerifyFunction | Should -Match ([regex]::Escape('$sync["WPFWin11ISOModifyButton"].IsEnabled = $false'))
        $script:mountAndVerifyFunction | Should -Match ([regex]::Escape('$sync["WPFWin11ISOModifyButton"].IsEnabled = [bool]$Verified'))
    }

    It "desmonta um ISO e mantém a modificação desativada quando a verificação falha" {
        $script:mountAndVerifyFunction | Should -Match ([regex]::Escape('$verified = $false'))
        $script:mountAndVerifyFunction | Should -Match ([regex]::Escape('$verified = $true'))
        $script:mountAndVerifyFunction | Should -Match ([regex]::Escape('Dismount-DiskImage -ImagePath $isoPath -ErrorAction Stop'))
        $script:mountAndVerifyFunction | Should -Match ([regex]::Escape('$sync["Win11ISOImagePath"] = $null'))
        $script:mountAndVerifyFunction.IndexOf('Dismount-DiskImage -ImagePath $isoPath') | Should -BeGreaterThan $script:mountAndVerifyFunction.IndexOf('finally')
    }

    It "desmonta um ISO verificado anteriormente antes de montar um substituto" {
        $script:mountAndVerifyFunction | Should -Match ([regex]::Escape('$previous = $sync["Win11ISOImagePath"]'))
        $script:mountAndVerifyFunction | Should -Match ([regex]::Escape('Dismount-DiskImage -ImagePath $previous -ErrorAction Stop'))

        $script:mountAndVerifyFunction.IndexOf('Dismount-DiskImage -ImagePath $previous') |
            Should -BeLessThan $script:mountAndVerifyFunction.IndexOf('$sync["Win11ISOImagePath"] = $null')
    }

    It "mantém o caminho armazenado e restaura a interface quando o ISO anterior não pode ser desmontado" {
        $dismountIndex = $script:mountAndVerifyFunction.IndexOf('Dismount-DiskImage -ImagePath $previous')
        $resetIndex    = $script:mountAndVerifyFunction.IndexOf('$sync["Win11ISOImagePath"] = $null')

        $throwIndex = $script:mountAndVerifyFunction.IndexOf('throw $stillMounted')
        $throwIndex | Should -BeGreaterThan $dismountIndex
        $throwIndex | Should -BeLessThan $resetIndex

        $script:mountAndVerifyFunction.IndexOf('try {') | Should -BeLessThan $dismountIndex
    }

    It "mantém a limpeza do ISO no finally para que parar a modificação não a ignore" {
        $finallyIndex = $script:modifyFunction.IndexOf('finally')

        $finallyIndex | Should -BeGreaterThan -1
        $script:modifyFunction.IndexOf('Dismount-DiskImage', $finallyIndex) | Should -BeGreaterThan $finallyIndex
        $script:modifyFunction.IndexOf('Remove-Item -Path $workDir -Recurse -Force', $finallyIndex) | Should -BeGreaterThan $finallyIndex
        $script:modifyFunction.IndexOf('$sync["Win11ISOImagePath"] = $null', $finallyIndex) | Should -BeGreaterThan $finallyIndex
    }

    It "tenta novamente a descoberta de trabalho existente após o job ativo terminar" {
        $script:checkExistingWorkFunction | Should -Match ([regex]::Escape('Invoke-WinUtilWhenIdle -DelayMilliseconds 500'))
        $script:checkExistingWorkFunction | Should -Match ([regex]::Escape('Invoke-WinUtilISOCheckExistingWork'))
        $script:checkExistingWorkFunction | Should -Match ([regex]::Escape('$sync["Win11ISOExistingWorkRetryPending"] = $false'))
    }

    It "relata o progresso e o log do ISO pelos auxiliares compartilhados" {
        $content = Get-Content -Path $script:isoWorkflowPath -Raw
        $usbContent = Get-Content -Path $script:isoUsbWorkflowPath -Raw

        foreach ($source in @($content, $usbContent)) {
            $source | Should -Match ([regex]::Escape('Step-WinUtilJob -Status'))
            $source | Should -Not -Match '(?m)^\s*function (Log|SetProgress)\('
            $source | Should -Not -Match ([regex]::Escape('$sync["WPFTweaksProgressLabel"]'))
        }

        # Toda linha de log de status também vai para o log da sessão
        $content | Should -Match ([regex]::Escape('Write-WinUtilLog -Level $Level -Component "Win11Creator" -Message $Message'))
    }

    It "bloqueia um install.esd grande demais antes da confirmação de apagamento do USB" {
        $script:writeUsbFunction | Should -Match ([regex]::Escape('$installEsd = Join-Path $contentsDir "sources\install.esd"'))
        $script:writeUsbFunction | Should -Match ([regex]::Escape('$esdSizeBytes -ge 4GB'))
        $script:writeUsbFunction | Should -Match 'arquivo install\.esd'

        $guardIndex = $script:writeUsbFunction.IndexOf('$installEsd = Join-Path $contentsDir "sources\install.esd"')
        $confirmationIndex = $script:writeUsbFunction.IndexOf('Confirmar Apagamento da USB')
        $guardIndex | Should -BeGreaterThan -1
        $confirmationIndex | Should -BeGreaterThan $guardIndex
    }

    It "limpa o atributo somente leitura do install.wim antes da divisão FAT32" {
        $splitGuardIndex = $script:writeUsbFunction.IndexOf('$wimSizeMB -gt 3800')
        $readOnlyResetIndex = $script:writeUsbFunction.IndexOf(
            'Set-ItemProperty -LiteralPath $installWim -Name IsReadOnly -Value $false'
        )
        $splitCommandIndex = $script:writeUsbFunction.IndexOf('Split-WindowsImage')

        $splitGuardIndex | Should -BeGreaterThan -1
        $readOnlyResetIndex | Should -BeGreaterThan $splitGuardIndex
        $splitCommandIndex | Should -BeGreaterThan $readOnlyResetIndex
    }

    It "mapeia nomes de edição do Windows para IDs de edição da instalação" {
        . ([scriptblock]::Create($script:editionIdFunction))

        $cases = @{
            "Windows 11 Home Single Language" = "CoreSingleLanguage"
            "Windows 11 Home N"               = "CoreN"
            "Windows 11 Home"                 = "Core"
            "Windows 11 Pro for Workstations N" = "ProfessionalWorkstationN"
            "Windows 11 Pro for Workstations" = "ProfessionalWorkstation"
            "Windows 11 Pro Education N"      = "ProfessionalEducationN"
            "Windows 11 Pro Education"        = "ProfessionalEducation"
            "Windows 11 Pro N"                = "ProfessionalN"
            "Windows 11 Pro"                  = "Professional"
            "Windows 11 Education N"          = "EducationN"
            "Windows 11 Education"            = "Education"
            "Windows 11 Enterprise LTSC N"    = "EnterpriseSN"
            "Windows 11 Enterprise LTSC"      = "EnterpriseS"
            "Windows 11 Enterprise N"         = "EnterpriseN"
            "Windows 11 Enterprise"           = "Enterprise"
        }

        foreach ($case in $cases.GetEnumerator()) {
            Get-WinUtilEditionIdFromName -EditionName $case.Key | Should -Be $case.Value
        }

        Get-WinUtilEditionIdFromName -EditionName "Windows 11 Unknown Edition" | Should -Be ""
    }

    It "resolve IDs de edição da instalação a partir dos metadados da imagem, independentemente do idioma de exibição" {
        . ([scriptblock]::Create($script:editionIdFunction))
        . ([scriptblock]::Create($script:imageEditionIdFunction))

        # Nomes de exibição em francês não contêm tokens em inglês, então apenas os metadados
        # EditionId pode resolvê-los. O índice 9 não tem entrada de metadados e recai
        # no mapa de nomes de exibição em inglês.
        Set-Item -Path function:global:Get-WindowsImage -Value {
            [CmdletBinding()]
            param($ImagePath, $Index)
            if ($ImagePath -ne 'C:\mock\install.wim') { throw "unexpected image path: $ImagePath" }
            $metadata = @{ 1 = 'Core'; 6 = 'Professional' }
            if (-not $metadata.ContainsKey($Index)) { return $null }
            return [pscustomobject]@{ EditionId = $metadata[$Index] }
        }

        try {
            Get-WinUtilImageEditionId -ImagePath 'C:\mock\install.wim' -ImageIndex 6 -EditionName 'Windows 11 Professionnel' | Should -Be 'Professional'
            Get-WinUtilImageEditionId -ImagePath 'C:\mock\install.wim' -ImageIndex 1 -EditionName 'Windows 11 Famille' | Should -Be 'Core'
            Get-WinUtilImageEditionId -ImagePath 'C:\mock\install.wim' -ImageIndex 6 -EditionName 'Windows 11 Pro' | Should -Be 'Professional'
            Get-WinUtilImageEditionId -ImagePath 'C:\mock\install.wim' -ImageIndex 9 -EditionName 'Windows 11 Pro' | Should -Be 'Professional'
        } finally {
            Remove-Item -Path function:global:Get-WindowsImage -ErrorAction SilentlyContinue
        }
    }

    It "usa nomes de exibição em inglês como fallback quando os metadados da imagem não estão disponíveis" {
        . ([scriptblock]::Create($script:editionIdFunction))
        . ([scriptblock]::Create($script:imageEditionIdFunction))

        Set-Item -Path function:global:Get-WindowsImage -Value {
            [CmdletBinding()]
            param($ImagePath, $Index)
            throw "mock image metadata unavailable for ${ImagePath} index ${Index}"
        }

        try {
            Get-WinUtilImageEditionId -ImagePath 'C:\mock\install.esd' -ImageIndex 3 -EditionName 'Windows 11 Pro' | Should -Be 'Professional'
            Get-WinUtilImageEditionId -ImagePath 'C:\mock\install.esd' -ImageIndex 3 -EditionName 'Windows 11 Professionnel' | Should -Be ''
        } finally {
            Remove-Item -Path function:global:Get-WindowsImage -ErrorAction SilentlyContinue
        }
    }

    It "grava ei.cfg e remove o PID.txt obsoleto para a edição selecionada" {
        $contentRoot = Join-Path ([IO.Path]::GetTempPath()) "WinUtilIsoConfig_$([guid]::NewGuid())"
        $sourcesDir = Join-Path $contentRoot "sources"
        $logs = [System.Collections.Generic.List[string]]::new()
        $logger = { param($message) $logs.Add([string]$message) }

        try {
            New-Item -Path $sourcesDir -ItemType Directory -Force | Out-Null
            Set-Content -Path (Join-Path $sourcesDir "PID.txt") -Value "stale-key" -Encoding UTF8
            Set-Content -Path (Join-Path $sourcesDir "ei.cfg") -Value "stale-cfg" -Encoding UTF8

            . $script:isoScriptPath
            Invoke-WinUtilISOScript -ISOContentsDir $contentRoot -AutoUnattendXml (Get-Content -Path $script:autoUnattendPath -Raw) -InstallEditionId "Professional" -Log $logger

            Test-Path (Join-Path $sourcesDir "PID.txt") | Should -BeFalse
            Test-Path (Join-Path $sourcesDir "ei.cfg") | Should -BeTrue
            (Get-Content -Path (Join-Path $sourcesDir "ei.cfg")) -join "|" |
                Should -Be "[EditionID]|Professional|[Channel]|Retail|[VL]|0"
            ($logs -join "|") | Should -Match "Removido sources\\PID\.txt"
            ($logs -join "|") | Should -Match "Gravado sources\\ei\.cfg"
        } finally {
            Remove-Item -Path $contentRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }



    It "adiciona drivers elegíveis a um índice do install.wim e não cria `$WinpeDriver$" {
        $contentRoot = Join-Path ([IO.Path]::GetTempPath()) "WinUtilIsoDrivers_$([guid]::NewGuid())"
        $installWim = Join-Path $contentRoot 'sources\install.wim'
        $template = Get-Content -Path $script:autoUnattendPath -Raw
        $logs = [System.Collections.Generic.List[string]]::new()

        New-WinUtilDriverExportHarness -Fixtures @(
            @{ Path = 'system_pkg'; Name = 'chipset.inf'; Class = 'System' },
            @{ Path = 'storage_pkg'; Name = 'iaStorAC.inf'; Class = 'SCSIAdapter' },
            @{ Path = 'scsi_pkg'; Name = 'controller.inf'; Class = 'SCSIAdapter' },
            @{ Path = 'net_pkg'; Name = 'network.inf'; Class = 'Net' },
            @{ Path = 'group_a\duplicate'; Name = 'audio.inf'; Class = 'Media' },
            @{ Path = 'hdx_asusext_apot_g5-tse.inf_amd64_aabbccddeeff0011'; Name = 'hdx_asusext_apot_g5-tse.inf'; Class = 'Extension' },
            @{ Path = 'ntprint.inf_x86_7426e1b60aa62272'; Name = 'ntprint.inf'; Class = 'Printer'; DriverVer = '1/1/2023,10.0.26100.8875' },
            @{ Path = 'ntprint.inf_x86_58e7118cdecb935e'; Name = 'ntprint.inf'; Class = 'Printer'; DriverVer = '6/1/2024,10.0.26100.9168' },
            @{ Path = 'nested_pkg'; Name = 'main.inf'; Class = 'Net' },
            @{ Path = 'nested_pkg\x64'; Name = 'extra.inf'; Class = 'Net' },
            @{ Path = 'net_pkg_v2'; Name = 'network2.inf'; Class = 'Net' }
        )

        try {
            New-Item -Path (Split-Path $installWim -Parent) -ItemType Directory -Force | Out-Null
            Set-Content -Path $installWim -Value 'mock-wim'
            . $script:isoScriptPath
            $driversInjected = [ref]$false
            Invoke-WinUtilISOScript -ISOContentsDir $contentRoot -AutoUnattendXml $template -InjectCurrentSystemDrivers $true -InstallImagePath $installWim -InstallImageIndex 6 -InstallEditionId 'Professional' -DriversInjected $driversInjected -Log {
                param($message)
                $logs.Add([string]$message)
            }

            Test-Path (Join-Path $contentRoot '$WinpeDriver$') | Should -BeFalse
            ($logs -join '|') | Should -Match 'Warning: boot.wim não foi encontrado'

            @($script:dismCalls | Where-Object { $_ -match '/Mount-Image' }).Count | Should -Be 1
            @($script:dismCalls | Where-Object { $_ -match '/Add-Driver' }).Count | Should -Be 9
            @($script:dismCalls | Where-Object { $_ -match '/Unmount-Image\|.*\|/Commit' }).Count | Should -Be 1
            @($script:dismCalls | Where-Object { $_ -match '/Get-WimInfo' }).Count | Should -Be 2
            ($script:dismCalls -join "`n") | Should -Not -Match '/Cleanup-Image|/Export-Image'
            ($logs -join '|') | Should -Match "Adicionados 9 de 9 pacotes de driver"

            # nested_pkg contém INFs na raiz e em x64. A adição na raiz já recursa
            # em x64, então a subpasta não deve receber uma chamada /Add-Driver própria.
            @($script:dismCalls | Where-Object { $_ -match '/Add-Driver' -and $_ -match ([regex]::Escape('nested_pkg')) }).Count | Should -Be 1
            ($script:dismCalls -join "`n") | Should -Not -Match ([regex]::Escape('nested_pkg\x64'))

            [xml]$answerFile = Get-Content -Path (Join-Path $contentRoot 'autounattend.xml') -Raw
            $nsMgr = New-Object System.Xml.XmlNamespaceManager($answerFile.NameTable)
            $nsMgr.AddNamespace('sg', 'https://schneegans.de/windows/unattend-generator/')
            $answerFile.SelectSingleNode('//sg:File[@path="C:\Windows\Setup\Scripts\WinUtil-InstallDrivers.ps1"]', $nsMgr) | Should -BeNullOrEmpty
            ($logs -join '|') | Should -Match 'Exportados 10 de 11 pacotes de driver \(1 excluídos\)'
            ($logs -join '|') | Should -Match "Excluindo o pacote de driver duplicado e desatualizado '.*ntprint\.inf_x86_7426e1b60aa62272' \(DriverVer 1/1/2023,10\.0\.26100\.8875\), substituído por '.*ntprint\.inf_x86_58e7118cdecb935e' \(DriverVer 6/1/2024,10\.0\.26100\.9168\)"
            ($logs -join '|') | Should -Match 'validação dos metadados do install.wim passou'
            ($logs -join '|') | Should -Match 'DISM mount concluído.'
            ($logs -join '|') | Should -Not -Match '100.0%'

            $script:exportRootAtAddDriver | Should -Contain (Join-Path $script:driverExportRoot 'hdx_asusext_apot_g5-tse.inf_amd64_aabbccddeeff0011')
            $script:exportRootAtAddDriver | Should -Not -Contain (Join-Path $script:driverExportRoot 'ntprint.inf_x86_7426e1b60aa62272')
            $script:exportRootAtAddDriver | Should -Contain (Join-Path $script:driverExportRoot 'ntprint.inf_x86_58e7118cdecb935e')
            $script:exportRootAtAddDriver | Should -Contain (Join-Path $script:driverExportRoot 'system_pkg')
            $script:exportRootAtAddDriver | Should -Contain (Join-Path $script:driverExportRoot 'group_a\duplicate')
        } finally {
            Remove-Item Function:\dism.exe -ErrorAction SilentlyContinue
            Remove-Item -Path $contentRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "injeta drivers de armazenamento SCSIAdapter no índice 2 do boot.wim e não `$WinpeDriver`$" {
        $contentRoot = Join-Path ([IO.Path]::GetTempPath()) "WinUtilIsoBootWim_$([guid]::NewGuid())"
        $installWim = Join-Path $contentRoot 'sources\install.wim'
        $bootWim = Join-Path $contentRoot 'sources\boot.wim'
        $template = Get-Content -Path $script:autoUnattendPath -Raw
        $logs = [System.Collections.Generic.List[string]]::new()

        New-WinUtilDriverExportHarness -Fixtures @(
            @{ Path = 'net_pkg'; Name = 'network.inf'; Class = 'Net' },
            @{ Path = 'scsi_pkg'; Name = 'controller.inf'; Class = 'SCSIAdapter' },
            @{ Path = 'hdc_pkg'; Name = 'ide.inf'; Class = 'HDC' },
            @{ Path = 'name_only_pkg'; Name = 'iaStorAC.inf'; Class = 'System' },
            @{ Path = 'iastorhsacomponent.inf_amd64_1b2a068a8496b6a2'; Name = 'iaStorHsaComponent.inf'; Class = 'SoftwareComponent' },
            @{ Path = 'iastorhsa_ext.inf_amd64_ba71359697f80d4e'; Name = 'iaStorHsa_Ext.inf'; Class = 'Extension' }
        )

        try {
            New-Item -Path (Split-Path $installWim -Parent) -ItemType Directory -Force | Out-Null
            Set-Content -Path $installWim -Value 'mock-wim'
            Set-Content -Path $bootWim -Value 'mock-boot'
            . $script:isoScriptPath
            Invoke-WinUtilISOScript -ISOContentsDir $contentRoot -AutoUnattendXml $template -InjectCurrentSystemDrivers $true -InstallImagePath $installWim -InstallImageIndex 6 -InstallEditionId 'Professional' -Log {
                param($message)
                $logs.Add([string]$message)
            }

            Test-Path (Join-Path $contentRoot '$WinpeDriver$') | Should -BeFalse
            @($script:dismCalls | Where-Object { $_ -match '/Mount-Image' -and $_ -match 'boot\.wim' -and $_ -match '/Index:2' }).Count | Should -Be 1
            @($script:dismCalls | Where-Object { $_ -match '/Mount-Image' -and $_ -match 'install\.wim' }).Count | Should -Be 1
            @($script:dismCalls | Where-Object { $_ -match '/Unmount-Image\|.*\|/Commit' }).Count | Should -Be 2

            $bootMountCall = $script:dismCalls | Where-Object { $_ -match '/Mount-Image' -and $_ -match 'boot\.wim' } | Select-Object -First 1
            $installMountCall = $script:dismCalls | Where-Object { $_ -match '/Mount-Image' -and $_ -match 'install\.wim' } | Select-Object -First 1
            $bootMountIndex = [Array]::IndexOf($script:dismCalls.ToArray(), $bootMountCall)
            $installMountIndex = [Array]::IndexOf($script:dismCalls.ToArray(), $installMountCall)
            $bootAdds = @($script:dismCalls[$bootMountIndex..($installMountIndex - 1)] | Where-Object { $_ -match '/Add-Driver' })
            $bootAdds.Count | Should -Be 2
            ($bootAdds -join "`n") | Should -Match ([regex]::Escape('scsi_pkg'))
            ($bootAdds -join "`n") | Should -Match ([regex]::Escape('hdc_pkg'))
            ($bootAdds -join "`n") | Should -Not -Match ([regex]::Escape('net_pkg'))
            ($bootAdds -join "`n") | Should -Not -Match 'iastorhsa'
            ($bootAdds -join "`n") | Should -Not -Match ([regex]::Escape('name_only_pkg'))

            @($script:dismCalls | Where-Object { $_ -match '/Add-Driver' }).Count | Should -Be 8
            ($logs -join '|') | Should -Match 'Adicionados 2 de 2 pacotes de driver a boot.wim'
            ($logs -join '|') | Should -Match 'Adicionados 6 de 6 pacotes de driver a install.wim'
        } finally {
            Remove-Item Function:\dism.exe -ErrorAction SilentlyContinue
            Remove-Item -Path $contentRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "injeta no boot.wim apenas o pacote de armazenamento duplicado mais recente" {
        $contentRoot = Join-Path ([IO.Path]::GetTempPath()) "WinUtilIsoBootWimDedup_$([guid]::NewGuid())"
        $installWim = Join-Path $contentRoot 'sources\install.wim'
        $bootWim = Join-Path $contentRoot 'sources\boot.wim'
        $template = Get-Content -Path $script:autoUnattendPath -Raw
        $logs = [System.Collections.Generic.List[string]]::new()

        New-WinUtilDriverExportHarness -Fixtures @(
            @{ Path = 'iastorvd.inf_amd64_11111111aaaaaaaa'; Name = 'iaStorVD.inf'; Class = 'SCSIAdapter'; DriverVer = '1/1/2023,20.2.1.1016' },
            @{ Path = 'iastorvd.inf_amd64_22222222bbbbbbbb'; Name = 'iaStorVD.inf'; Class = 'SCSIAdapter'; DriverVer = '6/1/2024,20.2.8.1028' }
        )

        try {
            New-Item -Path (Split-Path $installWim -Parent) -ItemType Directory -Force | Out-Null
            Set-Content -Path $installWim -Value 'mock-wim'
            Set-Content -Path $bootWim -Value 'mock-boot'
            . $script:isoScriptPath
            Invoke-WinUtilISOScript -ISOContentsDir $contentRoot -AutoUnattendXml $template -InjectCurrentSystemDrivers $true -InstallImagePath $installWim -InstallImageIndex 6 -InstallEditionId 'Professional' -Log {
                param($message)
                $logs.Add([string]$message)
            }

            $bootAdds = @($script:dismCalls | Where-Object { $_ -match '/Add-Driver' })
            @($bootAdds | Where-Object { $_ -match '22222222bbbbbbbb' }).Count | Should -Be 2
            @($bootAdds | Where-Object { $_ -match '11111111aaaaaaaa' }).Count | Should -Be 0
            ($logs -join '|') | Should -Match 'Adicionados 1 de 1 pacotes de driver a boot.wim'
            ($logs -join '|') | Should -Match 'Adicionados 1 de 1 pacotes de driver a install.wim'
        } finally {
            Remove-Item Function:\dism.exe -ErrorAction SilentlyContinue
            Remove-Item -Path $contentRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "injeta pacotes de driver Class=Extension como qualquer outra exportação" {
        $contentRoot = Join-Path ([IO.Path]::GetTempPath()) "WinUtilIsoExtensionInject_$([guid]::NewGuid())"
        $installWim = Join-Path $contentRoot 'sources\install.wim'
        $template = Get-Content -Path $script:autoUnattendPath -Raw
        $logs = [System.Collections.Generic.List[string]]::new()

        New-WinUtilDriverExportHarness -Fixtures @(
            @{ Path = 'net_pkg'; Name = 'network.inf'; Class = 'Net' },
            @{ Path = 'ext_pkg_lower'; Name = 'lowercase_extension.inf'; Class = 'extension' },
            @{ Path = 'ext_pkg_quoted'; Name = 'quoted_extension.inf'; Class = '"Extension"' }
        )

        try {
            New-Item -Path (Split-Path $installWim -Parent) -ItemType Directory -Force | Out-Null
            Set-Content -Path $installWim -Value 'mock-wim'
            . $script:isoScriptPath
            $driversInjected = [ref]$false
            Invoke-WinUtilISOScript -ISOContentsDir $contentRoot -AutoUnattendXml $template -InjectCurrentSystemDrivers $true -InstallImagePath $installWim -InstallImageIndex 6 -InstallEditionId 'Professional' -DriversInjected $driversInjected -Log {
                param($message)
                $logs.Add([string]$message)
            }

            @($script:dismCalls | Where-Object { $_ -match '/Add-Driver' }).Count | Should -Be 3
            ($logs -join '|') | Should -Match 'Exportados 3 de 3 pacotes de driver \(0 excluídos\)'
            $driversInjected.Value | Should -BeTrue

            $script:exportRootAtAddDriver | Should -Contain (Join-Path $script:driverExportRoot 'ext_pkg_lower')
            $script:exportRootAtAddDriver | Should -Contain (Join-Path $script:driverExportRoot 'ext_pkg_quoted')
            $script:exportRootAtAddDriver | Should -Contain (Join-Path $script:driverExportRoot 'net_pkg')
        } finally {
            Remove-Item Function:\dism.exe -ErrorAction SilentlyContinue
            Remove-Item -Path $contentRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "mantém uma pasta duplicada obsoleta que contém um pacote aninhado retido" {
        $contentRoot = Join-Path ([IO.Path]::GetTempPath()) "WinUtilIsoStaleNestedRetained_$([guid]::NewGuid())"
        $installWim = Join-Path $contentRoot 'sources\install.wim'
        $template = Get-Content -Path $script:autoUnattendPath -Raw
        $logs = [System.Collections.Generic.List[string]]::new()

        New-WinUtilDriverExportHarness -Fixtures @(
            @{ Path = 'main.inf_amd64_11111111aaaaaaaa'; Name = 'main.inf'; Class = 'Net'; DriverVer = '1/1/2023,1.0.0.0' },
            @{ Path = 'main.inf_amd64_22222222bbbbbbbb'; Name = 'main.inf'; Class = 'Net'; DriverVer = '6/1/2024,2.0.0.0' },
            @{ Path = 'main.inf_amd64_11111111aaaaaaaa\retained_child'; Name = 'network.inf'; Class = 'Net' }
        )

        try {
            New-Item -Path (Split-Path $installWim -Parent) -ItemType Directory -Force | Out-Null
            Set-Content -Path $installWim -Value 'mock-wim'
            . $script:isoScriptPath
            $driversInjected = [ref]$false
            Invoke-WinUtilISOScript -ISOContentsDir $contentRoot -AutoUnattendXml $template -InjectCurrentSystemDrivers $true -InstallImagePath $installWim -InstallImageIndex 6 -InstallEditionId 'Professional' -DriversInjected $driversInjected -Log {
                param($message)
                $logs.Add([string]$message)
            }

            ($logs -join '|') | Should -Match "Excluindo o pacote de driver duplicado e desatualizado '.*main\.inf_amd64_11111111aaaaaaaa' \(DriverVer 1/1/2023,1\.0\.0\.0\), substituído por '.*main\.inf_amd64_22222222bbbbbbbb' \(DriverVer 6/1/2024,2\.0\.0\.0\)"
            ($logs -join '|') | Should -Match "Mantendo o diretório do pacote de driver excluído '.*main\.inf_amd64_11111111aaaaaaaa' porque ele contém um pacote aninhado retido"
            @($script:dismCalls | Where-Object { $_ -match '/Add-Driver' }).Count | Should -Be 2
            $script:exportRootAtAddDriver | Should -Contain (Join-Path $script:driverExportRoot 'main.inf_amd64_11111111aaaaaaaa')
            $script:exportedInfsAtAddDriver | Should -Not -Contain (Join-Path $script:driverExportRoot 'main.inf_amd64_11111111aaaaaaaa\main.inf')
            $script:exportedInfsAtAddDriver | Should -Contain (Join-Path $script:driverExportRoot 'main.inf_amd64_11111111aaaaaaaa\retained_child\network.inf')
            $driversInjected.Value | Should -BeTrue
        } finally {
            Remove-Item Function:\dism.exe -ErrorAction SilentlyContinue
            Remove-Item -Path $contentRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "remove um INF duplicado obsoleto antes de adicionar recursivamente seu ancestral retido" {
        $contentRoot = Join-Path ([IO.Path]::GetTempPath()) "WinUtilIsoStaleNestedExcluded_$([guid]::NewGuid())"
        $installWim = Join-Path $contentRoot 'sources\install.wim'
        $template = Get-Content -Path $script:autoUnattendPath -Raw

        New-WinUtilDriverExportHarness -Fixtures @(
            @{ Path = 'root_pkg'; Name = 'root.inf'; Class = 'Net' },
            @{ Path = 'root_pkg\dup.inf_amd64_11111111aaaaaaaa'; Name = 'dup.inf'; Class = 'Media'; DriverVer = '1/1/2020,1.0.0.0' },
            @{ Path = 'root_pkg\dup.inf_amd64_22222222bbbbbbbb'; Name = 'dup.inf'; Class = 'Media'; DriverVer = '6/1/2024,2.0.0.0' },
            @{ Path = 'root_pkg\dup.inf_amd64_11111111aaaaaaaa\retained_grandchild'; Name = 'storage.inf'; Class = 'SCSIAdapter' }
        )

        try {
            New-Item -Path (Split-Path $installWim -Parent) -ItemType Directory -Force | Out-Null
            Set-Content -Path $installWim -Value 'mock-wim'
            . $script:isoScriptPath
            Invoke-WinUtilISOScript -ISOContentsDir $contentRoot -AutoUnattendXml $template -InjectCurrentSystemDrivers $true -InstallImagePath $installWim -InstallImageIndex 6 -InstallEditionId 'Professional'

            $addDriverCalls = @($script:dismCalls | Where-Object { $_ -match '/Add-Driver' })
            $addDriverCalls.Count | Should -Be 1
            $addDriverCalls[0] | Should -Match ([regex]::Escape('/Driver:' + (Join-Path $script:driverExportRoot 'root_pkg')))
            $script:exportRootAtAddDriver | Should -Contain (Join-Path $script:driverExportRoot 'root_pkg\dup.inf_amd64_11111111aaaaaaaa')
            $script:exportedInfsAtAddDriver | Should -Contain (Join-Path $script:driverExportRoot 'root_pkg\root.inf')
            $script:exportedInfsAtAddDriver | Should -Not -Contain (Join-Path $script:driverExportRoot 'root_pkg\dup.inf_amd64_11111111aaaaaaaa\dup.inf')
            $script:exportedInfsAtAddDriver | Should -Contain (Join-Path $script:driverExportRoot 'root_pkg\dup.inf_amd64_11111111aaaaaaaa\retained_grandchild\storage.inf')
            $script:exportedInfsAtAddDriver | Should -Contain (Join-Path $script:driverExportRoot 'root_pkg\dup.inf_amd64_22222222bbbbbbbb\dup.inf')
        } finally {
            Remove-Item Function:\dism.exe -ErrorAction SilentlyContinue
            Remove-Item -Path $contentRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "mantém pacotes de provedores diferentes mesmo quando o nome e a arquitetura do INF coincidem" {
        $contentRoot = Join-Path ([IO.Path]::GetTempPath()) "WinUtilIsoProviderCollision_$([guid]::NewGuid())"
        $installWim = Join-Path $contentRoot 'sources\install.wim'
        $template = Get-Content -Path $script:autoUnattendPath -Raw
        $logs = [System.Collections.Generic.List[string]]::new()

        New-WinUtilDriverExportHarness -Fixtures @(
            @{ Path = 'device.inf_amd64_11111111aaaaaaaa'; Name = 'device.inf'; Class = 'Net'; Provider = 'Contoso'; DriverVer = '1/1/2023,1.0.0.0' },
            @{ Path = 'device.inf_amd64_22222222bbbbbbbb'; Name = 'device.inf'; Class = 'Net'; Provider = 'Fabrikam'; DriverVer = '1/1/2024,2.0.0.0' }
        )

        try {
            New-Item -Path (Split-Path $installWim -Parent) -ItemType Directory -Force | Out-Null
            Set-Content -Path $installWim -Value 'mock-wim'
            . $script:isoScriptPath
            Invoke-WinUtilISOScript -ISOContentsDir $contentRoot -AutoUnattendXml $template -InjectCurrentSystemDrivers $true -InstallImagePath $installWim -InstallImageIndex 6 -InstallEditionId 'Professional' -Log {
                param($message)
                $logs.Add([string]$message)
            }

            @($script:dismCalls | Where-Object { $_ -match '/Add-Driver' }).Count | Should -Be 2
            ($logs -join '|') | Should -Match 'Exportados 2 de 2 pacotes de driver \(0 excluídos\)'
            ($logs -join '|') | Should -Not -Match 'Excluindo o pacote de driver duplicado e desatualizado'

            $script:exportRootAtAddDriver | Should -Contain (Join-Path $script:driverExportRoot 'device.inf_amd64_11111111aaaaaaaa')
            $script:exportRootAtAddDriver | Should -Contain (Join-Path $script:driverExportRoot 'device.inf_amd64_22222222bbbbbbbb')
        } finally {
            Remove-Item Function:\dism.exe -ErrorAction SilentlyContinue
            Remove-Item -Path $contentRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "descarta versões duplicadas obsoletas de drivers e mantém apenas o maior DriverVer" {
        $contentRoot = Join-Path ([IO.Path]::GetTempPath()) "WinUtilIsoStaleDedup_$([guid]::NewGuid())"
        $installWim = Join-Path $contentRoot 'sources\install.wim'
        $template = Get-Content -Path $script:autoUnattendPath -Raw
        $logs = [System.Collections.Generic.List[string]]::new()

        New-WinUtilDriverExportHarness -Fixtures @(
            # Duplicata tripla espelhando o relatório real de ntprint.inf: apenas o DriverVer mais recente deve sobreviver.
            @{ Path = 'ntprint.inf_x86_7426e1b60aa62272'; Name = 'ntprint.inf'; Class = 'Printer'; DriverVer = '1/1/2023,10.0.26100.8875' },
            @{ Path = 'ntprint.inf_x86_6688e7b66f8d9fb5'; Name = 'ntprint.inf'; Class = 'Printer'; DriverVer = '1/1/2024,10.0.26100.8972' },
            @{ Path = 'ntprint.inf_x86_58e7118cdecb935e'; Name = 'ntprint.inf'; Class = 'Printer'; DriverVer = '6/1/2024,10.0.26100.9168' },
            # Um par duplicado em que um pacote não tem DriverVer: o que pode ser analisado deve vencer.
            @{ Path = 'sample.inf_amd64_11111111aaaaaaaa'; Name = 'sample.inf'; Class = 'Net' },
            @{ Path = 'sample.inf_amd64_22222222bbbbbbbb'; Name = 'sample.inf'; Class = 'Net'; DriverVer = '3/1/2024,1.2.3.4' },
            # Um par duplicado baseado inteiramente na análise de DriverVer sem diferenciar maiúsculas: o DRIVERVER
            # em maiúsculas no pacote mais novo ainda deve ser lido e vencer a comparação.
            @{ Path = 'caps.inf_amd64_33333333cccccccc'; Name = 'caps.inf'; Class = 'Net'; DriverVer = '1/1/2020,1.0.0.0'; VersionKeyword = 'driverver' },
            @{ Path = 'caps.inf_amd64_44444444dddddddd'; Name = 'caps.inf'; Class = 'Net'; DriverVer = '1/1/2021,2.0.0.0'; VersionKeyword = 'DRIVERVER' }
        )

        try {
            New-Item -Path (Split-Path $installWim -Parent) -ItemType Directory -Force | Out-Null
            Set-Content -Path $installWim -Value 'mock-wim'
            . $script:isoScriptPath
            Invoke-WinUtilISOScript -ISOContentsDir $contentRoot -AutoUnattendXml $template -InjectCurrentSystemDrivers $true -InstallImagePath $installWim -InstallImageIndex 6 -InstallEditionId 'Professional' -Log {
                param($message)
                $logs.Add([string]$message)
            }

            @($script:dismCalls | Where-Object { $_ -match '/Add-Driver' }).Count | Should -Be 3
            ($logs -join '|') | Should -Match 'Exportados 3 de 7 pacotes de driver \(4 excluídos\)'
            ($logs -join '|') | Should -Match "Excluindo o pacote de driver duplicado e desatualizado '.*ntprint\.inf_x86_7426e1b60aa62272' \(DriverVer 1/1/2023,10\.0\.26100\.8875\), substituído por '.*ntprint\.inf_x86_58e7118cdecb935e'"
            ($logs -join '|') | Should -Match "Excluindo o pacote de driver duplicado e desatualizado '.*ntprint\.inf_x86_6688e7b66f8d9fb5' \(DriverVer 1/1/2024,10\.0\.26100\.8972\), substituído por '.*ntprint\.inf_x86_58e7118cdecb935e'"
            ($logs -join '|') | Should -Match "Excluindo o pacote de driver duplicado e desatualizado '.*sample\.inf_amd64_11111111aaaaaaaa' \(DriverVer desconhecida\), substituído por '.*sample\.inf_amd64_22222222bbbbbbbb' \(DriverVer 3/1/2024,1\.2\.3\.4\)"
            ($logs -join '|') | Should -Match "Excluindo o pacote de driver duplicado e desatualizado '.*caps\.inf_amd64_33333333cccccccc' \(DriverVer 1/1/2020,1\.0\.0\.0\), substituído por '.*caps\.inf_amd64_44444444dddddddd' \(DriverVer 1/1/2021,2\.0\.0\.0\)"

            $script:exportRootAtAddDriver | Should -Not -Contain (Join-Path $script:driverExportRoot 'ntprint.inf_x86_7426e1b60aa62272')
            $script:exportRootAtAddDriver | Should -Not -Contain (Join-Path $script:driverExportRoot 'ntprint.inf_x86_6688e7b66f8d9fb5')
            $script:exportRootAtAddDriver | Should -Not -Contain (Join-Path $script:driverExportRoot 'sample.inf_amd64_11111111aaaaaaaa')
            $script:exportRootAtAddDriver | Should -Not -Contain (Join-Path $script:driverExportRoot 'caps.inf_amd64_33333333cccccccc')
            $script:exportRootAtAddDriver | Should -Contain (Join-Path $script:driverExportRoot 'ntprint.inf_x86_58e7118cdecb935e')
            $script:exportRootAtAddDriver | Should -Contain (Join-Path $script:driverExportRoot 'sample.inf_amd64_22222222bbbbbbbb')
            $script:exportRootAtAddDriver | Should -Contain (Join-Path $script:driverExportRoot 'caps.inf_amd64_44444444dddddddd')
        } finally {
            Remove-Item Function:\dism.exe -ErrorAction SilentlyContinue
            Remove-Item -Path $contentRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "descarta alterações parciais e confirma os demais drivers quando um pacote falha ao ser adicionado" {
        $contentRoot = Join-Path ([IO.Path]::GetTempPath()) "WinUtilIsoDriverPartial_$([guid]::NewGuid())"
        $installWim = Join-Path $contentRoot 'sources\install.wim'
        $template = Get-Content -Path $script:autoUnattendPath -Raw
        $logs = [System.Collections.Generic.List[string]]::new()
        New-WinUtilDriverExportHarness -Fixtures $script:resilienceDriverFixtures -FailedDriverPath 'group_a\duplicate'

        try {
            New-Item -Path (Split-Path $installWim -Parent) -ItemType Directory -Force | Out-Null
            Set-Content -Path $installWim -Value 'mock-wim'
            . $script:isoScriptPath
            $driversInjected = [ref]$false
            Invoke-WinUtilISOScript -ISOContentsDir $contentRoot -AutoUnattendXml $template -InjectCurrentSystemDrivers $true -InstallImagePath $installWim -InstallImageIndex 6 -InstallEditionId 'Professional' -DriversInjected $driversInjected -Log {
                param($message)
                $logs.Add([string]$message)
            }

            @($script:dismCalls | Where-Object { $_ -match '/Mount-Image' }).Count | Should -Be 2
            @($script:dismCalls | Where-Object { $_ -match '/Unmount-Image\|.*\|/Commit' }).Count | Should -Be 1
            @($script:dismCalls | Where-Object { $_ -match '/Unmount-Image\|.*\|/Discard' }).Count | Should -Be 1

            $lastMountCall = $script:dismCalls | Where-Object { $_ -match '/Mount-Image' } | Select-Object -Last 1
            $lastMountIndex = [Array]::LastIndexOf($script:dismCalls.ToArray(), $lastMountCall)
            $finalMountCalls = @($script:dismCalls[($lastMountIndex + 1)..($script:dismCalls.Count - 1)])
            @($finalMountCalls | Where-Object { $_ -match '/Add-Driver' }).Count | Should -Be ($script:expectedRootPackages - 1)
            ($finalMountCalls -join "`n") | Should -Not -Match ([regex]::Escape('group_a\duplicate'))

            ($logs -join '|') | Should -Match "Adicionados $($script:expectedRootPackages - 1) de $script:expectedRootPackages pacotes de driver"
            ($logs -join '|') | Should -Match 'validação dos metadados do install.wim passou'
            # group_a e group_b compartilham um nome-folha, então o aviso deve identificar o pacote
            # com falha por seu subcaminho; um nome só de folha apareceria como 'duplicate' e seria ambíguo.
            ($logs -join '|') | Should -Match ([regex]::Escape("falha ao adicionar o pacote de driver 'group_a\duplicate'"))
            ($logs -join '|') | Should -Match ([regex]::Escape('add-driver:group_b\duplicate concluído'))
            $driversInjected.Value | Should -BeTrue
        } finally {
            Remove-Item Function:\dism.exe -ErrorAction SilentlyContinue
            Remove-Item -Path $contentRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "descarta a montagem e continua quando todos os pacotes de driver falham ao ser adicionados" {
        $contentRoot = Join-Path ([IO.Path]::GetTempPath()) "WinUtilIsoDriverAllFail_$([guid]::NewGuid())"
        $installWim = Join-Path $contentRoot 'sources\install.wim'
        $template = Get-Content -Path $script:autoUnattendPath -Raw
        $logs = [System.Collections.Generic.List[string]]::new()
        New-WinUtilDriverExportHarness -Fixtures $script:resilienceDriverFixtures -FailAllAddDrivers

        try {
            New-Item -Path (Split-Path $installWim -Parent) -ItemType Directory -Force | Out-Null
            Set-Content -Path $installWim -Value 'mock-wim'
            . $script:isoScriptPath
            $driversInjected = [ref]$true
            Invoke-WinUtilISOScript -ISOContentsDir $contentRoot -AutoUnattendXml $template -InjectCurrentSystemDrivers $true -InstallImagePath $installWim -InstallImageIndex 6 -InstallEditionId 'Professional' -DriversInjected $driversInjected -Log {
                param($message)
                $logs.Add([string]$message)
            }

            @($script:dismCalls | Where-Object { $_ -match '/Add-Driver' }).Count | Should -Be $script:expectedRootPackages
            @($script:dismCalls | Where-Object { $_ -match '/Unmount-Image\|.*\|/Commit' }).Count | Should -Be 0
            @($script:dismCalls | Where-Object { $_ -match '/Mount-Image' }).Count | Should -Be $script:expectedRootPackages
            @($script:dismCalls | Where-Object { $_ -match '/Unmount-Image\|.*\|/Discard' }).Count | Should -Be $script:expectedRootPackages
            @($script:dismCalls | Where-Object { $_ -match '/Get-WimInfo' }).Count | Should -Be 1

            ($logs -join '|') | Should -Match "nenhum dos $script:expectedRootPackages pacotes de driver exportados pôde ser adicionado"
            ($logs -join '|') | Should -Not -Match "Adicionados 0 de $script:expectedRootPackages"
            Test-Path (Join-Path $contentRoot '$WinpeDriver$') | Should -BeFalse
            $driversInjected.Value | Should -BeFalse
        } finally {
            Remove-Item Function:\dism.exe -ErrorAction SilentlyContinue
            Remove-Item -Path $contentRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "encontra drivers exportados quando o caminho temporário contém caracteres curinga" {
        $contentRoot = Join-Path ([IO.Path]::GetTempPath()) "WinUtilIsoDriverGlob_$([guid]::NewGuid())"
        $installWim = Join-Path $contentRoot 'sources\install.wim'
        $template = Get-Content -Path $script:autoUnattendPath -Raw
        $logs = [System.Collections.Generic.List[string]]::new()
        New-WinUtilDriverExportHarness -Fixtures $script:resilienceDriverFixtures

        # Uma conta do Windows chamada como "John [Work]" coloca caracteres curinga em %TEMP%.
        # Get-ChildItem -Path os interpretaria como curinga, não encontraria nada e abortaria toda a execução do ISO.
        $originalTemp = $env:TEMP
        $bracketTemp = Join-Path ([IO.Path]::GetTempPath()) "WinUtil [Glob] $([guid]::NewGuid())"

        try {
            New-Item -Path (Split-Path $installWim -Parent) -ItemType Directory -Force | Out-Null
            Set-Content -Path $installWim -Value 'mock-wim'
            New-Item -Path $bracketTemp -ItemType Directory -Force | Out-Null
            $env:TEMP = $bracketTemp
            . $script:isoScriptPath
            Invoke-WinUtilISOScript -ISOContentsDir $contentRoot -AutoUnattendXml $template -InjectCurrentSystemDrivers $true -InstallImagePath $installWim -InstallImageIndex 6 -InstallEditionId 'Professional' -Log {
                param($message)
                $logs.Add([string]$message)
            }

            ($logs -join '|') | Should -Match "Adicionados $script:expectedRootPackages de $script:expectedRootPackages pacotes de driver"
            @($script:dismCalls | Where-Object { $_ -match '/Unmount-Image\|.*\|/Commit' }).Count | Should -Be 1
            ($logs -join '|') | Should -Match ([regex]::Escape('add-driver:nested_pkg concluído'))
        } finally {
            $env:TEMP = $originalTemp
            Remove-Item Function:\dism.exe -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $bracketTemp -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $contentRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "para quando uma montagem potencialmente parcial não pode ser descartada após a falha de um pacote" {
        $contentRoot = Join-Path ([IO.Path]::GetTempPath()) "WinUtilIsoDriverDiscardFailure_$([guid]::NewGuid())"
        $installWim = Join-Path $contentRoot 'sources\install.wim'
        $template = Get-Content -Path $script:autoUnattendPath -Raw
        New-WinUtilDriverExportHarness -Fixtures $script:resilienceDriverFixtures -FailAllAddDrivers -FailDiscard

        try {
            New-Item -Path (Split-Path $installWim -Parent) -ItemType Directory -Force | Out-Null
            Set-Content -Path $installWim -Value 'mock-wim'
            . $script:isoScriptPath

            { Invoke-WinUtilISOScript -ISOContentsDir $contentRoot -AutoUnattendXml $template -InjectCurrentSystemDrivers $true -InstallImagePath $installWim -InstallImageIndex 6 -InstallEditionId 'Professional' } |
                Should -Throw '*Falha ao descartar a montagem potencialmente parcial de install.wim após a falha do pacote de driver*'

            @($script:dismCalls | Where-Object { $_ -match '/Unmount-Image\|.*\|/Discard' }).Count | Should -Be 2
            @($script:dismCalls | Where-Object { $_ -match '/Unmount-Image\|.*\|/Commit' }).Count | Should -Be 0
        } finally {
            Remove-Item Function:\dism.exe -ErrorAction SilentlyContinue
            Remove-Item -Path $contentRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "descarta um install.wim parcialmente montado após falha na montagem" {
        $contentRoot = Join-Path ([IO.Path]::GetTempPath()) "WinUtilIsoMountFailure_$([guid]::NewGuid())"
        $installWim = Join-Path $contentRoot 'sources\install.wim'
        $template = Get-Content -Path $script:autoUnattendPath -Raw
        $script:dismCalls = [System.Collections.Generic.List[string]]::new()

        function dism.exe {
            param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)

            $script:dismCalls.Add(($Arguments -join '|'))
            if ($Arguments -contains '/Get-WimInfo') {
                $global:LASTEXITCODE = 0
                'Languages : en-US'
                'Installation : Client'
                'Edition : Professional'
                'ProductSuite : Terminal Server'
                'ProductType : WinNT'
            } elseif ($Arguments -contains '/Mount-Image') {
                $global:LASTEXITCODE = 50
                'Mount failed'
            } elseif ($Arguments -contains '/Get-MountedImageInfo') {
                $global:LASTEXITCODE = 0
                "Mount Dir : $(Join-Path (Split-Path -Path $contentRoot -Parent) 'wim_mount')"
            } elseif ($Arguments -contains '/Export-Driver') {
                $global:LASTEXITCODE = 0
                Export-WinUtilTestDriverPackage -Arguments $Arguments -Fixtures @(
                    @{ Path = 'storage_pkg'; Name = 'iaStorAC.inf'; Class = 'System' }
                )
            } else {
                $global:LASTEXITCODE = 0
            }
        }

        try {
            New-Item -Path (Split-Path $installWim -Parent) -ItemType Directory -Force | Out-Null
            Set-Content -Path $installWim -Value 'mock-wim'
            . $script:isoScriptPath

            { Invoke-WinUtilISOScript -ISOContentsDir $contentRoot -AutoUnattendXml $template -InjectCurrentSystemDrivers $true -InstallImagePath $installWim -InstallImageIndex 6 -InstallEditionId 'Professional' } |
                Should -Throw '*DISM mount falhou*'

            @($script:dismCalls | Where-Object { $_ -match '/Get-MountedImageInfo' }).Count | Should -Be 1
            @($script:dismCalls | Where-Object { $_ -match '/Unmount-Image\|.*\|/Discard' }).Count | Should -Be 1
        } finally {
            Remove-Item Function:\dism.exe -ErrorAction SilentlyContinue
            Remove-Item -Path $contentRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "relata uma explicação amigável quando o DISM falha com um código de saída conhecido" {
        $contentRoot = Join-Path ([IO.Path]::GetTempPath()) "WinUtilIsoMountFailureKnownCode_$([guid]::NewGuid())"
        $installWim = Join-Path $contentRoot 'sources\install.wim'
        $template = Get-Content -Path $script:autoUnattendPath -Raw
        $script:dismCalls = [System.Collections.Generic.List[string]]::new()

        function dism.exe {
            param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)

            $script:dismCalls.Add(($Arguments -join '|'))
            if ($Arguments -contains '/Get-WimInfo') {
                $global:LASTEXITCODE = 0
                'Languages : en-US'
                'Installation : Client'
                'Edition : Professional'
                'ProductSuite : Terminal Server'
                'ProductType : WinNT'
            } elseif ($Arguments -contains '/Mount-Image') {
                $global:LASTEXITCODE = 112
                'Mount failed'
            } elseif ($Arguments -contains '/Get-MountedImageInfo') {
                $global:LASTEXITCODE = 0
                "Mount Dir : $(Join-Path (Split-Path -Path $contentRoot -Parent) 'wim_mount')"
            } elseif ($Arguments -contains '/Export-Driver') {
                $global:LASTEXITCODE = 0
                Export-WinUtilTestDriverPackage -Arguments $Arguments -Fixtures @(
                    @{ Path = 'storage_pkg'; Name = 'iaStorAC.inf'; Class = 'System' }
                )
            } else {
                $global:LASTEXITCODE = 0
            }
        }

        try {
            New-Item -Path (Split-Path $installWim -Parent) -ItemType Directory -Force | Out-Null
            Set-Content -Path $installWim -Value 'mock-wim'
            . $script:isoScriptPath

            { Invoke-WinUtilISOScript -ISOContentsDir $contentRoot -AutoUnattendXml $template -InjectCurrentSystemDrivers $true -InstallImagePath $installWim -InstallImageIndex 6 -InstallEditionId 'Professional' } |
                Should -Throw '*112*Disco cheio*'

            @($script:dismCalls | Where-Object { $_ -match '/Get-MountedImageInfo' }).Count | Should -Be 1
            @($script:dismCalls | Where-Object { $_ -match '/Unmount-Image\|.*\|/Discard' }).Count | Should -Be 1
        } finally {
            Remove-Item Function:\dism.exe -ErrorAction SilentlyContinue
            Remove-Item -Path $contentRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "usa o código de saída simples como fallback para uma falha do DISM não mapeada" {
        $contentRoot = Join-Path ([IO.Path]::GetTempPath()) "WinUtilIsoMountFailureUnknownCode_$([guid]::NewGuid())"
        $installWim = Join-Path $contentRoot 'sources\install.wim'
        $template = Get-Content -Path $script:autoUnattendPath -Raw
        $script:dismCalls = [System.Collections.Generic.List[string]]::new()

        function dism.exe {
            param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)

            $script:dismCalls.Add(($Arguments -join '|'))
            if ($Arguments -contains '/Get-WimInfo') {
                $global:LASTEXITCODE = 0
                'Languages : en-US'
                'Installation : Client'
                'Edition : Professional'
                'ProductSuite : Terminal Server'
                'ProductType : WinNT'
            } elseif ($Arguments -contains '/Mount-Image') {
                $global:LASTEXITCODE = 999
                'Mount failed'
            } elseif ($Arguments -contains '/Get-MountedImageInfo') {
                $global:LASTEXITCODE = 0
                "Mount Dir : $(Join-Path (Split-Path -Path $contentRoot -Parent) 'wim_mount')"
            } elseif ($Arguments -contains '/Export-Driver') {
                $global:LASTEXITCODE = 0
                Export-WinUtilTestDriverPackage -Arguments $Arguments -Fixtures @(
                    @{ Path = 'storage_pkg'; Name = 'iaStorAC.inf'; Class = 'System' }
                )
            } else {
                $global:LASTEXITCODE = 0
            }
        }

        try {
            New-Item -Path (Split-Path $installWim -Parent) -ItemType Directory -Force | Out-Null
            Set-Content -Path $installWim -Value 'mock-wim'
            . $script:isoScriptPath

            $thrown = $null
            try {
                Invoke-WinUtilISOScript -ISOContentsDir $contentRoot -AutoUnattendXml $template -InjectCurrentSystemDrivers $true -InstallImagePath $installWim -InstallImageIndex 6 -InstallEditionId 'Professional'
            } catch {
                $thrown = $_.Exception.Message
            }
            $thrown | Should -Be 'DISM mount falhou com o código de saída 999.'

            @($script:dismCalls | Where-Object { $_ -match '/Get-MountedImageInfo' }).Count | Should -Be 1
            @($script:dismCalls | Where-Object { $_ -match '/Unmount-Image\|.*\|/Discard' }).Count | Should -Be 1
        } finally {
            Remove-Item Function:\dism.exe -ErrorAction SilentlyContinue
            Remove-Item -Path $contentRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "não adiciona artefatos de configuração de drivers quando a injeção está desativada" {
        $contentRoot = Join-Path ([IO.Path]::GetTempPath()) "WinUtilIsoNoDrivers_$([guid]::NewGuid())"

        try {
            New-Item -Path $contentRoot -ItemType Directory -Force | Out-Null
            . $script:isoScriptPath
            Invoke-WinUtilISOScript -ISOContentsDir $contentRoot -AutoUnattendXml (Get-Content -Path $script:autoUnattendPath -Raw) -InjectCurrentSystemDrivers $false -InstallEditionId 'Core'

            Test-Path (Join-Path $contentRoot '$WinpeDriver$') | Should -BeFalse
            [xml]$answerFile = Get-Content -Path (Join-Path $contentRoot 'autounattend.xml') -Raw
            $nsMgr = New-Object System.Xml.XmlNamespaceManager($answerFile.NameTable)
            $nsMgr.AddNamespace('sg', 'https://schneegans.de/windows/unattend-generator/')
            $answerFile.SelectSingleNode('//sg:File[@path="C:\Windows\Setup\Scripts\WinUtil-InstallDrivers.ps1"]', $nsMgr) | Should -BeNullOrEmpty
        } finally {
            Remove-Item -Path $contentRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "habilita o fallback de configuration-set ao preparar scripts de configuração OEM" {
        $contentRoot = Join-Path ([IO.Path]::GetTempPath()) "WinUtilIsoFallback_$([guid]::NewGuid())"

        try {
            New-Item -Path $contentRoot -ItemType Directory -Force | Out-Null
            . $script:isoScriptPath
            Invoke-WinUtilISOScript -ISOContentsDir $contentRoot -AutoUnattendXml (Get-Content -Path $script:autoUnattendPath -Raw) -InstallEditionId 'Core'

            [xml]$answerFile = Get-Content -Path (Join-Path $contentRoot 'autounattend.xml') -Raw
            $nsMgr = New-Object System.Xml.XmlNamespaceManager($answerFile.NameTable)
            $nsMgr.AddNamespace('u', 'urn:schemas-microsoft-com:unattend')

            $answerFile.SelectSingleNode('/u:unattend/u:settings[@pass="windowsPE"]/u:component[@name="Microsoft-Windows-Setup"]/u:UseConfigurationSet', $nsMgr).InnerText |
                Should -Be 'true'
            Test-Path (Join-Path $contentRoot 'sources\$OEM$\$$\Setup\Scripts\FirstLogon.ps1') | Should -BeTrue
        } finally {
            Remove-Item -Path $contentRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "tenta instalar o oscdimg pelo winget e sai antes da exportação quando o fallback falha" {
        $content = Get-Content -Path $script:isoWorkflowPath -Raw

        foreach ($expectedText in @(
            'oscdimg.exe não encontrado. Tentando instalar via winget...',
            'Install-WinUtilWinget',
            'Get-Command winget',
            '$env:ProgramFiles\WinGet\Packages',
            '$env:ProgramFiles\WinGet\Links\oscdimg.exe',
            'install -e --id Microsoft.OSCDIMG --accept-package-agreements --accept-source-agreements',
            'oscdimg.exe ainda não encontrado após a tentativa de instalação.',
            'oscdimg Não Encontrado'
        )) {
            $content | Should -Match ([regex]::Escape($expectedText))
        }

        ([regex]::Matches($content, 'function Get-WinUtilOscdimgPath', 'IgnoreCase')).Count | Should -Be 1
        $content | Should -Match ([regex]::Escape('Write-WinUtilISOLog -Level "WARN" -Message "oscdimg.exe ainda não encontrado após a tentativa de instalação."'))

        # O job de exportação para no diálogo em vez de executar oscdimg sem o binário
        $exportOscdimgIndex = $script:exportFunction.IndexOf('$oscdimg = Get-WinUtilOscdimgPath')
        $exportDialogIndex = $script:exportFunction.IndexOf('oscdimg Não Encontrado', $exportOscdimgIndex)
        $exportRunIndex = $script:exportFunction.IndexOf('Executando oscdimg...', $exportOscdimgIndex)

        $exportOscdimgIndex | Should -BeGreaterThan -1
        $exportDialogIndex | Should -BeGreaterThan $exportOscdimgIndex
        $exportRunIndex | Should -BeGreaterThan $exportDialogIndex
        $script:exportFunction | Should -Match ([regex]::Escape('return'))
    }

    Context "Restauração dos serviços de atualização do FirstLogon" {
        BeforeAll {
            [xml]$unattend = Get-Content -LiteralPath $script:autoUnattendPath -Raw
            $firstLogon = $unattend.SelectSingleNode("//*[local-name()='File' and @path='C:\Windows\Setup\Scripts\FirstLogon.ps1']").InnerText
            $tokens = $null
            $parseErrors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseInput($firstLogon, [ref]$tokens, [ref]$parseErrors)
            if ($parseErrors.Count) { throw 'FirstLogon script failed to parse.' }
            $blocks = @($ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.ScriptBlockExpressionAst] -and
                    $node.ScriptBlock.Find({
                        param($command)
                        $command -is [System.Management.Automation.Language.CommandAst] -and
                            $command.GetCommandName() -eq 'Set-Service'
                    }, $false)
            }, $true))
            if ($blocks.Count -ne 1) { throw 'Expected exactly one service restoration block.' }
            # Nunca executar a limpeza, os downloads ou o instalador do FirstLogon ao redor.
            $commands = $blocks[0].ScriptBlock.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.CommandAst]
            }, $true)
            foreach ($command in $commands) {
                if ($command.GetCommandName() -notin @('reg.exe', 'Set-Service', 'Set-ItemProperty')) {
                    throw "Unexpected command in restoration block: $($command.Extent.Text)"
                }
            }
            $script:restoreServices = $blocks[0].ScriptBlock.GetScriptBlock()
            function reg.exe { param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments) }
        }

        BeforeEach {
            Mock reg.exe { }
            Mock Set-Service { }
            Mock Set-ItemProperty { }
        }

        It "restaura serviços comuns e grava diretamente o valor de inicialização protegido do Medic" {
            & $script:restoreServices

            Should -Invoke Set-Service -Times 3 -Exactly
            Should -Invoke Set-Service -Times 1 -Exactly -ParameterFilter { $Name -eq 'BITS' -and $StartupType -eq 'Manual' -and $ErrorAction -eq 'Continue' }
            Should -Invoke Set-Service -Times 1 -Exactly -ParameterFilter { $Name -eq 'wuauserv' -and $StartupType -eq 'Manual' -and $ErrorAction -eq 'Continue' }
            Should -Invoke Set-Service -Times 1 -Exactly -ParameterFilter { $Name -eq 'UsoSvc' -and $StartupType -eq 'Automatic' -and $ErrorAction -eq 'Continue' }
            Should -Invoke Set-Service -Times 0 -Exactly -ParameterFilter { $Name -eq 'WaaSMedicSvc' }
            Should -Invoke Set-ItemProperty -Times 1 -Exactly
            Should -Invoke Set-ItemProperty -Times 1 -Exactly -ParameterFilter {
                $Path -eq 'HKLM:\SYSTEM\CurrentControlSet\Services\WaaSMedicSvc' -and
                $Name -eq 'Start' -and $Value -eq 3 -and $Type -eq 'DWord' -and $ErrorAction -eq 'Continue'
            }
        }

        It "mantém as falhas observáveis enquanto tenta o restante do trabalho de restauração" {
            $script:restorationCalls = [System.Collections.Generic.List[string]]::new()
            Mock Set-Service {
                param($Name, $ErrorAction)
                $script:restorationCalls.Add($Name)
                if ($script:restorationCalls.Count -eq 1) {
                    Write-Error 'simulated service restoration failure' -ErrorAction $ErrorAction
                }
            }
            Mock Set-ItemProperty {
                param($ErrorAction)
                $script:restorationCalls.Add('Medic registry')
                Write-Error 'simulated Medic registry failure' -ErrorAction $ErrorAction
            }

            $output = @(& $script:restoreServices 2>&1)
            $failures = @($output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            $failures.Count | Should -Be 2
            $failures[0].Exception.Message | Should -Be 'simulated service restoration failure'
            $failures[1].Exception.Message | Should -Be 'simulated Medic registry failure'
            $script:restorationCalls.Count | Should -Be 4
            @($script:restorationCalls | Select-Object -First 3 | Sort-Object) | Should -Be @('BITS', 'UsoSvc', 'wuauserv')
            $script:restorationCalls[3] | Should -Be 'Medic registry'
        }
    }
}
