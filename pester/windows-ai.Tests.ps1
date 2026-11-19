BeforeAll {
    $tweaks = Get-Content (Join-Path $PSScriptRoot '..\config\tweaks.json') -Raw | ConvertFrom-Json
    $script:windowsAI = [scriptblock]::Create($tweaks.WPFTweaksWindowsAI.InvokeScript -join "`n")
    $commandAssignment = $script:windowsAI.Ast.Find({
        param($node)
        $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
        $node.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
        $node.Left.VariablePath.UserPath -eq 'RecallCommand'
    }, $true)
    $script:recallCommand = $commandAssignment.Right.Expression.ScriptBlock.GetScriptBlock()
    . (Join-Path $PSScriptRoot '..\functions\private\Invoke-WinUtilScript.ps1')

    function powershell.exe {
        param([switch]$NoProfile, [switch]$NonInteractive, [scriptblock]$Command)
        throw "powershell.exe must be mocked: $NoProfile $NonInteractive $Command"
    }
    function winget { throw 'winget must be mocked.' }
    function Get-AppxPackage {
        param($Name, [switch]$AllUsers)
        throw "Get-AppxPackage must be mocked: $Name $AllUsers"
    }
    function Remove-AppxPackage {
        param($Package, [switch]$AllUsers)
        throw "Remove-AppxPackage must be mocked: $Package $AllUsers"
    }
    function Get-LocalUser {
        param($Name)
        throw "Get-LocalUser must be mocked: $Name"
    }
    function Disable-WindowsOptionalFeature {
        [CmdletBinding()]
        param($FeatureName, [switch]$Online, [switch]$NoRestart)
        throw "Disable-WindowsOptionalFeature must be mocked: $FeatureName $Online $NoRestart"
    }
    function Write-WinUtilLog {
        param($Message, $Component, $Level)
        throw "Write-WinUtilLog must be mocked: $Message $Component $Level"
    }
}

Describe 'Solução alternativa de host do Windows AI Recall' {
    BeforeEach {
        $script:savedExitCode = $global:LASTEXITCODE
        Mock Get-AppxPackage { }
        Mock Get-LocalUser { [pscustomobject]@{ Sid = [pscustomobject]@{ Value = 'S-1-5-21-1234' } } }
        Mock New-Item { }
        Mock Remove-AppxPackage { }
        Mock Set-Service { }
        Mock winget { $global:LASTEXITCODE = 1 }
        Mock powershell.exe { $global:LASTEXITCODE = 0 }
        Mock Disable-WindowsOptionalFeature { [pscustomobject]@{ RestartNeeded = $false } }
        Mock Write-Host { }
        Mock Write-Warning { }
        Mock Write-WinUtilLog { }
    }

    AfterEach { $global:LASTEXITCODE = $script:savedExitCode }

    It 'executa o Recall por meio de um processo do Windows PowerShell não interativo' {
        & $script:windowsAI

        Should -Invoke powershell.exe -Times 1 -Exactly -ParameterFilter {
            $NoProfile -and $NonInteractive -and $Command -is [scriptblock]
        }
        Should -Invoke Disable-WindowsOptionalFeature -Times 0 -Exactly
        Should -Invoke Write-Host -Times 1 -Exactly -ParameterFilter { $Object -eq 'Windows AI Disabled' }
    }

    It 'desativa apenas o Recall no sistema operacional em execução sem reiniciar' {
        $output = & $script:recallCommand

        $output | Should -BeNullOrEmpty
        Should -Invoke Disable-WindowsOptionalFeature -Times 1 -Exactly -ParameterFilter {
            $FeatureName -eq 'Recall' -and $Online -and $NoRestart -and $ErrorAction -eq 'Stop'
        }
    }

    It 'permite que uma falha do DISM interrompa o comando filho' {
        Mock Disable-WindowsOptionalFeature { throw 'DISM failed' }

        { & $script:recallCommand } | Should -Throw '*DISM failed*'
    }

    It 'mantém um aviso bem-sucedido do filho visível sem tratá-lo como falha' {
        Mock powershell.exe {
            $global:LASTEXITCODE = 0
            'WARNING: Restart is suppressed because NoRestart is specified.'
        }

        { & $script:windowsAI } | Should -Not -Throw

        Should -Invoke Write-Host -Times 1 -Exactly -ParameterFilter { $Object -like '*Restart is suppressed*' }
        Should -Invoke Write-Host -Times 1 -Exactly -ParameterFilter { $Object -eq 'Windows AI Disabled' }
    }

    It 'relata uma saída com falha do filho com detalhes e sem mensagem de sucesso' {
        Mock powershell.exe {
            $global:LASTEXITCODE = 1
            'Class not registered'
        }

        { & $script:windowsAI } | Should -Throw '*Failed to disable Recall (exit code 1): Class not registered*'
        Should -Invoke Write-Host -Times 0 -Exactly -ParameterFilter { $Object -eq 'Windows AI Disabled' }
    }

    It 'relata a falha do filho pelo wrapper de log de ajustes existente' {
        Mock powershell.exe {
            $global:LASTEXITCODE = 1
            'DISM failed'
        }

        Invoke-WinUtilScript -Name 'WPFTweaksWindowsAI' -ScriptBlock $script:windowsAI

        Should -Invoke Write-WinUtilLog -Times 1 -Exactly -ParameterFilter {
            $Level -eq 'ERROR' -and $Message -like '*Failed to disable Recall*DISM failed*'
        }
        Should -Invoke Write-Host -Times 0 -Exactly -ParameterFilter { $Object -eq 'Windows AI Disabled' }
    }
}
