#====================================================================# Testes - Arquivos de configuração
#====================================================================
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$configRoot = Join-Path $PSScriptRoot "..\config"
$functionRoot = Join-Path $repoRoot "functions"
$xamlPath = Join-Path $repoRoot "xaml\inputXML.xaml"
$mainScriptPath = Join-Path $repoRoot "scripts\main.ps1"
$buttonScriptPath = Join-Path $repoRoot "functions\public\Invoke-WPFButton.ps1"
$configCases = @(
    Get-ChildItem -Path $configRoot -Filter *.json | ForEach-Object {
        @{
            Name = $_.Name
            Path = $_.FullName
        }
    }
)

BeforeAll {
    $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
    $script:configRoot = Join-Path $script:repoRoot "config"
    $script:functionRoot = Join-Path $script:repoRoot "functions"
    $script:xamlPath = Join-Path $script:repoRoot "xaml\inputXML.xaml"
    $script:mainScriptPath = Join-Path $script:repoRoot "scripts\main.ps1"
    $script:buttonScriptPath = Join-Path $script:repoRoot "functions\public\Invoke-WPFButton.ps1"

function script:Get-WinUtilConfigObject {
    param([string]$Name)

    Get-Content -Path (Join-Path $script:configRoot "$Name.json") -Raw | ConvertFrom-Json
}

function script:Test-WinUtilHasProperty {
    param(
        [Parameter(Mandatory)]
        [psobject]$Object,

        [Parameter(Mandatory)]
        [string]$Name
    )

    return @($Object.PSObject.Properties.Name) -contains $Name
}

function script:Test-WinUtilHasNonEmptyProperty {
    param(
        [Parameter(Mandatory)]
        [psobject]$Object,

        [Parameter(Mandatory)]
        [string]$Name
    )

    if (-not (Test-WinUtilHasProperty -Object $Object -Name $Name)) {
        return $false
    }

    $value = $Object.$Name
    if ($null -eq $value) {
        return $false
    }

    if ($value -is [string]) {
        return -not [string]::IsNullOrWhiteSpace($value)
    }

    if ($value -is [array]) {
        return @($value).Count -gt 0
    }

    return -not [string]::IsNullOrWhiteSpace([string]$value)
}

function script:Get-WinUtilMissingRequiredFields {
    param(
        [Parameter(Mandatory)]
        [string]$EntryName,

        [Parameter(Mandatory)]
        [psobject]$Entry,

        [Parameter(Mandatory)]
        [string[]]$RequiredFields
    )

    foreach ($field in $RequiredFields) {
        if (-not (Test-WinUtilHasNonEmptyProperty -Object $Entry -Name $field)) {
            "$EntryName missing $field"
        }
    }
}

function script:Get-WinUtilTopLevelFunctionNames {
    Get-ChildItem -Path $script:functionRoot -Filter *.ps1 -Recurse | ForEach-Object {
        $tokens = $null
        $syntaxErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$syntaxErrors)
        if ($syntaxErrors.Count -ne 0) {
            throw ($syntaxErrors | Out-String)
        }

        $ast.EndBlock.Statements |
            Where-Object { $_ -is [System.Management.Automation.Language.FunctionDefinitionAst] } |
            ForEach-Object { $_.Name }
    } | Sort-Object -Unique
}

function script:Get-WinUtilButtonSwitchNames {
    $buttonSource = Get-Content -Path $script:buttonScriptPath -Raw
    [regex]::Matches($buttonSource, '"(WPF[A-Za-z0-9_]+)"\s*\{') |
        ForEach-Object { $_.Groups[1].Value } |
        Sort-Object -Unique
}

# Substitutos para que o manipulador do Defender extraído do ajuste de Telemetria possa
# rodar em um teste sem tocar no Defender nem no arquivo de log real.
function script:Set-MpPreference {
    [CmdletBinding()]
    param([int]$SubmitSamplesConsent)

    throw "Set-MpPreference must be mocked: $SubmitSamplesConsent"
}

function script:Write-WinUtilLog {
    param($Level, $Component, $Message)
}
}

Describe "Arquivos de configuração" {
    foreach ($configCase in $configCases) {
        It "importa $($configCase.Name) sem erros de JSON" -TestCases $configCase {
            param([string]$Name, [string]$Path)

            try {
                Get-Content -Path $Path -Raw | ConvertFrom-Json | Out-Null
            } catch {
                throw "Failed to import ${Name}: $_"
            }
        }
    }
}

Describe "Configuração de aplicativos" {
    $testCase = @{ Path = (Join-Path $configRoot "applications.json") }

    It "contém pelo menos um aplicativo" -TestCases $testCase {
        param([string]$Path)

        $applications = Get-Content -Path $Path -Raw | ConvertFrom-Json
        $applicationEntries = @($applications.PSObject.Properties)

        if ($applicationEntries.Count -eq 0) {
            throw "applications.json does not contain any application entries."
        }
    }

    It "contém os campos de exibição obrigatórios e pelo menos uma fonte de instalação" -TestCases $testCase {
        param([string]$Path)

        $applications = Get-Content -Path $Path -Raw | ConvertFrom-Json
        $requiredFields = @("category", "content", "description", "link")
        $invalidEntries = New-Object System.Collections.Generic.List[string]

        foreach ($entry in $applications.PSObject.Properties) {
            $entryFields = @($entry.Value.PSObject.Properties.Name)

            foreach ($field in $requiredFields) {
                if ($entryFields -notcontains $field -or [string]::IsNullOrWhiteSpace([string]$entry.Value.$field)) {
                    $invalidEntries.Add("$($entry.Name) missing $field")
                }
            }

            $hasInstallSource = $false
            foreach ($sourceField in @("winget", "choco")) {
                if ($entryFields -contains $sourceField -and -not [string]::IsNullOrWhiteSpace([string]$entry.Value.$sourceField)) {
                    $hasInstallSource = $true
                }
            }

            if (-not $hasInstallSource) {
                $invalidEntries.Add("$($entry.Name) missing winget/choco install source")
            }
        }

        if ($invalidEntries.Count -gt 0) {
            throw ($invalidEntries -join "`n")
        }
    }
}

Describe "Configuração de ajustes" {
    $testCase = @{ Path = (Join-Path $configRoot "tweaks.json") }

    It "contém metadados de desfazer para ações de registro e serviço" -TestCases $testCase {
        param([string]$Path)

        $tweaks = Get-Content -Path $Path -Raw | ConvertFrom-Json
        $invalidTweaks = New-Object System.Collections.Generic.List[string]

        foreach ($tweak in $tweaks.PSObject.Properties) {
            foreach ($registryEntry in @($tweak.Value.registry)) {
                if ($null -eq $registryEntry) { continue }

                if ($registryEntry.Values) {
                    if ($registryEntry.PSObject.Properties.Name -notcontains "DefaultValue" -or
                        [string]::IsNullOrWhiteSpace([string]$registryEntry.DefaultValue)) {
                        $invalidTweaks.Add("$($tweak.Name),registry")
                    }
                    continue
                }

                if ($registryEntry.PSObject.Properties.Name -notcontains "OriginalValue" -or
                    [string]::IsNullOrWhiteSpace([string]$registryEntry.OriginalValue)) {
                    $invalidTweaks.Add("$($tweak.Name),registry")
                }
            }

            foreach ($serviceEntry in @($tweak.Value.service)) {
                if ($null -eq $serviceEntry) { continue }

                if ($serviceEntry.PSObject.Properties.Name -notcontains "OriginalType" -or
                    [string]::IsNullOrWhiteSpace([string]$serviceEntry.OriginalType)) {
                    $invalidTweaks.Add("$($tweak.Name),service")
                }
            }
        }

        if ($invalidTweaks.Count -gt 0) {
            throw ($invalidTweaks -join "`n")
        }
    }

    It "mantém o limite de divisão do svchost fora do ajuste de serviços" -TestCases $testCase {
        param([string]$Path)

        $tweaks = Get-Content -Path $Path -Raw | ConvertFrom-Json

        $tweaks.WPFTweaksServices.InvokeScript | Should -BeNullOrEmpty

        $invokeScript = @($tweaks.WPFTweaksSvcHostSplitting.InvokeScript) -join "`n"
        $undoScript = @($tweaks.WPFTweaksSvcHostSplitting.UndoScript) -join "`n"
        $invokeScript | Should -Match 'SvcHostSplitThresholdInKB'
        $undoScript | Should -Match 'SvcHostSplitThresholdInKB'
        $undoScript | Should -Match '3670016'
    }

    It "não reivindica o mesmo valor de registro com valores originais ou tipos conflitantes" -TestCases $testCase {
        param([string]$Path)

        $tweaks = Get-Content -Path $Path -Raw | ConvertFrom-Json
        $claims = @{}

        foreach ($tweak in $tweaks.PSObject.Properties) {
            foreach ($registryEntry in @($tweak.Value.registry)) {
                if ($null -eq $registryEntry -or $registryEntry.Values) { continue }

                $key = "$($registryEntry.Path)|$($registryEntry.Name)"
                if (-not $claims.ContainsKey($key)) {
                    $claims[$key] = @{}
                }
                $claims[$key][$tweak.Name] = [pscustomobject]@{
                    OriginalValue = [string]$registryEntry.OriginalValue
                    Type          = [string]$registryEntry.Type
                }
            }
        }

        $conflicts = New-Object System.Collections.Generic.List[string]
        foreach ($key in $claims.Keys) {
            $variants = @($claims[$key].Values | Select-Object -Unique -Property OriginalValue, Type)
            if ($variants.Count -gt 1) {
                $owners = ($claims[$key].Keys | Sort-Object) -join ", "
                $conflicts.Add("$key claimed with conflicting originals/types by: $owners")
            }
        }

        if ($conflicts.Count -gt 0) {
            throw ($conflicts -join "`n")
        }
    }

    It "desativa a indexação do Windows Search pelo esquema de serviço com uma parada e inicialização reversíveis" -TestCases $testCase {
        param([string]$Path)

        $tweaks = Get-Content -Path $Path -Raw | ConvertFrom-Json
        $tweak = $tweaks.WPFTweaksDisableSearchIndexing

        $tweak | Should -Not -BeNullOrEmpty
        $tweak.category | Should -Be "z__Advanced Tweaks - CAUTION"
        $tweak.Description | Should -Match "slower"

        $search = @($tweak.service | Where-Object Name -eq "WSearch")
        $search | Should -HaveCount 1
        $search[0].StartupType | Should -Be "Disabled"
        $search[0].OriginalType | Should -Be "Automatic"

        # Set-WinUtilService apenas altera o tipo de inicialização. O indexador em execução é parado no
        # InvokeScript e iniciado novamente no UndoScript, ambos protegidos por Get-Service para que um
        # serviço ausente não registre um erro (#5123).
        $invoke = @($tweak.InvokeScript) -join "`n"
        $undo = @($tweak.UndoScript) -join "`n"
        $invoke | Should -Match 'Get-Service.*WSearch'
        $invoke | Should -Match 'Stop-Service.*WSearch'
        $undo | Should -Match 'Get-Service.*WSearch'
        $undo | Should -Match 'Start-Service.*WSearch'

        # Os scripts só agem depois que a entrada do serviço realmente alterou o tipo de inicialização,
        # então um serviço movido pelo usuário para Manual (mantido por KeepServiceStartup) não é parado nem iniciado.
        $invoke | Should -Match "StartType -eq 'Disabled'"
        $undo | Should -Match "StartType -eq 'Automatic'"
    }

    It "mantém o serviço de localização desabilitado" -TestCases $testCase {
        param([string]$Path)

        $tweaks = Get-Content -Path $Path -Raw | ConvertFrom-Json
        $locationServices = @($tweaks.WPFTweaksLocation.service | Where-Object Name -eq "lfsvc")

        $locationServices | Should -HaveCount 1
        $locationServices[0].StartupType | Should -Be "Disabled"
    }

    It "desativa o Windows Error Reporting pelo esquema de serviço" -TestCases $testCase {
        param([string]$Path)

        $tweaks = Get-Content -Path $Path -Raw | ConvertFrom-Json
        $telemetry = $tweaks.WPFTweaksTelemetry
        $errorReporting = @($telemetry.service | Where-Object Name -eq "WerSvc")

        $errorReporting | Should -HaveCount 1
        $errorReporting[0].StartupType | Should -Be "Disabled"
        $errorReporting[0].OriginalType | Should -Be "Manual"

        # Telemetria e relatório de erros devem coexistir após a mesclagem de suas correções independentes.
        $diagnostics = @($telemetry.service | Where-Object Name -eq "diagtrack")
        $diagnostics | Should -HaveCount 1
        $diagnostics[0].StartupType | Should -Be "Disabled"
        $diagnostics[0].OriginalType | Should -Be "Automatic"
        ((@($telemetry.InvokeScript) + @($telemetry.UndoScript)) -join "`n") |
            Should -Not -Match 'Set-Service\s+-Name\s+diagtrack'

        # wermgr é um executável, não um serviço, então Set-Service nele falhava em toda execução (#5145)
        $scripts = (@($telemetry.InvokeScript) + @($telemetry.UndoScript)) -join "`n"
        $scripts | Should -Not -Match "wermgr"
    }

    It "remove o valor do período de feedback pelo esquema de registro" -TestCases $testCase {
        param([string]$Path)

        $tweaks = Get-Content -Path $Path -Raw | ConvertFrom-Json
        $telemetry = $tweaks.WPFTweaksTelemetry
        $period = @($telemetry.registry | Where-Object Name -eq "PeriodInNanoSeconds")

        $period | Should -HaveCount 1
        $period[0].Path | Should -Be "HKCU:\Software\Microsoft\Siuf\Rules"
        $period[0].Value | Should -Be "<RemoveEntry>"

        # Um Remove-ItemProperty direto no script dava erro em uma instalação nova, em que o valor
        # ainda não existe (#5145); Set-WinUtilRegistry trata um valor ausente como removido.
        (@($telemetry.InvokeScript) -join "`n") | Should -Not -Match "Remove-ItemProperty"
    }

    $icaclsPrincipalCases = @(
        @{
            Path          = (Join-Path $configRoot "tweaks.json")
            Tweak         = "WPFTweaksDisableStoreSearch"
            Sid           = '*S-1-1-0'
            ExpectedCount = 2
        }
        @{
            Path          = (Join-Path $configRoot "tweaks.json")
            Tweak         = "WPFTweaksRazerBlock"
            Sid           = '*S-1-1-0'
            ExpectedCount = 2
        }
        @{
            Path          = (Join-Path $configRoot "tweaks.json")
            Tweak         = "WPFTweaksRemoveOneDrive"
            Sid           = '*S-1-5-32-544'
            ExpectedCount = 1
        }
    )

    It "identifica o principal do icacls de <Tweak> pelo SID" -TestCases $icaclsPrincipalCases {
        param([string]$Path, [string]$Tweak, [string]$Sid, [int]$ExpectedCount)

        $tweaks = Get-Content -Path $Path -Raw | ConvertFrom-Json
        $scripts = (@($tweaks.$Tweak.InvokeScript) + @($tweaks.$Tweak.UndoScript)) -join "`n"
        $sidCount = ([regex]::Matches($scripts, [regex]::Escape($Sid))).Count

        $sidCount | Should -Be $ExpectedCount -Because "$Tweak deve passar $Sid ao icacls em todo ponto de chamada, em vez de um nome de conta localizado"
    }
}

Describe "Scripts de configuração que alteram serviços" {
    It "protege toda chamada a Set-Service em um script de configuração com uma verificação de existência de serviço ou modelo" {
        $unguarded = New-Object System.Collections.Generic.List[string]

        foreach ($configFile in (Get-ChildItem -Path $script:configRoot -Filter *.json)) {
            $config = Get-Content -Path $configFile.FullName -Raw | ConvertFrom-Json
            foreach ($entry in $config.PSObject.Properties) {
                foreach ($field in @("InvokeScript", "UndoScript")) {
                    if (-not (Test-WinUtilHasProperty -Object $entry.Value -Name $field)) { continue }

                    foreach ($scriptText in @($entry.Value.$field)) {
                        if ([string]$scriptText -notmatch 'Set-Service') { continue }
                        if ([string]$scriptText -notmatch 'Get-Service|Test-Path -LiteralPath.*CurrentControlSet') {
                            $unguarded.Add("$($configFile.Name):$($entry.Name).$field")
                        }
                    }
                }
            }
        }

        if ($unguarded.Count -gt 0) {
            throw ("Unguarded Set-Service calls abort the rest of their script block when the service is missing:`n" + ($unguarded -join "`n"))
        }
    }
}

Describe "Scripts de configuração que alteram preferências do Defender" {
    It "protege toda chamada a Set-MpPreference com um bloco try e -ErrorAction Stop" {
        $unguarded = New-Object System.Collections.Generic.List[string]

        foreach ($configFile in (Get-ChildItem -Path $script:configRoot -Filter *.json)) {
            $config = Get-Content -Path $configFile.FullName -Raw | ConvertFrom-Json
            foreach ($entry in $config.PSObject.Properties) {
                foreach ($field in @("InvokeScript", "UndoScript")) {
                    if (-not (Test-WinUtilHasProperty -Object $entry.Value -Name $field)) { continue }

                    foreach ($scriptText in @($entry.Value.$field)) {
                        if ([string]$scriptText -notmatch 'Set-MpPreference') { continue }

                        $source = [scriptblock]::Create([string]$scriptText)
                        $calls = @($source.Ast.FindAll({
                            param($node)
                            $node -is [System.Management.Automation.Language.CommandAst] -and
                                $node.GetCommandName() -eq 'Set-MpPreference'
                        }, $true))

                        foreach ($call in $calls) {
                            $hasStop = $call.Extent.Text -match '-ErrorAction\s*:?\s*Stop'

                            $insideTryBody = $false
                            $child = $call
                            $parent = $call.Parent
                            while ($null -ne $parent) {
                                if ($parent -is [System.Management.Automation.Language.TryStatementAst] -and
                                    [object]::ReferenceEquals($parent.Body, $child)) {
                                    $insideTryBody = $true
                                    break
                                }
                                $child = $parent
                                $parent = $parent.Parent
                            }

                            if (-not $hasStop -or -not $insideTryBody) {
                                $unguarded.Add("$($configFile.Name):$($entry.Name).$field line $($call.Extent.StartLineNumber)")
                            }
                        }
                    }
                }
            }
        }

        if ($unguarded.Count -gt 0) {
            throw ("Set-MpPreference calls must be inside a try block and pass -ErrorAction Stop, so unavailable Defender can be handled without hiding other failures:`n" + ($unguarded -join "`n"))
        }
    }
}

Describe "Falhas do Defender no ajuste de Telemetria" {
    BeforeAll {
        function Get-DefenderGuardBlock {
            param([string]$Action)

            $source = [scriptblock]::Create((Get-WinUtilConfigObject -Name "tweaks").WPFTweaksTelemetry.$Action -join "`n")
            $blocks = @($source.Ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.TryStatementAst] -and
                    $node.Extent.Text -match 'Set-MpPreference'
            }, $true))
            $blocks.Count | Should -Be 1
            [scriptblock]::Create($blocks[0].Extent.Text)
        }
    }

    It "avisa e continua quando o Defender não está disponível (<Action>)" -TestCases @(
        @{ Action = "InvokeScript" }
        @{ Action = "UndoScript" }
    ) {
        param($Action)
        Mock Write-WinUtilLog {}
        # A mensagem omite o código de propósito, para que apenas a verificação do HResult corresponda a essa falha.
        Mock Set-MpPreference {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Runtime.InteropServices.COMException]::new("Defender provider unavailable.", [int]0x800106ba),
                "DefenderUnavailable",
                [System.Management.Automation.ErrorCategory]::ResourceUnavailable,
                $null
            )
        }

        { & (Get-DefenderGuardBlock -Action $Action) } | Should -Not -Throw

        Should -Invoke Write-WinUtilLog -Times 1 -Exactly -ParameterFilter { $Level -eq 'WARN' }
    }

    It "avisa sobre um erro de provedor apenas por mensagem e continua sob Continue do chamador (<Action>)" -TestCases @(
        @{ Action = "InvokeScript" }
        @{ Action = "UndoScript" }
    ) {
        param($Action)
        $ErrorActionPreference = 'Continue'
        Mock Write-WinUtilLog {}
        Mock Write-Warning {}
        Mock Set-MpPreference { Write-Error "Operation failed with the following error: 0x800106BA." }

        { & (Get-DefenderGuardBlock -Action $Action) } | Should -Not -Throw

        Should -Invoke Write-Warning -Times 1 -Exactly
        Should -Invoke Write-WinUtilLog -Times 1 -Exactly -ParameterFilter {
            $Level -eq 'WARN' -and $Component -eq 'Script' -and $Message -like '*Defender*'
        }
    }

    It "define o consentimento solicitado quando o Defender está disponível (<Action>)" -TestCases @(
        @{ Action = "InvokeScript"; Consent = 2 }
        @{ Action = "UndoScript"; Consent = 1 }
    ) {
        param($Action, $Consent)
        Mock Write-WinUtilLog {}
        Mock Write-Warning {}
        Mock Set-MpPreference {}

        { & (Get-DefenderGuardBlock -Action $Action) } | Should -Not -Throw

        Should -Invoke Set-MpPreference -Times 1 -Exactly -ParameterFilter {
            $SubmitSamplesConsent -eq $Consent -and $ErrorAction -eq 'Stop'
        }
        Should -Invoke Write-Warning -Times 0 -Exactly
        Should -Invoke Write-WinUtilLog -Times 0 -Exactly
    }

    It "relança acesso negado com um HResult estruturado e não relacionado (<Action>)" -TestCases @(
        @{ Action = "InvokeScript" }
        @{ Action = "UndoScript" }
    ) {
        param($Action)
        Mock Set-MpPreference {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.UnauthorizedAccessException]::new("Access denied."),
                "DefenderAccessDenied",
                [System.Management.Automation.ErrorCategory]::PermissionDenied,
                $null
            )
        }

        { & (Get-DefenderGuardBlock -Action $Action) } | Should -Throw -ExpectedMessage "*Access denied*"
    }

    It "relança a ausência de um comando do Defender (<Action>)" -TestCases @(
        @{ Action = "InvokeScript" }
        @{ Action = "UndoScript" }
    ) {
        param($Action)
        Mock Set-MpPreference { throw [System.Management.Automation.CommandNotFoundException]::new("Set-MpPreference is unavailable.") }

        { & (Get-DefenderGuardBlock -Action $Action) } | Should -Throw -ExpectedMessage "*Set-MpPreference is unavailable*"
    }

    It "não confunde um valor hexadecimal mais longo com o código de indisponibilidade (<Action>)" -TestCases @(
        @{ Action = "InvokeScript" }
        @{ Action = "UndoScript" }
    ) {
        param($Action)
        Mock Set-MpPreference { throw "Unrelated error value: 0x800106bad." }

        { & (Get-DefenderGuardBlock -Action $Action) } | Should -Throw -ExpectedMessage "*0x800106bad*"
    }

    It "relança falhas de Set-MpPreference que não são o Defender estar indisponível (<Action>)" -TestCases @(
        @{ Action = "InvokeScript" }
        @{ Action = "UndoScript" }
    ) {
        param($Action)
        Mock Set-MpPreference { throw "Operation failed with the following error: 0x80041001." }

        { & (Get-DefenderGuardBlock -Action $Action) } | Should -Throw -ExpectedMessage "*0x80041001*"
    }
}

Describe "Configuração de predefinições" {
    It "referencia entradas de configuração existentes ou ações compatíveis" {
        $preset = Get-WinUtilConfigObject -Name "preset"
        $applications = Get-WinUtilConfigObject -Name "applications"
        $tweaks = Get-WinUtilConfigObject -Name "tweaks"
        $feature = Get-WinUtilConfigObject -Name "feature"
        $appx = Get-WinUtilConfigObject -Name "appx"

        $validReferences = @(
            $tweaks.PSObject.Properties.Name
            $feature.PSObject.Properties.Name
            $appx.PSObject.Properties.Name
            $applications.PSObject.Properties.Name | ForEach-Object { "WPFInstall$_" }
            Get-WinUtilButtonSwitchNames
        ) | Sort-Object -Unique

        $invalidReferences = New-Object System.Collections.Generic.List[string]
        foreach ($presetEntry in $preset.PSObject.Properties) {
            foreach ($reference in @($presetEntry.Value)) {
                if ($validReferences -notcontains $reference) {
                    $invalidReferences.Add("$($presetEntry.Name) references missing item $reference")
                }
            }
        }

        if ($invalidReferences.Count -gt 0) {
            throw ($invalidReferences -join "`n")
        }
    }
}

Describe "Configuração de navegação de aplicativos" {
    It "está conectado a uma grade XAML de destino existente" {
        $mainScript = Get-Content -Path $script:mainScriptPath -Raw
        $tabInitializerScript = Get-Content -Path (Join-Path $script:repoRoot "functions/private/Initialize-WinUtilTabContent.ps1") -Raw
        $uiInitializerScript = Get-Content -Path (Join-Path $script:repoRoot "functions/public/Initialize-WPFUI.ps1") -Raw
        $targetGridMatch = [regex]::Match(
            "$mainScript`n$tabInitializerScript`n$uiInitializerScript",
            'Invoke-WPFUIElements\s+-configVariable\s+\$sync\.configs\.appnavigation\s+-targetGridName\s+"([^"]+)"'
        )

        if (-not $targetGridMatch.Success) {
            throw "Startup tab initialization does not wire appnavigation through Invoke-WPFUIElements."
        }

        $xamlText = Get-Content -Path $script:xamlPath -Raw
        $targetGridName = $targetGridMatch.Groups[1].Value
        if ($xamlText -notmatch "Name=`"$([regex]::Escape($targetGridName))`"") {
            throw "appnavigation target grid '$targetGridName' was not found in xaml/inputXML.xaml."
        }
    }

    It "contém entradas renderizáveis com grupos de botões e de opções válidos" {
        $appnavigation = Get-WinUtilConfigObject -Name "appnavigation"
        $feature = Get-WinUtilConfigObject -Name "feature"
        $requiredFields = @("Content", "Category", "Type", "Order", "Description")
        $allowedTypes = @("Button", "RadioButton", "Note")
        $supportedButtons = @(
            Get-WinUtilButtonSwitchNames
            $feature.PSObject.Properties.Name
        ) | Sort-Object -Unique
        $invalidEntries = New-Object System.Collections.Generic.List[string]

        foreach ($entry in $appnavigation.PSObject.Properties) {
            foreach ($missingField in (Get-WinUtilMissingRequiredFields -EntryName $entry.Name -Entry $entry.Value -RequiredFields $requiredFields)) {
                $invalidEntries.Add($missingField)
            }

            if ($allowedTypes -notcontains $entry.Value.Type) {
                $invalidEntries.Add("$($entry.Name) has unsupported Type '$($entry.Value.Type)'")
            }

            if ($entry.Value.Type -eq "Button" -and $supportedButtons -notcontains $entry.Name) {
                $invalidEntries.Add("$($entry.Name) is not handled by Invoke-WPFButton or feature config")
            }

            if ($entry.Value.Type -eq "RadioButton") {
                if (-not (Test-WinUtilHasNonEmptyProperty -Object $entry.Value -Name "GroupName")) {
                    $invalidEntries.Add("$($entry.Name) missing GroupName")
                }

                if (-not (Test-WinUtilHasProperty -Object $entry.Value -Name "Checked")) {
                    $invalidEntries.Add("$($entry.Name) missing Checked")
                }
            }
        }

        $radioButtons = @($appnavigation.PSObject.Properties | Where-Object { $_.Value.Type -eq "RadioButton" })
        foreach ($group in ($radioButtons | Group-Object -Property { $_.Value.GroupName })) {
            if ([string]::IsNullOrWhiteSpace($group.Name)) {
                $invalidEntries.Add("RadioButton group name is blank")
                continue
            }

            $checkedCount = @($group.Group | Where-Object { $_.Value.Checked -eq $true }).Count
            if ($checkedCount -ne 1) {
                $invalidEntries.Add("RadioButton group '$($group.Name)' has $checkedCount checked entries")
            }
        }

        if ($invalidEntries.Count -gt 0) {
            throw ($invalidEntries -join "`n")
        }
    }
}

Describe "Entradas de configuração renderizadas na interface" {
    It "contém os campos obrigatórios de AppX" {
        $appx = Get-WinUtilConfigObject -Name "appx"
        $requiredFields = @("Category", "Content", "Description", "Panel", "PackageId")
        $invalidEntries = New-Object System.Collections.Generic.List[string]

        foreach ($entry in $appx.PSObject.Properties) {
            foreach ($missingField in (Get-WinUtilMissingRequiredFields -EntryName $entry.Name -Entry $entry.Value -RequiredFields $requiredFields)) {
                $invalidEntries.Add($missingField)
            }

            if ((Test-WinUtilHasProperty -Object $entry.Value -Name "StoreId") -and
                $entry.Value.StoreId -notmatch '^(?:[A-Z0-9]{12}|XP[A-Z0-9]{12})$') {
                $invalidEntries.Add("$($entry.Name) has invalid Microsoft Store ID '$($entry.Value.StoreId)'")
            }
        }

        if ($invalidEntries.Count -gt 0) {
            throw ($invalidEntries -join "`n")
        }
    }

    It "contém os campos obrigatórios de DNS com endereços IP válidos para análise" {
        $dns = Get-WinUtilConfigObject -Name "dns"
        $requiredFields = @("Primary", "Secondary", "Primary6", "Secondary6")
        $invalidEntries = New-Object System.Collections.Generic.List[string]

        foreach ($entry in $dns.PSObject.Properties) {
            foreach ($missingField in (Get-WinUtilMissingRequiredFields -EntryName $entry.Name -Entry $entry.Value -RequiredFields $requiredFields)) {
                $invalidEntries.Add($missingField)
            }

            foreach ($field in $requiredFields) {
                if (-not (Test-WinUtilHasNonEmptyProperty -Object $entry.Value -Name $field)) {
                    continue
                }

                try {
                    [System.Net.IPAddress]::Parse([string]$entry.Value.$field) | Out-Null
                } catch {
                    $invalidEntries.Add("$($entry.Name) $field is not a parseable IP address")
                }
            }
        }

        if ($invalidEntries.Count -gt 0) {
            throw ($invalidEntries -join "`n")
        }
    }

    It "expõe todo provedor DNS configurado na lista suspensa de DNS" {
        $dns = Get-WinUtilConfigObject -Name "dns"
        $tweaks = Get-WinUtilConfigObject -Name "tweaks"
        $comboItems = @($tweaks.WPFchangedns.ComboItems -split " ")
        $missingProviders = @($dns.PSObject.Properties.Name | Where-Object { $comboItems -notcontains $_ })

        if ($missingProviders.Count -gt 0) {
            throw "WPFchangedns missing providers: $($missingProviders -join ', ')"
        }
    }

    It "contém os campos obrigatórios de recursos e funções configuradas válidas" {
        $feature = Get-WinUtilConfigObject -Name "feature"
        $functionNames = Get-WinUtilTopLevelFunctionNames
        $requiredFields = @("Content", "category", "panel", "link")
        $invalidEntries = New-Object System.Collections.Generic.List[string]

        foreach ($entry in $feature.PSObject.Properties) {
            foreach ($missingField in (Get-WinUtilMissingRequiredFields -EntryName $entry.Name -Entry $entry.Value -RequiredFields $requiredFields)) {
                $invalidEntries.Add($missingField)
            }

            if ($entry.Value.Type -and $entry.Value.Type -ne "Button") {
                $invalidEntries.Add("$($entry.Name) has unsupported Type '$($entry.Value.Type)'")
            }

            if ($entry.Value.Type -eq "Button") {
                if (-not $entry.Value.function -and -not $entry.Value.InvokeScript) {
                    $invalidEntries.Add("$($entry.Name) button missing function or InvokeScript")
                }
            } else {
                if (-not (Test-WinUtilHasNonEmptyProperty -Object $entry.Value -Name "Description")) {
                    $invalidEntries.Add("$($entry.Name) missing Description")
                }

                if (-not $entry.Value.feature -and -not $entry.Value.InvokeScript) {
                    $invalidEntries.Add("$($entry.Name) missing feature or InvokeScript action")
                }
            }

            if ($entry.Value.function -and $functionNames -notcontains $entry.Value.function) {
                $invalidEntries.Add("$($entry.Name) references missing function $($entry.Value.function)")
            }
        }

        if ($invalidEntries.Count -gt 0) {
            throw ($invalidEntries -join "`n")
        }
    }

    It "contém os campos obrigatórios de ajustes e metadados de ação válidos" {
        $tweaks = Get-WinUtilConfigObject -Name "tweaks"
        $requiredFields = @("Content", "category", "panel", "link")
        $allowedTypes = @("Button", "Combobox", "Toggle", "ToggleButton")
        $allowedServiceStartupTypes = @("Automatic", "AutomaticDelayedStart", "Disabled", "Manual")
        $supportedButtons = Get-WinUtilButtonSwitchNames
        $invalidEntries = New-Object System.Collections.Generic.List[string]

        foreach ($entry in $tweaks.PSObject.Properties) {
            foreach ($missingField in (Get-WinUtilMissingRequiredFields -EntryName $entry.Name -Entry $entry.Value -RequiredFields $requiredFields)) {
                $invalidEntries.Add($missingField)
            }

            if ($entry.Value.Type -and $allowedTypes -notcontains $entry.Value.Type) {
                $invalidEntries.Add("$($entry.Name) has unsupported Type '$($entry.Value.Type)'")
            }

            if ($entry.Value.Type -eq "Button") {
                if ($supportedButtons -notcontains $entry.Name) {
                    $invalidEntries.Add("$($entry.Name) is not handled by Invoke-WPFButton")
                }
            } elseif ($entry.Value.Type -eq "Combobox") {
                if (-not (Test-WinUtilHasNonEmptyProperty -Object $entry.Value -Name "ComboItems")) {
                    $invalidEntries.Add("$($entry.Name) combobox missing ComboItems")
                }
                $statefulRegistry = @($entry.Value.registry | Where-Object Values)
                if ($statefulRegistry.Count -gt 0) {
                    $comboItems = if ($entry.Value.ComboItems -is [string]) {
                        if ($entry.Value.ComboItems.Contains("|")) {
                            @($entry.Value.ComboItems -split "\|")
                        } else {
                            @($entry.Value.ComboItems -split " ")
                        }
                    } else {
                        @($entry.Value.ComboItems)
                    }
                    if ($statefulRegistry.Count -ne @($entry.Value.registry).Count) {
                        $invalidEntries.Add("$($entry.Name) registry states must all use Values")
                    } else {
                    foreach ($setting in $statefulRegistry) {
                        if (Compare-Object $comboItems @($setting.Values.PSObject.Properties.Name)) {
                            $invalidEntries.Add("$($entry.Name) ComboItems and registry states do not match")
                        }
                    }
                    }
                }
            } else {
                if (-not (Test-WinUtilHasNonEmptyProperty -Object $entry.Value -Name "Description")) {
                    $invalidEntries.Add("$($entry.Name) missing Description")
                }

                if (-not $entry.Value.registry -and -not $entry.Value.service -and -not $entry.Value.InvokeScript -and -not $entry.Value.appx) {
                    $invalidEntries.Add("$($entry.Name) missing registry, service, InvokeScript, or appx action")
                }
            }

            foreach ($registryEntry in @($entry.Value.registry)) {
                if ($null -eq $registryEntry) { continue }

                $requiredRegistryFields = if ($entry.Value.Type -eq "Combobox" -and $statefulRegistry.Count -gt 0) {
                    @("Path", "Name", "Type", "DefaultValue", "Values")
                } else {
                    @("Path", "Name", "Type", "Value", "OriginalValue")
                }
                foreach ($missingField in (Get-WinUtilMissingRequiredFields -EntryName "$($entry.Name),registry" -Entry $registryEntry -RequiredFields $requiredRegistryFields)) {
                    $invalidEntries.Add($missingField)
                }
            }

            foreach ($serviceEntry in @($entry.Value.service)) {
                if ($null -eq $serviceEntry) { continue }

                foreach ($missingField in (Get-WinUtilMissingRequiredFields -EntryName "$($entry.Name),service" -Entry $serviceEntry -RequiredFields @("Name", "StartupType", "OriginalType"))) {
                    $invalidEntries.Add($missingField)
                }

                foreach ($startupTypeField in @("StartupType", "OriginalType")) {
                    if ((Test-WinUtilHasNonEmptyProperty -Object $serviceEntry -Name $startupTypeField) -and
                        $allowedServiceStartupTypes -notcontains $serviceEntry.$startupTypeField) {
                        $invalidEntries.Add("$($entry.Name),service has unsupported $startupTypeField '$($serviceEntry.$startupTypeField)'")
                    }
                }
            }
        }

        if ($invalidEntries.Count -gt 0) {
            throw ($invalidEntries -join "`n")
        }
    }

    It "define os recursos de tema exigidos pela renderização XAML" {
        $themes = Get-WinUtilConfigObject -Name "themes"
        $invalidEntries = New-Object System.Collections.Generic.List[string]

        foreach ($themeName in @("shared", "Light", "Dark")) {
            if (-not (Test-WinUtilHasProperty -Object $themes -Name $themeName)) {
                $invalidEntries.Add("themes.json missing $themeName")
                continue
            }

            foreach ($property in $themes.$themeName.PSObject.Properties) {
                if ([string]::IsNullOrWhiteSpace([string]$property.Value)) {
                    $invalidEntries.Add("$themeName.$($property.Name) is blank")
                }
            }
        }

        $lightKeys = @($themes.Light.PSObject.Properties.Name)
        $darkKeys = @($themes.Dark.PSObject.Properties.Name)
        foreach ($key in $lightKeys) {
            if ($darkKeys -notcontains $key) {
                $invalidEntries.Add("Dark theme missing $key")
            }
        }
        foreach ($key in $darkKeys) {
            if ($lightKeys -notcontains $key) {
                $invalidEntries.Add("Light theme missing $key")
            }
        }

        $xamlText = Get-Content -Path $script:xamlPath -Raw
        $dynamicResourceNames = @(
            [regex]::Matches($xamlText, '\{DynamicResource\s+([^\}\s]+)') |
                ForEach-Object { $_.Groups[1].Value }
        ) | Sort-Object -Unique
        $xamlDefinedResourceNames = @(
            [regex]::Matches($xamlText, 'x:Key="([^"]+)"') |
                ForEach-Object { $_.Groups[1].Value }
        ) | Sort-Object -Unique
        $themeResourceNames = @(
            $themes.shared.PSObject.Properties.Name
            $themes.Light.PSObject.Properties.Name
            $themes.Dark.PSObject.Properties.Name
            "CBorderColor"
            "CButtonBackgroundMouseoverColor"
            "CAppIconShadowColor"
            # Definido pela largura da lista de aplicativos (Update-WinUtilAppEntryWidth), não por um tema
            "AppEntryCardWidth"
            "CMainGradientTopColor"
            "CMainGradientBottomColor"
        ) | Sort-Object -Unique

        foreach ($resourceName in $dynamicResourceNames) {
            if ($xamlDefinedResourceNames -notcontains $resourceName -and $themeResourceNames -notcontains $resourceName) {
                $invalidEntries.Add("XAML DynamicResource '$resourceName' is not defined in themes.json or XAML resources")
            }
        }

        if ($invalidEntries.Count -gt 0) {
            throw ($invalidEntries -join "`n")
        }
    }
}

Describe "Scripts de configuração incorporados" {
    It "são analisados como blocos de script do PowerShell" {
        $invalidScripts = New-Object System.Collections.Generic.List[string]

        foreach ($configFile in (Get-ChildItem -Path $script:configRoot -Filter *.json)) {
            $config = Get-Content -Path $configFile.FullName -Raw | ConvertFrom-Json
            foreach ($entry in $config.PSObject.Properties) {
                foreach ($field in @("InvokeScript", "UndoScript")) {
                    if (-not (Test-WinUtilHasProperty -Object $entry.Value -Name $field)) {
                        continue
                    }

                    $index = 0
                    foreach ($scriptText in @($entry.Value.$field)) {
                        $index++
                        if ([string]::IsNullOrWhiteSpace([string]$scriptText)) {
                            continue
                        }

                        try {
                            [scriptblock]::Create([string]$scriptText) | Out-Null
                        } catch {
                            $invalidScripts.Add("$($configFile.Name):$($entry.Name).$field[$index] $($psitem.Exception.Message)")
                        }
                    }
                }
            }
        }

        if ($invalidScripts.Count -gt 0) {
            throw ($invalidScripts -join "`n")
        }
    }
}
