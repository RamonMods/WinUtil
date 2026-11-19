BeforeAll {
    [xml]$unattend = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../tools/autounattend.xml') -Raw
    function Get-CompletionTail {
        param([string]$Name, [string]$Variable)
        $text = $unattend.SelectSingleNode("//*[local-name()='File' and @path='C:\Windows\Setup\Scripts\$Name.ps1']").InnerText
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$tokens, [ref]$errors)
        if ($errors.Count) { throw ($errors | Out-String) }
        $start = @($ast.EndBlock.Statements | Where-Object {
            $_ -is [System.Management.Automation.Language.AssignmentStatementAst] -and
            $_.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
            $_.Left.VariablePath.UserPath -eq $Variable
        })
        if ($start.Count -ne 1) { throw "Expected one $Variable assignment in $Name." }
        # Executa apenas a coordenação de conclusão, nunca comandos de configuração, downloads ou instaladores.
        [scriptblock]::Create($text.Substring($start[0].Extent.StartOffset))
    }
    $script:publishCompletion = Get-CompletionTail 'UserOnce' 'completionDir'
    $script:awaitCompletion = Get-CompletionTail 'FirstLogon' 'completionPath'
    # Sobrescreve o comando real de reinício mesmo no Windows; um mock ausente nunca deve reiniciar o host de teste.
    function Restart-Computer { param([switch]$Force) throw 'Restart must be mocked.' }
}

Describe 'Coordenação de reinício no primeiro logon' {
    BeforeEach {
        $script:savedLocalAppData = $env:LOCALAPPDATA
        $env:LOCALAPPDATA = Join-Path $TestDrive ('profile[1]-' + [guid]::NewGuid())
        $script:completionPath = Join-Path $env:LOCALAPPDATA 'WinUtil/UserOnce.complete'
        $script:now = [datetime]'2026-01-01T00:00:00'
        $script:sleeps = 0
        $script:messages = [System.Collections.Generic.List[string]]::new()
        Mock Get-Date { $script:now }
        Mock Start-Sleep { $script:sleeps++; $script:now = $script:now.AddMinutes(1) }
        Mock Out-File { $script:messages.Add([string]$InputObject) }
        Mock Restart-Computer { }
    }

    AfterEach {
        $env:LOCALAPPDATA = $script:savedLocalAppData
    }

    It 'reinicia imediatamente quando a configuração do usuário termina primeiro' {
        & $script:publishCompletion
        Test-Path -LiteralPath $script:completionPath | Should -BeTrue
        & $script:awaitCompletion
        Should -Invoke Restart-Computer -Times 1 -Exactly -ParameterFilter { $Force }
        Should -Invoke Start-Sleep -Times 0 -Exactly
        Test-Path -LiteralPath $script:completionPath | Should -BeTrue
    }

    It 'aguarda a configuração atrasada do usuário antes de reiniciar' {
        Mock Start-Sleep {
            $script:sleeps++
            if ($script:sleeps -eq 2) { & $script:publishCompletion }
        }
        Mock Restart-Computer {
            $script:sleeps | Should -Be 2
            Test-Path -LiteralPath $script:completionPath | Should -BeTrue
        }
        & $script:awaitCompletion
        Should -Invoke Start-Sleep -Times 2 -Exactly
        Should -Invoke Restart-Computer -Times 1 -Exactly
    }

    It 'registra o tempo limite e deixa a máquina ligada quando a conclusão nunca chega' {
        & $script:awaitCompletion
        Should -Invoke Start-Sleep -Times 5 -Exactly
        Should -Invoke Restart-Computer -Times 0 -Exactly
        ($script:messages -join '\n') | Should -Match 'Timed out.*Automatic restart skipped'
    }

    It 'não reinicia se a verificação de conclusão falhar' {
        Mock Test-Path { throw 'Cannot read completion marker' }
        { & $script:awaitCompletion } | Should -Throw '*Cannot read completion marker*'
        Should -Invoke Restart-Computer -Times 0 -Exactly
    }
}
