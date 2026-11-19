<#
    .DESCRIPTION
    Gera a documentação em markdown do Astro/Starlight a partir de config/tweaks.json e config/feature.json.
    Executado pelo workflow de docs do GitHub Actions antes do build do Astro.
#>

function Update-Progress {
    param (
        [Parameter(Mandatory, position=0)]
        [string]$StatusMessage,
        [Parameter(Mandatory, position=1)]
        [ValidateRange(0,100)]
        [int]$Percent
    )
    Write-Progress -Activity "Gerando a documentação de desenvolvimento" -Status $StatusMessage -PercentComplete $Percent
}

function Get-RawJsonBlock {
    # Retorna o texto JSON bruto e a linha inicial (base 1) de um item, sem a propriedade "link".
    param (
        [Parameter(Mandatory)]
        [string]$ItemName,
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string[]]$JsonLines
    )

    $escapedName = [regex]::Escape($ItemName)
    $startIndex  = -1

    for ($i = 0; $i -lt $JsonLines.Count; $i++) {
        if ($JsonLines[$i] -match "^(\s*)`"$escapedName`"\s*:\s*\{") {
            $startIndex  = $i
            break
        }
    }

    if ($startIndex -eq -1) {
        Write-Warning "Não foi possível encontrar '$ItemName' no JSON"
        return $null
    }

    # Usa o rastreamento de profundidade de chaves para encontrar a chave de fechamento
    $endIndex = -1
    $depth = 1  # Estamos começando dentro da chave de abertura
    for ($i = ($startIndex + 1); $i -lt $JsonLines.Count; $i++) {
        $line = $JsonLines[$i]

        # Conta as chaves nesta linha, ignorando as que estão dentro de strings
        $inString = $false
        $chars = $line.ToCharArray()
        for ($k = 0; $k -lt $chars.Count; $k++) {
            if ($chars[$k] -eq '"' -and ($k -eq 0 -or $chars[$k-1] -ne '\')) {
                $inString = -not $inString
            } elseif (-not $inString) {
                if ($chars[$k] -eq '{') { $depth++ }
                elseif ($chars[$k] -eq '}') { $depth-- }
            }
        }

        # Encontrou a chave de fechamento do item
        if ($depth -eq 0) {
            $endIndex = $i
            break
        }
    }

    if ($endIndex -eq -1) {
        Write-Warning "Não foi possível encontrar a chave de fechamento de '$ItemName'"
        return $null
    }

    # Remove a propriedade "link" final e as linhas em branco antes de retornar
    $lastContentIndex = $endIndex - 1
    while ($lastContentIndex -gt $startIndex) {
        $trimmed = $JsonLines[$lastContentIndex].Trim()
        if ($trimmed -eq "" -or $trimmed -match '^"link"') {
            $lastContentIndex--
        } else {
            break
        }
    }

    # Inclui a própria chave de fechamento do item, sem a vírgula final que
    # existe apenas para separá-lo do próximo irmão no objeto pai.
    $closingLine = $JsonLines[$endIndex] -replace ',\s*$', ''

    return @{
        LineNumber = $startIndex + 1
        RawText    = (($JsonLines[$startIndex..$lastContentIndex] + $closingLine) -join "`r`n")
    }
}

function Get-GeneratedFromNote {
    # Monta o aviso ":::note" do Starlight apontando de volta para o arquivo de origem de uma entrada.
    param (
        [Parameter(Mandatory)]
        [string]$SourceRelativePath
    )

    $githubUrl = "https://github.com/RamonMods/WinUtil/blob/main/$SourceRelativePath"
    $note  = ":::note`r`n"
    $note += "Esta página é gerada a partir de [``$SourceRelativePath``]($githubUrl). Não edite esta página diretamente.`r`n"
    $note += ":::`r`n`r`n"
    return $note
}

function Get-ButtonFunctionMapping {
    # Analisa Invoke-WPFButton.ps1 e retorna uma hashtable de nome do botão -> nome da função.
    param (
        [Parameter(Mandatory)]
        [string]$ButtonFilePath
    )

    $mapping = @{}
    foreach ($line in (Get-Content -Path $ButtonFilePath)) {
        if ($line -match '^\s*"(\w+)"\s*\{(Invoke-\w+)') {
            $mapping[$matches[1]] = $matches[2]
        }
    }
    return $mapping
}

function Add-LinkAttributeToJson {
    # Atualiza apenas a propriedade "link" de cada entrada em um arquivo de configuração JSON.
    # Lê via ConvertFrom-Json para metadados e depois edita as linhas diretamente para evitar reformatação.
    param (
        [Parameter(Mandatory)]
        [string]$JsonFilePath,
        [Parameter(Mandatory)]
        [string]$UrlPrefix,
        [Parameter(Mandatory)]
        [string]$ItemNameToCut
    )

    $jsonData = Get-Content -Path $JsonFilePath -Raw | ConvertFrom-Json
    $lines    = [System.Collections.Generic.List[string]](Get-Content -Path $JsonFilePath)

    foreach ($item in $jsonData.PSObject.Properties) {
        $itemName    = $item.Name
        $category    = $item.Value.category -replace '[^a-zA-Z0-9]', '-'
        $displayName = $itemName -replace $ItemNameToCut, ''
        $newLink     = "$UrlPrefix/$($category.ToLower())/$($displayName.ToLower())"
        $escapedName = [regex]::Escape($itemName)

        # Encontra a linha inicial do item
        $startIdx = -1
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match "^\s*`"$escapedName`"\s*:\s*\{") {
                $startIdx = $i
                break
            }
        }
        if ($startIdx -eq -1) { continue }

        # Deduz a indentação usada pelas propriedades de nível superior do item.
        # Prefere a indentação de propriedade existente para não herdar a indentação errada da chave.
        $null       = $lines[$startIdx] -match '^(\s*)'
        $propIndent = $matches[1] + '  '

        $depthProbe = 1
        for ($p = $startIdx + 1; $p -lt $lines.Count; $p++) {
            $probeLine = $lines[$p]

            if ($depthProbe -eq 1 -and $probeLine -match '^(\s*)"[^"]+"\s*:') {
                $propIndent = $matches[1]
                break
            }

            $inStringProbe = $false
            $probeChars = $probeLine.ToCharArray()
            for ($q = 0; $q -lt $probeChars.Count; $q++) {
                if ($probeChars[$q] -eq '"' -and ($q -eq 0 -or $probeChars[$q-1] -ne '\')) {
                    $inStringProbe = -not $inStringProbe
                } elseif (-not $inStringProbe) {
                    if ($probeChars[$q] -eq '{') { $depthProbe++ }
                    elseif ($probeChars[$q] -eq '}') { $depthProbe-- }
                }
            }

            if ($depthProbe -eq 0) { break }
        }

        # Percorre adiante: remove qualquer propriedade "link" existente e encontra a chave de fechamento.
        # Usa o rastreamento de profundidade de chaves para tratar corretamente estruturas aninhadas como arrays.
        $closeBraceIdx = -1
        $depth         = 1  # Estamos começando dentro da chave de abertura do item
        $linesToRemove  = @()

        for ($j = $startIdx + 1; $j -lt $lines.Count; $j++) {
            $line = $lines[$j]

            # Verifica se existe uma propriedade "link" no nível superior (profundidade 1 antes de processar as chaves desta linha)
            # Casa em qualquer nível de indentação (o usuário pode ter alterado a indentação manualmente)
            if ($depth -eq 1 -and $line -match '^\s*"link"\s*:') {
                # Marca esta linha para remoção
                $linesToRemove += $j
            }

            # Conta as chaves nesta linha, ignorando as que estão dentro de strings
            $inString = $false
            $chars = $line.ToCharArray()
            for ($k = 0; $k -lt $chars.Count; $k++) {
                if ($chars[$k] -eq '"' -and ($k -eq 0 -or $chars[$k-1] -ne '\')) {
                    $inString = -not $inString
                } elseif (-not $inString) {
                    if ($chars[$k] -eq '{') { $depth++ }
                    elseif ($chars[$k] -eq '}') { $depth-- }
                }
            }

            # Encontrou a chave de fechamento do item
            if ($depth -eq 0) {
                $closeBraceIdx = $j
                break
            }
        }

        # Remove as linhas antigas de "link" em ordem inversa para preservar os índices
        foreach ($idx in ($linesToRemove | Sort-Object -Descending)) {
            # Se a linha anterior tinha uma vírgula final (da propriedade link), remove-a
            if ($idx -gt $startIdx) {
                $prevLine = $lines[$idx - 1]
                if ($prevLine -match ',\s*$' -and $lines[$idx].Trim() -match '^}') {
                    $lines[$idx - 1] = $prevLine -replace ',\s*$', ''
                }
            }
            $lines.RemoveAt($idx)
            if ($idx -lt $closeBraceIdx) {
                $closeBraceIdx--
            }
        }

        # Agora insere "link" antes da chave de fechamento (posição consistente para todos os itens)
        if ($closeBraceIdx -ne -1) {
            $prevPropIdx = $closeBraceIdx - 1
            while ($prevPropIdx -gt $startIdx -and $lines[$prevPropIdx].Trim() -eq '') { $prevPropIdx-- }

            if ($lines[$prevPropIdx] -notmatch ',\s*$') {
                $lines[$prevPropIdx] = $lines[$prevPropIdx].TrimEnd() + ','
            }
            $lines.Insert($closeBraceIdx, "$propIndent`"link`": `"$newLink`"")
        }
    }

    Set-Content -Path $JsonFilePath -Value $lines -Encoding utf8
}

# ==============================================================================
# Principal
# ==============================================================================

$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$repoRoot  = Resolve-Path "$scriptDir/.."

$tweaksJsonPath      = "$repoRoot/config/tweaks.json"
$featuresJsonPath    = "$repoRoot/config/feature.json"
$tweaksOutputDir     = "$repoRoot/docs/src/content/docs/code-reference/tweaks"
$featuresOutputDir   = "$repoRoot/docs/src/content/docs/code-reference/features"
$publicFunctionsDir  = "$repoRoot/functions/public"
$privateFunctionsDir = "$repoRoot/functions/private"

$itemnametocut = 'WPF(WinUtil|Toggle|Features?|Tweaks?|Panel|Fix(es)?)?'
$baseUrl       = "https://github.com/RamonMods/WinUtil"

# Categorias com documentação gerada
$documentedCategories = @(
    "Essential Tweaks",
    "z__Advanced Tweaks - CAUTION",
    "Customize Preferences",
    "Performance Plans",
    "Features",
    "Fixes",
    "Legacy Windows Panels",
    "Powershell Profile Powershell 7+ Only",
    "Remote Access"
)

# Categorias em que as entradas Button embutem uma função PS em vez de JSON bruto
$functionEmbedCategories = @(
    "Fixes",
    "Powershell Profile Powershell 7+ Only",
    "Remote Access"
)

Update-Progress "Carregando os arquivos JSON" 10
$tweaks   = Get-Content -Path $tweaksJsonPath   -Raw | ConvertFrom-Json
$features = Get-Content -Path $featuresJsonPath -Raw | ConvertFrom-Json

Update-Progress "Carregando os arquivos de funções" 20
$functionFiles = @{}
Get-ChildItem -Path $publicFunctionsDir  -Filter *.ps1 | ForEach-Object {
    $functionFiles[$_.BaseName] = @{ Content = (Get-Content -Path $_.FullName -Raw).TrimEnd(); RelativePath = "functions/public/$($_.Name)" }
}
Get-ChildItem -Path $privateFunctionsDir -Filter *.ps1 | ForEach-Object {
    $functionFiles[$_.BaseName] = @{ Content = (Get-Content -Path $_.FullName -Raw).TrimEnd(); RelativePath = "functions/private/$($_.Name)" }
}

Update-Progress "Montando o mapa de botão para função" 30
$buttonFunctionMap = Get-ButtonFunctionMapping -ButtonFilePath "$publicFunctionsDir/Invoke-WPFButton.ps1"

Update-Progress "Atualizando os links de documentação no JSON" 40
Add-LinkAttributeToJson -JsonFilePath $tweaksJsonPath   -UrlPrefix "$baseUrl/code-reference/tweaks"   -ItemNameToCut $itemnametocut
Add-LinkAttributeToJson -JsonFilePath $featuresJsonPath -UrlPrefix "$baseUrl/code-reference/features" -ItemNameToCut $itemnametocut

# Recarrega as linhas após a atualização dos links para que os números de linha na documentação fiquem corretos
$tweaksLines   = Get-Content -Path $tweaksJsonPath
$featuresLines = Get-Content -Path $featuresJsonPath

# ==============================================================================
# Limpa os arquivos .mdx gerados antigos
# ==============================================================================

Update-Progress "Limpando a documentação gerada antiga" 45
foreach ($dir in @($tweaksOutputDir, $featuresOutputDir)) {
    if (-Not (Test-Path -Path $dir)) { continue }
    Get-ChildItem -Path $dir -Recurse -Filter *.mdx | Where-Object {
        # Ainda não existem páginas index.mdx de categoria. Se uma for adicionada depois como
        # página de entrada da categoria, descomente esta linha para impedir que ela seja apagada.
        # $_.Name -ne "index.mdx"
        $true
    } | Remove-Item -Force
}

# ==============================================================================
# Gera a documentação dos ajustes
# ==============================================================================

Update-Progress "Gerando a documentação dos ajustes" 50

$tweakNames  = $tweaks.PSObject.Properties.Name
$totalTweaks = $tweakNames.Count
$tweakCount  = 0

foreach ($itemName in $tweakNames) {
    $item = $tweaks.$itemName
    $tweakCount++

    if ($item.category -notin $documentedCategories) { continue }

    $category    = $item.category -replace '[^a-zA-Z0-9]', '-'
    $displayName = $itemName -replace $itemnametocut, ''
    $categoryDir = "$tweaksOutputDir/$category"
    $filename    = "$categoryDir/$displayName.mdx"

    if (-Not (Test-Path -Path $categoryDir)) { New-Item -ItemType Directory -Path $categoryDir | Out-Null }

    # Escalares de string do JSON são YAML válido e escapam caminhos do Windows e caracteres de controle.
    $title       = ConvertTo-Json -InputObject ([string]$item.Content) -Compress
    $description = ConvertTo-Json -InputObject ([string]$item.Description) -Compress
    $content     = "---`r`ntitle: $title`r`ndescription: $description`r`neditUrl: false`r`n---`r`n`r`n"

    if ($item.Type -eq "Button") {
        $funcName = $buttonFunctionMap[$itemName]
        if ($funcName -and $functionFiles.ContainsKey($funcName)) {
            $func     = $functionFiles[$funcName]
            $content += Get-GeneratedFromNote -SourceRelativePath $func.RelativePath
            $content += "``````powershell title=`"$($func.RelativePath)`"`r`n"
            $content += $func.Content + "`r`n"
            $content += "```````r`n"
        }
    } else {
        $jsonBlock = Get-RawJsonBlock -ItemName $itemName -JsonLines $tweaksLines
        if ($jsonBlock) {
            $content += Get-GeneratedFromNote -SourceRelativePath "config/tweaks.json"
            $content += "``````json title=`"config/tweaks.json`"`r`n"
            $content += $jsonBlock.RawText + "`r`n"
            $content += "```````r`n"
        }

        if ($item.registry) {
            $content += "`r`n## Alterações no Registro`r`n`r`n"
            $content += "Aplicativos e componentes do sistema armazenam e recuperam dados de configuração para modificar as configurações do Windows, então podemos usar o registro para alterar muitas configurações em um só lugar.`r`n`r`n"
            $content += "Você pode encontrar informações sobre o registro na [Wikipedia](https://en.wikipedia.org/wiki/Windows_Registry) e no [site da Microsoft](https://learn.microsoft.com/en-us/windows/win32/sysinfo/registry).`r`n"
        }
    }

    Set-Content -Path $filename -Value $content -Encoding utf8 -NoNewline

    $percent = [Math]::Min(70, 50 + [int](($tweakCount / $totalTweaks) * 20))
    Update-Progress "Gerando a documentação dos ajustes ($tweakCount/$totalTweaks)" $percent
}

# ==============================================================================
# Gera a documentação dos recursos
# ==============================================================================

Update-Progress "Gerando a documentação dos recursos" 70

$featureNames  = $features.PSObject.Properties.Name
$totalFeatures = $featureNames.Count
$featureCount  = 0

foreach ($itemName in $featureNames) {
    $item = $features.$itemName
    $featureCount++

    if ($item.category -notin $documentedCategories) { continue }
    if ($itemName -eq "WPFFeatureInstall") { continue }

    $category    = $item.category -replace '[^a-zA-Z0-9]', '-'
    $displayName = $itemName -replace $itemnametocut, ''
    $categoryDir = "$featuresOutputDir/$category"
    $filename    = "$categoryDir/$displayName.mdx"

    if (-Not (Test-Path -Path $categoryDir)) { New-Item -ItemType Directory -Path $categoryDir | Out-Null }

    # Escalares de string do JSON são YAML válido e escapam caminhos do Windows e caracteres de controle.
    $title       = ConvertTo-Json -InputObject ([string]$item.Content) -Compress
    $description = ConvertTo-Json -InputObject ([string]$item.Description) -Compress
    $content     = "---`r`ntitle: $title`r`ndescription: $description`r`neditUrl: false`r`n---`r`n`r`n"

    if ($item.category -in $functionEmbedCategories) {
        $funcName = if ($item.function) { $item.function } else { $buttonFunctionMap[$itemName] }
        if ($funcName -and $functionFiles.ContainsKey($funcName)) {
            $func     = $functionFiles[$funcName]
            $content += Get-GeneratedFromNote -SourceRelativePath $func.RelativePath
            $content += "``````powershell title=`"$($func.RelativePath)`"`r`n"
            $content += $func.Content + "`r`n"
            $content += "```````r`n"
        }
    } else {
        $jsonBlock = Get-RawJsonBlock -ItemName $itemName -JsonLines $featuresLines
        if ($jsonBlock) {
            $content += Get-GeneratedFromNote -SourceRelativePath "config/feature.json"
            $content += "``````json title=`"config/feature.json`"`r`n"
            $content += $jsonBlock.RawText + "`r`n"
            $content += "```````r`n"
        }
    }

    Set-Content -Path $filename -Value $content -Encoding utf8 -NoNewline

    $percent = [Math]::Min(90, 70 + [int](($featureCount / $totalFeatures) * 20))
    Update-Progress "Gerando a documentação dos recursos ($featureCount/$totalFeatures)" $percent
}

Update-Progress "Processo concluído" 100
Write-Host "Geração da documentação concluída."
