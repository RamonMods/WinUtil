#===========================================================================
# Testes - Resultados de execução de pacotes
#===========================================================================

BeforeAll {
    $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

    . (Join-Path $script:repoRoot "functions\private\Install-WinUtilProgramWinget.ps1")
    . (Join-Path $script:repoRoot "functions\private\Install-WinUtilProgramChoco.ps1")
    . (Join-Path $script:repoRoot "functions\private\Complete-WinUtilPackageRun.ps1")

    function Step-WinUtilJob { param([string]$Status, [int]$Percent, [string]$State, [string]$Overlay, [switch]$Hide) }
    function Write-WinUtilLog {
        param($Message, $Level, $Component)
    }
}

Describe "Resultados de Install-WinUtilProgramWinget" {
    BeforeEach {
        Mock Write-WinUtilLog { }
    }

    It "informa sucesso para código de saída 0" {
        Mock Start-Process { [pscustomobject]@{ ExitCode = 0 } }

        $result = Install-WinUtilProgramWinget -Action Install -Programs @("Git.Git")

        $result.Outcome | Should -Be "Succeeded"
        $result.Package | Should -Be "Git.Git"
        $result.Manager | Should -Be "winget"
    }




    It "informa um pacote já instalado como ignorado em vez de falho" {
        Mock Start-Process { [pscustomobject]@{ ExitCode = -1978335135 } }

        $result = Install-WinUtilProgramWinget -Action Install -Programs @("Git.Git")

        $result.Outcome | Should -Be "Skipped"
        $result.Detail | Should -Be "já instalado"
    }

    It "ignora um pacote por usuário que o WinGet elevado não pode atualizar durante a instalação" {
        Mock Start-Process { [pscustomobject]@{ ExitCode = -1978335107 } }

        $result = Install-WinUtilProgramWinget -Action Install -Programs @("Microsoft.Sysinternals.ProcessExplorer")

        $result.Outcome | Should -Be "Skipped"
        $result.Detail | Should -Be "já instalado para o usuário atual; o WinUtil elevado não pode atualizá-lo"
        Should -Invoke -CommandName Write-WinUtilLog -Times 1 -Exactly -ParameterFilter {
            $Level -eq "INFO" -and $Message -like "*skipped: Microsoft.Sysinternals.ProcessExplorer*"
        }
        Should -Invoke -CommandName Start-Process -Times 1 -Exactly
    }

    It "ignora ações que o WinGet elevado não pode executar em um pacote por usuário" {
        $expectedDetails = @{
            Upgrade = "não atualizado; instalado para o usuário atual e o WinUtil elevado não pode modificá-lo"
            Uninstall = "continua instalado para o usuário atual; o WinUtil elevado não pode desinstalá-lo"
        }

        foreach ($action in $expectedDetails.Keys) {
            Mock Start-Process { [pscustomobject]@{ ExitCode = -1978335107 } }

            $result = Install-WinUtilProgramWinget -Action $action -Programs @("Microsoft.Sysinternals.ProcessExplorer")

            $result.Outcome | Should -Be "Skipped"
            $result.Detail | Should -Be $expectedDetails[$action]
            $result.ExitCode | Should -Be -1978335107
        }

        Should -Invoke -CommandName Start-Process -Times 2 -Exactly
    }

    It "informa qualquer outro código de saída como falha" {
        Mock Start-Process { [pscustomobject]@{ ExitCode = -1978335212 } }

        $result = Install-WinUtilProgramWinget -Action Install -Programs @("Git.Git")

        $result.Outcome | Should -Be "Failed"
        $result.ExitCode | Should -Be -1978335212
        Should -Invoke -CommandName Write-WinUtilLog -Times 1 -Exactly -ParameterFilter {
            $Level -eq "ERROR" -and $Message -like "*failed: Git.Git*"
        }
    }

    It "retorna um resultado por pacote" {
        Mock Start-Process { [pscustomobject]@{ ExitCode = 0 } }

        $results = @(Install-WinUtilProgramWinget -Action Install -Programs @("Git.Git", "VideoLAN.VLC"))

        $results.Count | Should -Be 2
    }

    It "trata a necessidade de reinício como sucesso, não falha" {
        # 3010 e 1641 significam que o instalador funcionou e o Windows quer reiniciar. Contá-los como
        # falhas marca toda a execução de atualização como quebrada quando nada deu errado.
        foreach ($code in @(3010, 1641)) {
            Mock Start-Process { [pscustomobject]@{ ExitCode = $code } }.GetNewClosure()

            $result = Install-WinUtilProgramWinget -Action Install -Programs @("Git.Git")

            $result.Outcome | Should -Be "Succeeded" -Because "código de saída $code significa que a instalação funcionou"
            $result.Detail | Should -Match "reinici"
        }
    }
}

Describe "Resultados de Install-WinUtilProgramChoco" {
    BeforeAll {
        function choco { $global:LASTEXITCODE = 0 }
    }

    BeforeEach {
        Mock Write-WinUtilLog { }
        Mock Step-WinUtilJob { }
        Mock Get-Command { "choco" } -ParameterFilter { $Name -eq "choco" }
    }

    It "trata um código de saída que exige reinício como sucesso" {
        Mock choco { $global:LASTEXITCODE = 3010 }

        $result = Install-WinUtilProgramChoco -Action Install -Programs @("git")
        $result.Outcome | Should -Be "Succeeded"
        $result.Detail | Should -Match "reinici"
    }

    It "informa um código de saída diferente de zero como falha" {
        Mock choco { $global:LASTEXITCODE = 1 }

        (Install-WinUtilProgramChoco -Action Install -Programs @("git")).Outcome | Should -Be "Failed"
    }

    It "informa nada a fazer como ignorado em vez de falho" {
        Mock choco { $global:LASTEXITCODE = 2 }

        (Install-WinUtilProgramChoco -Action Install -Programs @("git")).Outcome | Should -Be "Skipped"
    }

    # O motivo está na própria saída do choco, que é registrada em log; o resultado carrega o código
    It "informa o código de saída quando o choco falha" {
        Mock choco { $global:LASTEXITCODE = 1; "git is not installed. Cannot uninstall a non-existent package." }

        $result = Install-WinUtilProgramChoco -Action Uninstall -Programs @("git")

        $result.Outcome | Should -Be "Failed"
        $result.Detail | Should -Be "código de saída 1"
    }

    It "falha em vez de reutilizar um código de saída obsoleto quando o Chocolatey não está disponível" {
        $global:LASTEXITCODE = 0
        Mock Get-Command { $null } -ParameterFilter { $Name -eq "choco" }

        $result = Install-WinUtilProgramChoco -Action Uninstall -Programs @("git")

        $result.Outcome | Should -Be "Failed"
        $result.ExitCode | Should -Be -1
        $result.Detail | Should -Be "O comando do Chocolatey não iniciou"
    }
}

Describe "Complete-WinUtilPackageRun" {
    BeforeEach {
        Mock Write-WinUtilLog { }
        Mock Write-Host { }
        Mock Write-Warning { }
    }

    It "informa as contagens de cada resultado" {
        $results = @(
            [pscustomobject]@{ Package = "a"; Outcome = "Succeeded"; Detail = "exit code 0" },
            [pscustomobject]@{ Package = "b"; Outcome = "Skipped"; Detail = "já instalado" }
        )

        Complete-WinUtilPackageRun -Action "Install" -Results $results

        Should -Invoke -CommandName Write-WinUtilLog -Times 1 -Exactly -ParameterFilter {
            $Message -eq "Resumo de Install: 1 com sucesso, 1 ignorados, 0 com falha"
        }
    }

    It "não falha uma instalação quando todos os pacotes selecionados já estão presentes" {
        $results = @(
            [pscustomobject]@{ Package = "Microsoft.Sysinternals.ProcessMonitor"; Outcome = "Skipped"; Detail = "no applicable update" },
            [pscustomobject]@{ Package = "Microsoft.Sysinternals.ProcessExplorer"; Action = "Install"; ExitCode = -1978335107; Outcome = "Skipped"; Detail = "já instalado para o usuário atual; o WinUtil elevado não pode atualizá-lo" }
        )

        { Complete-WinUtilPackageRun -Action "Install" -Results $results } | Should -Not -Throw
        Should -Invoke -CommandName Write-WinUtilLog -Times 1 -Exactly -ParameterFilter {
            $Message -eq "Resumo de Install: 0 com sucesso, 2 ignorados, 0 com falha"
        }
        Should -Invoke -CommandName Write-Warning -Times 1 -Exactly -ParameterFilter {
            $Message -eq "1 ação(ões) de pacote foram ignoradas porque o WinUtil elevado não pode modificar instalações do escopo do usuário."
        }
    }

    It "não falha a desinstalação informada de dois pacotes quando o WinGet elevado não pode agir no escopo do usuário" {
        Mock Start-Process { [pscustomobject]@{ ExitCode = -1978335107 } }
        $results = @(Install-WinUtilProgramWinget -Action Uninstall -Programs @(
            "Microsoft.Sysinternals.ProcessMonitor",
            "Microsoft.Sysinternals.ProcessExplorer"
        ))

        { Complete-WinUtilPackageRun -Action "Uninstall" -Results $results } | Should -Not -Throw
        @($results | Where-Object Outcome -eq "Skipped").Count | Should -Be 2
        Should -Invoke -CommandName Write-WinUtilLog -Times 1 -Exactly -ParameterFilter {
            $Message -eq "Resumo de Uninstall: 0 com sucesso, 2 ignorados, 0 com falha"
        }
        Should -Invoke -CommandName Write-Warning -Times 1 -Exactly -ParameterFilter {
            $Message -eq "2 ação(ões) de pacote foram ignoradas porque o WinUtil elevado não pode modificar instalações do escopo do usuário."
        }
    }

    It "falha o trabalho quando um pacote falhou" {
        $results = @(
            [pscustomobject]@{ Package = "a"; Outcome = "Succeeded"; Detail = "exit code 0" },
            [pscustomobject]@{ Package = "b"; Outcome = "Failed"; Detail = "exit code 5" }
        )

        $caught = $null
        try {
            Complete-WinUtilPackageRun -Action "Install" -Results $results
        } catch {
            $caught = $_
        }

        $caught.Exception.Message | Should -BeLike "1 de 2 pacote(s) falharam: b. *"
        $caught.Exception.Data["WinUtilErrorReported"] | Should -BeTrue
    }

    It "aceita uma execução vazia" {
        { Complete-WinUtilPackageRun -Action "Install" -Results @() } | Should -Not -Throw
    }
}
