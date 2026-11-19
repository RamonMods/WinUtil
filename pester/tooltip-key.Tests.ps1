#===========================================================================
# Testes - Auxiliar de dica de ferramenta de entrada
#===========================================================================

BeforeAll {
    $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
    . (Join-Path $script:repoRoot "functions\private\Get-WinUtilEntryToolTip.ps1")
    . (Join-Path $script:repoRoot "functions\private\Update-WinUtilSelections.ps1")

    $applications = Get-Content (Join-Path $script:repoRoot "config\applications.json") -Raw | ConvertFrom-Json
    $applicationsHashtable = @{}
    foreach ($property in $applications.PSObject.Properties) {
        $applicationsHashtable["WPFInstall$($property.Name)"] = $property.Value
    }
    $appx = Get-Content (Join-Path $script:repoRoot "config\appx.json") -Raw | ConvertFrom-Json
    $appxHashtable = @{}
    foreach ($property in $appx.PSObject.Properties) {
        $appxHashtable[$property.Name] = $property.Value
    }
    $script:selectionConfigs = @{
        applicationsHashtable = $applicationsHashtable
        tweaks                 = Get-Content (Join-Path $script:repoRoot "config\tweaks.json") -Raw | ConvertFrom-Json
        feature                = Get-Content (Join-Path $script:repoRoot "config\feature.json") -Raw | ConvertFrom-Json
        appxHashtable          = $appxHashtable
    }

    # Mapeia cada tipo de controle tratado pelo renderizador para indicar se sua ramificação adiciona a chave da predefinição.
    # Lê a AST do código-fonte para que readicionar o auxiliar a uma ramificação não suportada faça o teste falhar.
    $script:rendererClauses = @{}
    $rendererPath = Join-Path $script:repoRoot "functions\public\Invoke-WPFUIElements.ps1"
    $rendererAst = [System.Management.Automation.Language.Parser]::ParseFile($rendererPath, [ref]$null, [ref]$null)
    $typeSwitch = $rendererAst.FindAll({
        $args[0] -is [System.Management.Automation.Language.SwitchStatementAst]
    }, $true) | Where-Object { $_.Clauses.Item1.Extent.Text -contains '"Combobox"' }

    foreach ($clause in $typeSwitch.Clauses) {
        $clauseName = $clause.Item1.Extent.Text.Trim('"')
        $script:rendererClauses[$clauseName] = [bool]($clause.Item2.Extent.Text -match 'Get-WinUtilEntryToolTip')
    }
    $script:rendererClauses["default"] = [bool]($typeSwitch.Default.Extent.Text -match 'Get-WinUtilEntryToolTip')

    $appRendererPath = Join-Path $script:repoRoot "functions\private\Initialize-InstallAppEntries.ps1"
    $script:appRenderer = Get-Content $appRendererPath -Raw

    # Cada entrada desenhada pelo renderizador, com a ramificação que a desenha
    $script:renderedEntries = foreach ($configName in "appnavigation", "tweaks", "feature", "appx") {
        $config = Get-Content (Join-Path $script:repoRoot "config\$configName.json") -Raw | ConvertFrom-Json
        foreach ($property in $config.PSObject.Properties) {
            $clauseName = "default"
            if ($property.Value.Type -and $script:rendererClauses.ContainsKey($property.Value.Type)) {
                $clauseName = $property.Value.Type
            }
            [pscustomobject]@{
                Config = $configName
                Key    = $property.Name
                Clause = $clauseName
            }
        }
    }
}

Describe "Get-WinUtilEntryToolTip" {
    It "anexa a chave da predefinição após a descrição" {
        Get-WinUtilEntryToolTip -Description "Fast private browser" -Key "WPFInstallBrave" |
            Should -Be "Fast private browser`n`nPreset key: WPFInstallBrave"
    }

    It "retorna apenas a linha da chave quando a descrição é nula" {
        Get-WinUtilEntryToolTip -Description $null -Key "WPFTweaksTele" |
            Should -Be "Preset key: WPFTweaksTele"
    }

    It "retorna apenas a linha da chave quando a descrição contém apenas espaços" {
        Get-WinUtilEntryToolTip -Description "   " -Key "WPFTweaksTele" |
            Should -Be "Preset key: WPFTweaksTele"
    }

    It "retorna uma string simples, não um objeto de interface" {
        (Get-WinUtilEntryToolTip -Description "x" -Key "WPFTweaksTele").GetType().Name |
            Should -Be "String"
    }
}

Describe "Preset key tooltips" {
    It "deixa controles não suportados sem rótulo" {
        # Caixas de combinação e botões de opção não podem ser representados no formato simples de predefinição.
        # Chaves de interruptor podem ser importadas, mas a execução da predefinição não aplica seu estado.
        $script:rendererClauses["Toggle"] | Should -BeFalse
        $script:rendererClauses["Combobox"] | Should -BeFalse
        $script:rendererClauses["RadioButton"] | Should -BeFalse
    }

    It "rotula entradas criadas pelo renderizador de aplicativos" {
        $script:appRenderer | Should -Match '\$tooltip\s*=\s*\[Security\.SecurityElement\]::Escape\(\(Get-WinUtilEntryToolTip\s+-Description\s+\$app\.description\s+-Key\s+\$appKey\)\)'
    }

    It "rotula cada entrada com uma chave aceita pelo importador de predefinições" {
        $labelled = @($script:renderedEntries | Where-Object { $script:rendererClauses[$_.Clause] })
        $labelled.Count | Should -BeGreaterThan 0

        foreach ($entry in $labelled) {
            $sync = @{
                selectedApps     = [System.Collections.Generic.List[string]]::new()
                selectedTweaks   = [System.Collections.Generic.List[string]]::new()
                selectedToggles  = [System.Collections.Generic.List[string]]::new()
                selectedFeatures = [System.Collections.Generic.List[string]]::new()
                selectedAppx     = [System.Collections.Generic.List[string]]::new()
                configs          = $script:selectionConfigs
            }

            { Update-WinUtilSelections -flatJson @($entry.Key) } |
                Should -Not -Throw -Because "$($entry.Config).json key '$($entry.Key)' é exibida como uma chave de predefinição"

            $imported = @($sync.Values | ForEach-Object { $_ })
            $imported | Should -Contain $entry.Key -Because "importar '$($entry.Key)' deve restaurar essa seleção"
        }
    }
}
