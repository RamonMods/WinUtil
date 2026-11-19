#===========================================================================
# Testes - Get-WinUtilVariables
#===========================================================================

BeforeAll {
    $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
    $script:originalSyncVariable = Get-Variable -Name sync -Scope Global -ErrorAction SilentlyContinue
    if ($script:originalSyncVariable) {
        $script:originalSyncValue = $script:originalSyncVariable.Value
    }
    $global:sync = [Hashtable]::Synchronized(@{})

    # Configura algumas variáveis de teste
    $global:sync["WPFTestString"] = "I am a string"
    $global:sync["WPFTestObj1"] = [PSCustomObject]@{ Name = "Test1" }
    $global:sync["WPFTestObj2"] = [PSCustomObject]@{ Name = "Test2" }
    $global:sync["WPFTestButton"] = [System.Version]::new("1.0.0.0")
    $global:sync["OtherVar"] = "Not a WPF variable"

    . (Join-Path $script:repoRoot "functions\private\Get-WinUtilVariables.ps1")
}

AfterAll {
    if ($script:originalSyncVariable) {
        Set-Variable -Name sync -Value $script:originalSyncValue -Scope Global -Force
    } else {
        Remove-Variable -Name sync -Scope Global -ErrorAction SilentlyContinue
    }
}

Describe "Get-WinUtilVariables" {

    It "retorna todas as chaves com prefixo WPF quando nenhum tipo é fornecido" {
        $result = Get-WinUtilVariables
        $result.Count | Should -Be 4
        $result | Should -Contain "WPFTestString"
        $result | Should -Contain "WPFTestObj1"
        $result | Should -Contain "WPFTestObj2"
        $result | Should -Contain "WPFTestButton"
        $result | Should -Not -Contain "OtherVar"
    }

    It "retorna apenas chaves WPF que correspondem ao tipo exato especificado" {
        $result = Get-WinUtilVariables -Type "String"
        $result.Count | Should -Be 1
        $result | Should -Contain "WPFTestString"
    }

    It "retorna múltiplos objetos que correspondem a PSCustomObject" {
        $result = Get-WinUtilVariables -Type "PSCustomObject"
        $result.Count | Should -Be 2
        $result | Should -Contain "WPFTestObj1"
        $result | Should -Contain "WPFTestObj2"
    }

    It "retorna uma lista vazia quando nenhum tipo correspondente é encontrado" {
        $result = Get-WinUtilVariables -Type "Int32"
        $result | Should -BeNullOrEmpty
    }
}
