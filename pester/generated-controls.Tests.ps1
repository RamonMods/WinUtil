#===========================================================================
# Testes - Tempo de vida dos controles gerados

BeforeAll {
    $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
    $script:xamlText = Get-Content -Path (Join-Path $script:repoRoot "xaml\inputXML.xaml") -Raw

    # Nomes que só existem depois que uma aba foi construída a partir da configuração
    $script:generatedNames = @(
        Get-ChildItem -Path (Join-Path $script:repoRoot "config") -Filter *.json | ForEach-Object {
            $config = Get-Content -Path $_.FullName -Raw | ConvertFrom-Json
            $config.PSObject.Properties.Name
        }
    ) | Sort-Object -Unique | Where-Object { $script:xamlText -notmatch "Name=`"$([regex]::Escape($_))`"" }
}

Describe "Controles gerados" {
    # O conteúdo da aba é construído após a primeira renderização, então qualquer referência a um controle gerado
    # feita durante a construção da interface ocorre enquanto o controle ainda é $null. Isso produziu três erros silenciosos
    # "Não é possível chamar um método em uma expressão sem valor".
    It "não são tocados enquanto a interface está sendo construída" {
        $uiScript = Get-Content -Path (Join-Path $script:repoRoot "functions\private\Start-WinUtilUserInterface.ps1") -Raw

        $referenced = @(
            [regex]::Matches($uiScript, '\$sync(?:\["([A-Za-z_][A-Za-z0-9_]*)"\]|\.([A-Za-z_][A-Za-z0-9_]*))') |
                ForEach-Object { if ($_.Groups[1].Success) { $_.Groups[1].Value } else { $_.Groups[2].Value } }
        ) | Sort-Object -Unique

        $tooEarly = @($referenced | Where-Object { $script:generatedNames -contains $_ })

        if ($tooEarly.Count -gt 0) {
            throw "Start-WinUtilUserInterface touches generated control(s) that do not exist yet: $($tooEarly -join ', '). Wire them from Initialize-WinUtilInstallTabControls or the tab that creates them."
        }
    }




}
