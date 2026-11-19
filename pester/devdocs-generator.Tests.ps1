BeforeAll {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
    $script:fixtureRoot = Join-Path $TestDrive "repo"
    foreach ($directory in @("tools", "config", "functions/public", "functions/private")) {
        $null = New-Item -ItemType Directory -Path (Join-Path $script:fixtureRoot $directory) -Force
    }
    Copy-Item -LiteralPath (Join-Path $repoRoot "tools/devdocs-generator.ps1") -Destination (Join-Path $script:fixtureRoot "tools/devdocs-generator.ps1")
    Set-Content -LiteralPath (Join-Path $script:fixtureRoot "functions/public/Invoke-WPFButton.ps1") -Value "function Invoke-WPFButton {}"

    $script:escapedTitle = 'Path C:\Tools\ "quoted" # title'
    $script:escapedDescription = "Saved in %LocalAppData%\winutil.`r`nSecond line`twith 'quotes' and `"double quotes`". Ends in C:\Temp\"
    foreach ($kind in @("tweaks", "feature")) {
        $category = if ($kind -eq "tweaks") { "Essential Tweaks" } else { "Features" }
        $prefix = if ($kind -eq "tweaks") { "WPFTweaks" } else { "WPFFeature" }
        $config = [ordered]@{}
        $config["${prefix}Escaped"] = @{ Category = $category; Type = "CheckBox"; Content = $script:escapedTitle; Description = $script:escapedDescription }
        $config["${prefix}Empty"] = @{ Category = $category; Type = "CheckBox"; Content = "Empty description" }
        $config | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $script:fixtureRoot "config/$kind.json") -Encoding utf8
    }
    & (Join-Path $script:fixtureRoot "tools/devdocs-generator.ps1")
}

Describe "Metadados da documentação gerada" {
    It "preserva as strings de título e descrição em <Page>" -TestCases @(
        @{ Page = "tweaks/Essential-Tweaks/Escaped.mdx"; Escaped = $true }
        @{ Page = "features/Features/Escaped.mdx"; Escaped = $true }
        @{ Page = "tweaks/Essential-Tweaks/Empty.mdx"; Escaped = $false }
        @{ Page = "features/Features/Empty.mdx"; Escaped = $false }
    ) {
        param($Page, $Escaped)
        $document = Get-Content -LiteralPath (Join-Path $script:fixtureRoot "docs/src/content/docs/code-reference/$Page")
        # Escalares entre aspas em JSON também são escalares entre aspas em YAML. Verifique a ida e volta dos
        # valores emitidos, incluindo caminhos do Windows, aspas, quebras de linha e tabulações.
        $title = ($document[1] -split ': ', 2)[1] | ConvertFrom-Json -ErrorAction Stop
        $description = ($document[2] -split ': ', 2)[1] | ConvertFrom-Json -ErrorAction Stop
        if ($Escaped) {
            $title | Should -BeExactly $script:escapedTitle
            $description | Should -BeExactly $script:escapedDescription
        } else {
            $title | Should -BeExactly "Empty description"
            $description | Should -BeExactly ""
        }
    }
}
