# Executa o comportamento de busca com controles WPF reais em um novo processo do Windows PowerShell.
# Outros arquivos do Pester instalam tipos de interface leves que não podem coexistir com o WPF.
Describe "Filtragem de busca com controles WPF reais" {
    It "preserva o comportamento de busca e categoria no Windows PowerShell 5.1" -Skip:($env:OS -ne "Windows_NT") {
        $env:WINUTIL_WPF_TEST_ROOT = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
        $env:WINUTIL_WPF_PESTER_PATH = Join-Path (Get-Module Pester).ModuleBase "Pester.psd1"
        try {
            $scriptText = @'
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework
if ([Windows.Controls.Border].Assembly.GetName().Name -ne 'PresentationFramework') {
    throw 'The search integration test requires real WPF controls.'
}
Import-Module $env:WINUTIL_WPF_PESTER_PATH -Force
if ((Get-Module Pester).Version -ne [version]"5.8.0") {
    throw "The WPF search test requires Pester 5.8.0."
}
Invoke-Pester -Path (Join-Path $env:WINUTIL_WPF_TEST_ROOT 'pester/search-filter.Tests.ps1') -Output Detailed -CI
'@
            $encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($scriptText))
            $output = & powershell.exe -NoLogo -NoProfile -NonInteractive -STA -EncodedCommand $encodedCommand 2>&1
            $result = $LASTEXITCODE
            Write-Host ($output -join [Environment]::NewLine)
            $result | Should -Be 0
        } finally {
            Remove-Item Env:WINUTIL_WPF_TEST_ROOT -ErrorAction SilentlyContinue
            Remove-Item Env:WINUTIL_WPF_PESTER_PATH -ErrorAction SilentlyContinue
        }
    }
}
