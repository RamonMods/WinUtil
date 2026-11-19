#===========================================================================
# Testes - Códigos de saída da reparação do sistema
#===========================================================================

BeforeAll {
    $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

    . (Join-Path $script:repoRoot "functions\public\Invoke-WPFSystemRepair.ps1")

    function Step-WinUtilJob { param([string]$Status, [int]$Percent, [string]$State, [string]$Overlay, [switch]$Hide) }
    function Write-WinUtilLog { param($Message, $Level, $Component) }
}

Describe "Invoke-WPFSystemRepair códigos de saída do chkdsk" {
    BeforeEach {
        Mock Write-WinUtilLog { }
        Mock Write-Warning { }
        Mock Step-WinUtilJob { }
    }

    It "trata o código de saída 0 do chkdsk como disco limpo" {
        Mock Start-Process { [pscustomobject]@{ ExitCode = 0 } }

        { Invoke-WPFSystemRepair } | Should -Not -Throw
        Should -Invoke -CommandName Start-Process -Times 3 -Exactly
    }

    It "trata o código de saída 1 do chkdsk como sucesso e informa o que ele significa" {
        Mock Start-Process {
            [pscustomobject]@{ ExitCode = $(if (($ArgumentList -join " ") -match "chkdsk") { 1 } else { 0 }) }
        }

        { Invoke-WPFSystemRepair } | Should -Not -Throw
        Should -Invoke -CommandName Write-Warning -ParameterFilter {
            $Message -like "*errors were found and fixed*"
        }
    }

    It "trata o código de saída 2 do chkdsk como sucesso e informa o que ele significa" {
        Mock Start-Process {
            [pscustomobject]@{ ExitCode = $(if (($ArgumentList -join " ") -match "chkdsk") { 2 } else { 0 }) }
        }

        { Invoke-WPFSystemRepair } | Should -Not -Throw
        Should -Invoke -CommandName Write-Warning -ParameterFilter {
            $Message -like "*cleanup was performed*"
        }
    }

    It "falha no código de saída 3 do chkdsk, que uma verificação online não consegue reparar" {
        Mock Start-Process {
            [pscustomobject]@{ ExitCode = $(if (($ArgumentList -join " ") -match "chkdsk") { 3 } else { 0 }) }
        }

        { Invoke-WPFSystemRepair } | Should -Throw "*Checking the disk for errors failed with exit code 3*"
    }

    It "não executa as etapas seguintes após a falha do chkdsk" {
        Mock Start-Process {
            [pscustomobject]@{ ExitCode = $(if (($ArgumentList -join " ") -match "chkdsk") { 3 } else { 0 }) }
        }

        { Invoke-WPFSystemRepair } | Should -Throw
        Should -Invoke -CommandName Start-Process -Times 1 -Exactly
    }
}

Describe "Invoke-WPFSystemRepair códigos por etapa" {
    BeforeEach {
        Mock Write-WinUtilLog { }
        Mock Write-Warning { }
        Mock Step-WinUtilJob { }
    }

    It "aceita 3010 do DISM como imagem reparada aguardando uma reinicialização" {
        Mock Start-Process {
            [pscustomobject]@{ ExitCode = $(if (($ArgumentList -join " ") -match "dism") { 3010 } else { 0 }) }
        }

        { Invoke-WPFSystemRepair } | Should -Not -Throw
        Should -Invoke -CommandName Write-Warning -ParameterFilter {
            $Message -like "*a restart is needed*"
        }
    }

    It "falha em 3010 do chkdsk, onde isso não significa uma reinicialização pendente" {
        Mock Start-Process {
            [pscustomobject]@{ ExitCode = $(if (($ArgumentList -join " ") -match "chkdsk") { 3010 } else { 0 }) }
        }

        { Invoke-WPFSystemRepair } | Should -Throw "*exit code 3010*"
    }

    It "falha em qualquer valor diferente de zero do sfc, que não tem códigos de sucesso próprios" {
        Mock Start-Process {
            [pscustomobject]@{ ExitCode = $(if (($ArgumentList -join " ") -match "sfc") { 1 } else { 0 }) }
        }

        { Invoke-WPFSystemRepair } | Should -Throw "*Scanning protected system files failed with exit code 1*"
    }
}
