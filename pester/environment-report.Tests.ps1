#===========================================================================
# Testes - Relatório de ambiente
#===========================================================================

BeforeAll {
    $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
    . (Join-Path $script:repoRoot "functions\private\Write-WinUtilLog.ps1")
    . (Join-Path $script:repoRoot "functions\private\Get-WinUtilToggleStatus.ps1")
    . (Join-Path $script:repoRoot "functions\private\Invoke-WinUtilCurrentSystem.ps1")
    . (Join-Path $script:repoRoot "functions\private\Get-WinUtilTweaksStateReport.ps1")
    . (Join-Path $script:repoRoot "functions\private\Test-WinUtilPackageManager.ps1")
    . (Join-Path $script:repoRoot "functions\private\Get-WinUtilEnvironmentReport.ps1")
    . (Join-Path $script:repoRoot "functions\private\Get-WinUtilEnvironmentReportLogsPath.ps1")
    . (Join-Path $script:repoRoot "functions\private\Write-WinUtilEnvironmentReportExport.ps1")
}

Describe "Get-WinUtilEnvironmentReport" {
    BeforeEach {
        # Mantenha este Describe focado no esquema de nível superior; o agrupamento/detecção de
        # tweaksState tem seu próprio Describe dedicado abaixo, com sua própria fixture de registro.
        Mock Get-WinUtilTweaksStateReport {
            [pscustomobject]@{
                collectionStatus = "collected"
                essentialTweaks = [pscustomobject]@{}
                customizePreferences = [pscustomobject]@{}
                advancedTweaks = [pscustomobject]@{}
                performancePlans = [pscustomobject]@{}
                notEvaluable = @()
            }
        }

        Mock Get-CimInstance {
            switch ($ClassName) {
                "Win32_OperatingSystem" {
                    return [pscustomobject]@{
                        Caption = "Windows 11 Pro"
                        Version = "10.0.26100"
                        BuildNumber = "26100"
                        OSArchitecture = "64-bit"
                        TotalVisibleMemorySize = 16777216
                    }
                }
                "Win32_Processor" {
                    return [pscustomobject]@{
                        Name = "Example CPU"
                        NumberOfLogicalProcessors = 8
                    }
                }
            }
        }
        Mock Get-ExecutionPolicy { "RemoteSigned" }
        Mock Test-WinUtilPackageManager { "not-installed" }
        Mock Test-Path { $false }
        Mock Get-ItemProperty { $null }
        Mock Write-WinUtilLog { }
        Mock Write-Warning { }
    }

    It "retorna o esquema de relatório versionado com lista de permissões" {
        $report = Get-WinUtilEnvironmentReport

        $report.schemaVersion | Should -Be "1.0"
        $report.generatedAtUtc | Should -Match '^\d{4}-\d{2}-\d{2}T'
        $report.windows.edition | Should -Be "Windows 11 Pro"
        $report.hardware.cpuModel | Should -Be "Example CPU"
        $report.hardware.logicalProcessorCount | Should -Be 8
        $report.hardware.totalMemoryGB | Should -Be 16
        $report.powershell.PSObject.Properties.Name | Should -Be @("edition", "version", "executionPolicy")
        $report.powershell.executionPolicy | Should -Be "RemoteSigned"
        $report.packageManagers.PSObject.Properties.Name | Should -Be @("winget", "chocolatey")
        $report.system.PSObject.Properties.Name | Should -Be @("pendingRebootRequired")
        $report.PSObject.Properties.Name | Should -Not -Contain "windowsFeatures"
        $report.PSObject.Properties.Name | Should -Contain "tweaksState"
    }

    It "não contém campos fora do esquema de relatório aprovado" {
        # Afirmações exatas de nomes de propriedades, não uma lista de bloqueio de nomes específicos - uma lista
        # de bloqueio só pega campos que alguém lembrou de listar e deixaria passar um futuro "biosUuid" ou "userSid".
        # As chaves dinâmicas de ajustes nos grupos de tweaksState não são verificadas aqui de propósito.
        $report = Get-WinUtilEnvironmentReport

        $report.PSObject.Properties.Name | Should -Be @(
            "schemaVersion", "generatedAtUtc", "windows", "hardware", "powershell",
            "packageManagers", "system", "tweaksState"
        )
        $report.windows.PSObject.Properties.Name | Should -Be @("edition", "version", "buildNumber", "architecture")
        $report.hardware.PSObject.Properties.Name | Should -Be @("cpuModel", "logicalProcessorCount", "totalMemoryGB")
        $report.packageManagers.winget.PSObject.Properties.Name | Should -Be @("installed", "version")
        $report.packageManagers.chocolatey.PSObject.Properties.Name | Should -Be @("installed", "version")
        $report.tweaksState.PSObject.Properties.Name | Should -Be @(
            "collectionStatus", "essentialTweaks", "customizePreferences", "advancedTweaks",
            "performancePlans", "notEvaluable"
        )
    }

    It "não reporta um gerenciador de pacotes como instalado a menos que Test-WinUtilPackageManager confirme" {
        $report = Get-WinUtilEnvironmentReport

        $report.packageManagers.winget.installed | Should -BeFalse
        $report.packageManagers.winget.version | Should -BeNullOrEmpty
        $report.packageManagers.chocolatey.installed | Should -BeFalse
        $report.packageManagers.chocolatey.version | Should -BeNullOrEmpty
    }

    It "lê a versão de um gerenciador de pacotes por meio da própria opção -v após a instalação ser confirmada" {
        Mock Test-WinUtilPackageManager { "installed" } -ParameterFilter { $winget }
        Mock winget { "v1.29.290" }

        $report = Get-WinUtilEnvironmentReport

        $report.packageManagers.winget.installed | Should -BeTrue
        $report.packageManagers.winget.version | Should -Be "v1.29.290"
    }

    It "não trata uma mensagem de falha na sondagem do gerenciador de pacotes como versão" {
        Mock Test-WinUtilPackageManager { "installed" } -ParameterFilter { $winget }
        Mock winget {
            $global:LASTEXITCODE = 7
            "WinGet failed to initialize"
        }

        $report = Get-WinUtilEnvironmentReport

        $report.packageManagers.winget.installed | Should -BeTrue
        $report.packageManagers.winget.version | Should -BeNullOrEmpty
        Should -Invoke Write-WinUtilLog -ParameterFilter {
            $Level -eq "WARN" -and $Message -like "Falha ao ler a versão do WinGet:*código 7*"
        }
        Should -Invoke Write-Warning -ParameterFilter {
            $Message -like "Falha ao ler a versão do WinGet:*código 7*"
        }
    }

    It "expõe um relatório incompleto do estado dos ajustes como aviso" {
        Mock Get-WinUtilTweaksStateReport {
            [pscustomobject]@{ collectionStatus = "unavailable" }
        }

        Get-WinUtilEnvironmentReport | Out-Null

        Should -Invoke Write-Warning -ParameterFilter {
            $Message -eq "Falha ao coletar o estado completo dos ajustes para o relatório de ambiente."
        }
    }

    It "sinaliza uma reinicialização pendente a partir de PendingFileRenameOperations" {
        Mock Get-ItemProperty {
            [pscustomobject]@{ PendingFileRenameOperations = @("a", "b") }
        }

        $report = Get-WinUtilEnvironmentReport

        $report.system.pendingRebootRequired | Should -BeTrue
    }

    It "não sinaliza reinicialização pendente para um valor PendingFileRenameOperations presente, mas vazio" {
        Mock Get-ItemProperty {
            [pscustomobject]@{ PendingFileRenameOperations = @() }
        }

        $report = Get-WinUtilEnvironmentReport

        $report.system.pendingRebootRequired | Should -BeFalse
    }

    It "reporta o estado de reinicialização pendente como desconhecido quando uma leitura do registro falha" {
        Mock Get-ItemProperty { throw "registry access denied" }

        $report = Get-WinUtilEnvironmentReport

        $report.system.pendingRebootRequired | Should -BeNullOrEmpty
        Should -Invoke Write-Warning -ParameterFilter {
            $Message -like "Falha ao verificar o estado de reinicialização pendente no registro:*registry access denied*"
        }
    }

}

Describe "Get-WinUtilEnvironmentReportLogsPath" {
    It "troca a extensão JSON pelo sufixo _logs.txt" {
        Get-WinUtilEnvironmentReportLogsPath -JsonPath "C:\Reports\WinUtilEnvironmentReport_20260101.json" |
            Should -Be "C:\Reports\WinUtilEnvironmentReport_20260101_logs.txt"
    }

    It "lida com um caminho sem extensão" {
        Get-WinUtilEnvironmentReportLogsPath -JsonPath "C:\Reports\Report" |
            Should -Be "C:\Reports\Report_logs.txt"
    }
}

Describe "Proteção contra sobrescrita em Invoke-WPFExportEnvironmentReport" {
    It "verifica o caminho de logs derivado literalmente" {
        $source = Get-Content -LiteralPath (Join-Path $script:repoRoot "functions\public\Invoke-WPFExportEnvironmentReport.ps1") -Raw

        $source | Should -Match 'Test-Path\s+-LiteralPath\s+\$logsPath'
    }

    It "aborta em vez de manter um arquivo complementar obsoleto quando os logs são excluídos" {
        $source = Get-Content -LiteralPath (Join-Path $script:repoRoot "functions\public\Invoke-WPFExportEnvironmentReport.ps1") -Raw

        $source | Should -Match 'if \(-not \$includeLogs\) \{[\s\S]*Escolha outro nome para o relatório[\s\S]*return'
        $source | Should -Match 'if \(-not \$replaceLogs\) \{\s*return\s*\}'
    }
}

Describe "Write-WinUtilEnvironmentReportExport" {
    BeforeEach {
        $script:rollbackJsonPath = $null
        $script:removeAttempts = [System.Collections.Generic.List[string]]::new()
    }

    It "restaura o JSON anterior quando a publicação do complemento de logs falha" {
        $jsonPath = Join-Path $TestDrive "report.json"
        $logsPath = Join-Path $TestDrive "report_logs.txt"
        [System.IO.File]::WriteAllText($jsonPath, "old report")
        $null = New-Item -ItemType Directory -Path $logsPath

        {
            Write-WinUtilEnvironmentReportExport -JsonPath $jsonPath -Json "new report" `
                -LogsPath $logsPath -Logs "new logs" -IncludeLogs
        } | Should -Throw

        [System.IO.File]::ReadAllText($jsonPath) | Should -Be "old report"
        [System.IO.Directory]::Exists($logsPath) | Should -BeTrue
        @(Get-ChildItem -LiteralPath $TestDrive -File).Name | Should -Be @("report.json")
    }

    It "mantém a cópia de recuperação e ainda tenta a reversão dos logs quando a restauração do JSON falha" {
        $jsonPath = Join-Path $TestDrive "rollback-report.json"
        $logsPath = Join-Path $TestDrive "rollback-report_logs.txt"
        [System.IO.File]::WriteAllText($jsonPath, "old report")
        $null = New-Item -ItemType Directory -Path $logsPath
        $script:rollbackJsonPath = $jsonPath
        Mock Copy-WinUtilEnvironmentReportExportFile {
            if ($SourcePath -like "*.bak" -and $DestinationPath -eq $script:rollbackJsonPath) {
                throw "JSON restore blocked"
            }
            [System.IO.File]::Copy($SourcePath, $DestinationPath, [bool]$Overwrite)
        }

        {
            Write-WinUtilEnvironmentReportExport -JsonPath $jsonPath -Json "new report" `
                -LogsPath $logsPath -Logs "new logs" -IncludeLogs
        } | Should -Throw "*Recovery copy retained*"

        [System.IO.File]::ReadAllText($jsonPath) | Should -Be "new report"
        $backup = @(Get-ChildItem -LiteralPath $TestDrive -Filter "rollback-report.json.*.bak" -File)
        $backup.Count | Should -Be 1
        [System.IO.File]::ReadAllText($backup[0].FullName) | Should -Be "old report"
        [System.IO.Directory]::Exists($logsPath) | Should -BeTrue
    }

    It "não permite que uma falha de limpeza de arquivo temporário oculte uma exportação bem-sucedida" {
        $jsonPath = Join-Path $TestDrive "cleanup-report.json"
        $logsPath = Join-Path $TestDrive "cleanup-report_logs.txt"
        Mock Remove-WinUtilEnvironmentReportExportFile {
            $script:removeAttempts.Add($Path)
            if ($Path -like "$jsonPath.*.tmp") {
                throw "temporary file is locked"
            }
            [System.IO.File]::Delete($Path)
        }

        {
            Write-WinUtilEnvironmentReportExport -JsonPath $jsonPath -Json "new report" `
                -LogsPath $logsPath -Logs "new logs" -IncludeLogs
        } | Should -Not -Throw

        [System.IO.File]::ReadAllText($jsonPath) | Should -Be "new report"
        [System.IO.File]::ReadAllText($logsPath) | Should -Be "new logs"
        @($script:removeAttempts | Where-Object { $_ -like "*.tmp" }).Count | Should -Be 2
    }
}

Describe "Get-WinUtilTweaksStateReport" {
    BeforeEach {
        $script:sync = [Hashtable]::Synchronized(@{
            configs = @{
                tweaks = [pscustomobject]@{
                    WPFTweaksApplied     = [pscustomobject]@{
                        category = "Essential Tweaks"
                        registry = @([pscustomobject]@{ Path = "HKCU:\Fake1"; Name = "Enabled"; Value = "1"; OriginalValue = "0"; DefaultState = "true" })
                    }
                    WPFTweaksNotApplied  = [pscustomobject]@{
                        category = "Essential Tweaks"
                        registry = @([pscustomobject]@{ Path = "HKCU:\Fake2"; Name = "Enabled"; Value = "1"; OriginalValue = "0"; DefaultState = "false" })
                    }
                    WPFToggleCustomize   = [pscustomobject]@{
                        category = "Customize Preferences"
                        Type     = "Toggle"
                        registry = @([pscustomobject]@{ Path = "HKCU:\Fake3"; Name = "Enabled"; Value = "1"; OriginalValue = "0"; DefaultState = "true" })
                    }
                    WPFTweaksAdvanced    = [pscustomobject]@{
                        category = "z__Advanced Tweaks - CAUTION"
                        registry = @([pscustomobject]@{ Path = "HKCU:\Fake4"; Name = "Enabled"; Value = "1"; OriginalValue = "0"; DefaultState = "false" })
                    }
                    WPFComboExample      = [pscustomobject]@{
                        category = "Customize Preferences"
                        Type     = "Combobox"
                    }
                    WPFButtonExample     = [pscustomobject]@{
                        category = "z__Advanced Tweaks - CAUTION"
                        Type     = "Button"
                    }
                    WPFScriptOnly        = [pscustomobject]@{
                        category = "Essential Tweaks"
                    }
                    WPFUnknownCategory   = [pscustomobject]@{
                        category = "Some Unmapped Category"
                        registry = @([pscustomobject]@{ Path = "HKCU:\Fake5"; Name = "Enabled"; Value = "1"; OriginalValue = "0"; DefaultState = "true" })
                    }
                }
            }
        })

        Mock Get-PSDrive { [pscustomobject]@{ Name = "HKU" } } -ParameterFilter { $Name -eq "HKU" }
        Mock New-PSDrive { }
        Mock Test-Path { $false }
        Mock Get-ItemProperty { $null }
        Mock Write-WinUtilLog { }
    }

    It "agrupa ajustes aplicados/não aplicados e interruptores por categoria" {
        $result = Get-WinUtilTweaksStateReport

        $result.collectionStatus | Should -Be "collected"
        $result.essentialTweaks.WPFTweaksApplied | Should -BeTrue
        $result.essentialTweaks.WPFTweaksNotApplied | Should -BeFalse
        $result.customizePreferences.WPFToggleCustomize | Should -BeTrue
        $result.advancedTweaks.WPFTweaksAdvanced | Should -BeFalse
        @($result.performancePlans.PSObject.Properties).Count | Should -Be 0
    }

    It "lê o estado ao vivo do interruptor em vez do estado em cache da interface" {
        $script:sync.ToggleStatusCache = @{ WPFToggleCustomize = $true }
        Mock Test-Path { $Path -eq "HKCU:\Fake3" }
        Mock Get-ItemProperty { [pscustomobject]@{ Enabled = "0" } } -ParameterFilter {
            $Path -eq "HKCU:\Fake3"
        }

        $result = Get-WinUtilTweaksStateReport

        $result.customizePreferences.WPFToggleCustomize | Should -BeFalse
        $script:sync.ToggleStatusCache.WPFToggleCustomize | Should -BeTrue
        Should -Invoke -CommandName Get-ItemProperty -Times 1 -Exactly -ParameterFilter {
            $Path -eq "HKCU:\Fake3"
        }
    }

    It "reporta a coleta como indisponível quando uma leitura ao vivo do registro falha" {
        Mock Test-Path { $Path -eq "HKCU:\Fake3" }
        Mock Get-ItemProperty { Write-Error -Message "Registry access denied" -ErrorAction Stop } -ParameterFilter {
            $Path -eq "HKCU:\Fake3"
        }

        $result = Get-WinUtilTweaksStateReport

        $result.collectionStatus | Should -Be "unavailable"
        @($result.customizePreferences.PSObject.Properties).Count | Should -Be 0
    }

    It "reporta a coleta como indisponível quando um serviço configurado não pode ser lido" {
        $script:sync.configs.tweaks | Add-Member -MemberType NoteProperty -Name WPFTweaksMissingService -Value ([pscustomobject]@{
            category = "Essential Tweaks"
            service = @([pscustomobject]@{ Name = "MissingService"; StartupType = "Disabled" })
        })
        Mock Get-Service { throw "Service access failed" } -ParameterFilter { $Name -eq "MissingService" }

        $result = Get-WinUtilTweaksStateReport

        $result.collectionStatus | Should -Be "unavailable"
        @($result.essentialTweaks.PSObject.Properties).Count | Should -Be 0
    }

    It "marca como falso apenas o ajuste afetado quando um serviço configurado está ausente" {
        $script:sync.configs.tweaks | Add-Member -MemberType NoteProperty -Name WPFTweaksMissingService -Value ([pscustomobject]@{
            category = "Essential Tweaks"
            service = @([pscustomobject]@{ Name = "MissingService"; StartupType = "Disabled" })
        })
        Mock Get-Service {
            Write-Error -Message "Cannot find any service with service name 'MissingService'." `
                -Category ObjectNotFound -ErrorId NoServiceFoundForGivenName -ErrorAction Stop
        } -ParameterFilter { $Name -eq "MissingService" }

        $result = Get-WinUtilTweaksStateReport

        $result.collectionStatus | Should -Be "collected"
        $result.essentialTweaks.WPFTweaksApplied | Should -BeTrue
        $result.essentialTweaks.WPFTweaksMissingService | Should -BeFalse
    }

    It "lista os ajustes do tipo lista suspensa e apenas script como não avaliáveis, em vez de descartá-los silenciosamente" {
        $result = Get-WinUtilTweaksStateReport

        $result.notEvaluable | Should -Contain "WPFComboExample"
        $result.notEvaluable | Should -Contain "WPFScriptOnly"
    }

    It "exclui totalmente botões de ação e categorias não mapeadas" {
        $result = Get-WinUtilTweaksStateReport

        $result.advancedTweaks.PSObject.Properties.Name | Should -Not -Contain "WPFButtonExample"
        $result.notEvaluable | Should -Not -Contain "WPFButtonExample"
        $result.notEvaluable | Should -Not -Contain "WPFUnknownCategory"
        ($result.essentialTweaks.PSObject.Properties.Name +
         $result.customizePreferences.PSObject.Properties.Name +
         $result.advancedTweaks.PSObject.Properties.Name +
         $result.performancePlans.PSObject.Properties.Name) | Should -Not -Contain "WPFUnknownCategory"
    }

    It "retorna grupos vazios em vez de lançar exceção quando Invoke-WinUtilCurrentSystem falha" {
        Mock Invoke-WinUtilCurrentSystem { throw "Registry access denied" }

        # Chamar isso diretamente (em vez de um bloco de script encapsulado encaminhado a Should -Not -Throw) evita
        # uma armadilha de escopo do PowerShell em que uma atribuição nesse bloco não se propaga de forma
        # confiável a este escopo - uma exceção não capturada aqui ainda falha o teste de qualquer forma.
        $result = Get-WinUtilTweaksStateReport

        # Grupos vazios sozinhos seriam indistinguíveis de uma varredura bem-sucedida que não
        # encontrou nada relevante, então collectionStatus é o que realmente registra que esta execução falhou.
        $result.collectionStatus | Should -Be "unavailable"
        $result.essentialTweaks.PSObject.Properties.Name | Should -Not -Contain "WPFTweaksApplied"
        @($result.essentialTweaks.PSObject.Properties).Count | Should -Be 0
        @($result.customizePreferences.PSObject.Properties).Count | Should -Be 0
        @($result.advancedTweaks.PSObject.Properties).Count | Should -Be 0
        @($result.performancePlans.PSObject.Properties).Count | Should -Be 0
        $result.notEvaluable | Should -BeNullOrEmpty
    }
}
