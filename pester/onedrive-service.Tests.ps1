BeforeAll {
    $tweaks = Get-Content (Join-Path $PSScriptRoot '../config/tweaks.json') -Raw | ConvertFrom-Json
    $script:oneDrive = $tweaks.WPFTweaksRemoveOneDrive
    # Isole apenas a proteção do modelo, nunca o script destrutivo do OneDrive ao redor dela.
    function Get-OneSyncGuard {
        param($Action)
        $source = [scriptblock]::Create($script:oneDrive.$Action -join "`n")
        $guards = @($source.Ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.IfStatementAst] -and
                $node.Extent.Text -match 'Set-Service -Name OneSyncSvc'
        }, $true))
        $guards.Count | Should -Be 1
        [scriptblock]::Create($guards[0].Extent.Text)
    }
    function Set-Service {
        param($Name, $StartupType)
        throw "Set-Service must be mocked: $Name $StartupType"
    }
    function Get-Service {
        param($Name)
        throw "Get-Service cannot enumerate the template: $Name"
    }
}

Describe 'Modelo de serviço do OneDrive por usuário' {
    BeforeEach {
        Mock Set-Service {}
        Mock Get-Service { throw 'No running service instance is visible' }
    }

    It 'configura um modelo existente sem consultar uma instância em execução (<Action>)' -TestCases @(
        @{ Action = 'InvokeScript'; ExpectedType = 'Disabled' }
        @{ Action = 'UndoScript'; ExpectedType = 'Automatic' }
    ) {
        param($Action, $ExpectedType)
        $guard = Get-OneSyncGuard -Action $Action
        Mock Test-Path { $true }

        { & $guard } | Should -Not -Throw

        Should -Invoke Test-Path -Times 1 -Exactly -ParameterFilter {
            $LiteralPath -eq 'HKLM:\SYSTEM\CurrentControlSet\Services\OneSyncSvc'
        }
        Should -Invoke Set-Service -Times 1 -Exactly -ParameterFilter {
            $Name -eq 'OneSyncSvc' -and $StartupType -eq $ExpectedType
        }
        Should -Invoke Get-Service -Times 0 -Exactly
    }

    It 'ignora a operação quando o modelo está ausente (<Action>)' -TestCases @(
        @{ Action = 'InvokeScript' }
        @{ Action = 'UndoScript' }
    ) {
        param($Action)
        $guard = Get-OneSyncGuard -Action $Action
        Mock Test-Path { $false }

        { & $guard } | Should -Not -Throw

        Should -Invoke Test-Path -Times 1 -Exactly -ParameterFilter {
            $LiteralPath -eq 'HKLM:\SYSTEM\CurrentControlSet\Services\OneSyncSvc'
        }
        Should -Invoke Set-Service -Times 0 -Exactly
        Should -Invoke Get-Service -Times 0 -Exactly
    }
}
