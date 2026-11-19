#===========================================================================
# Testes - Execuções headless nunca precisam de janela

BeforeAll {
    $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
    $script:functionRoot = Join-Path $script:repoRoot "functions"
    $script:mainScript = Get-Content -Path (Join-Path $script:repoRoot "scripts\main.ps1") -Raw
    $script:startScript = Get-Content -Path (Join-Path $script:repoRoot "scripts\start.ps1") -Raw
    $startAst = [System.Management.Automation.Language.Parser]::ParseInput($script:startScript, [ref]$null, [ref]$null)
    $script:fileProcessFunction = $startAst.Find({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -eq "Test-WinUtilOwnsFileProcess"
    }, $true).Extent.Text
    $script:elevationCommandFunction = $startAst.Find({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -eq "New-WinUtilElevationCommand"
    }, $true).Extent.Text

    . (Join-Path $script:functionRoot "private\Update-WinUtilSelections.ps1")
    . (Join-Path $script:functionRoot "public\Invoke-WPFImpex.ps1")

    # Stubs para que os mocks abaixo tenham o que substituir; as funções reais estão em outros arquivos
    function Write-WinUtilLog { param($Level, $Component, $Message, [switch]$Detail) }
    function Write-WinUtilTimingSummary { param($Scope, $TotalMilliseconds) }
    function Clear-WinUtilActiveJob { param([string]$Token) $sync.ActiveJobToken = $null; $sync.ActiveJob = $null; return $true }
    # Uma etapa com tempo esgotado interrompe seu worker antes da próxima começar, então a execução precisa de ambos
    function Stop-WinUtilActiveWork { param([switch]$NoWait) }
    function Test-WinUtilActiveWorkRunning { return $false }
    function Write-WinUtilErrorRecord { param($ErrorRecord, $Component, $Context) }
    function Invoke-WPFtweaksbutton { }
    function Invoke-WPFToggleSelections { }
    function Invoke-WPFFeatureInstall { }
    function Invoke-WPFInstall { }
    function Invoke-WPFAppxRemoval { }
}

Describe "Ponto de entrada headless" {
    It "trata predefinição e configuração por um único caminho" {
        $script:mainScript | Should -Match 'if \(\$Preset -or \$Config\) \{'
    }

    It "retorna um resultado sem encerrar um chamador em memória" {
        $script:mainScript | Should -Match 'if \(\$env:WINUTIL_HEADLESS_CHILD -eq "1" -or \$script:WinUtilIsFileProcess\) \{[\s\S]*exit \$headlessCode[\s\S]*\$global:LASTEXITCODE = \$headlessCode[\s\S]*return \$headlessCode'
        $script:mainScript | Should -Match 'Write-WinUtilAutoRunSummary'
    }

    It "sai com o resultado quando o modo headless possui um processo baseado em arquivo" {
        $script:startScript | Should -Match '\$script:WinUtilIsFileProcess = Test-WinUtilOwnsFileProcess'
        $script:mainScript | Should -Match '-or \$script:WinUtilIsFileProcess\) \{[\s\S]*exit \$headlessCode'
    }

    It "reconhece alvos de arquivo diretos explícitos e posicionais como possuidores do processo" {
        . ([scriptblock]::Create($script:fileProcessFunction))
        $winUtilPath = Join-Path $script:repoRoot "winutil.ps1"
        $wrapperPath = Join-Path $TestDrive "wrapper.ps1"

        Test-WinUtilOwnsFileProcess -ScriptPath $winUtilPath -CommandLineArgs @("pwsh.dll", "-File", $winUtilPath) | Should -BeTrue
        Test-WinUtilOwnsFileProcess -ScriptPath $winUtilPath -CommandLineArgs @("pwsh.dll", "-f", $winUtilPath) | Should -BeTrue
        Test-WinUtilOwnsFileProcess -ScriptPath $winUtilPath -CommandLineArgs @("pwsh.dll", "-EP", "Bypass", "-File", $winUtilPath) | Should -BeTrue
        Test-WinUtilOwnsFileProcess -ScriptPath $winUtilPath -CommandLineArgs @("powershell.exe", "-Version", "5.1", "-File", $winUtilPath) | Should -BeTrue
        Test-WinUtilOwnsFileProcess -ScriptPath $winUtilPath -CommandLineArgs @("powershell.exe", "-PSConsoleFile", "profile.psc1", "-File", $winUtilPath) | Should -BeTrue
        Test-WinUtilOwnsFileProcess -ScriptPath $winUtilPath -CommandLineArgs @("pwsh.dll", "-config", "profile.pssc", "-File", $winUtilPath) | Should -BeTrue
        Test-WinUtilOwnsFileProcess -ScriptPath $winUtilPath -CommandLineArgs @("pwsh.dll", "-W", "Hidden", $winUtilPath) | Should -BeTrue
        Test-WinUtilOwnsFileProcess -ScriptPath $winUtilPath -CommandLineArgs @("pwsh.dll", "-WorkingD", "C:\", $winUtilPath) | Should -BeTrue
        Test-WinUtilOwnsFileProcess -ScriptPath $winUtilPath -CommandLineArgs @("pwsh.dll", "-Execu", "Bypass", $winUtilPath) | Should -BeTrue
        Test-WinUtilOwnsFileProcess -ScriptPath $winUtilPath -CommandLineArgs @("pwsh.dll", "-i", $winUtilPath) | Should -BeTrue
        Test-WinUtilOwnsFileProcess -ScriptPath $winUtilPath -CommandLineArgs @("pwsh.dll", $winUtilPath) | Should -BeTrue
        Test-WinUtilOwnsFileProcess -ScriptPath $winUtilPath -CommandLineArgs @("pwsh.dll", "-NoProfile", $winUtilPath) | Should -BeTrue
        Test-WinUtilOwnsFileProcess -ScriptPath $winUtilPath -CommandLineArgs @("pwsh.dll", "-NoExit", $winUtilPath) | Should -BeFalse
        Test-WinUtilOwnsFileProcess -ScriptPath $winUtilPath -CommandLineArgs @("pwsh.dll", "-noe", $winUtilPath) | Should -BeFalse
        Test-WinUtilOwnsFileProcess -ScriptPath $winUtilPath -CommandLineArgs @("pwsh.dll", "-File", $wrapperPath) | Should -BeFalse
        Test-WinUtilOwnsFileProcess -ScriptPath $winUtilPath -CommandLineArgs @("pwsh.dll", $wrapperPath, "-HarnessPath", $winUtilPath) | Should -BeFalse
        Test-WinUtilOwnsFileProcess -ScriptPath $winUtilPath -CommandLineArgs @("pwsh.dll", "-Command", "& '$winUtilPath'") | Should -BeFalse
    }

    It "falha em inicializações com linguagem restrita e posse de processo sem encerrar chamadores em memória" {
        $script:startScript | Should -Match 'LanguageMode -ne ''FullLanguage''[\s\S]*\$global:LASTEXITCODE = 1[\s\S]*if \(\$env:WINUTIL_HEADLESS_CHILD -eq "1" -or \$script:WinUtilIsFileProcess\) \{ exit 1 \}[\s\S]*return 1'
    }

    It "trata valores hostis de parâmetro de elevação como dados em vez de código executável" {
        . ([scriptblock]::Create($script:elevationCommandFunction))
        $targetDirectory = Join-Path $TestDrive "O'Brien"
        $targetScript = Join-Path $targetDirectory "target.ps1"
        $markerPath = Join-Path $TestDrive "injected.txt"
        New-Item -ItemType Directory -Path $targetDirectory | Out-Null
        'param([string]$Config) Write-Output $Config' | Set-Content -LiteralPath $targetScript
        $hostileConfig = "'; Set-Content -LiteralPath '$markerPath' -Value injected; #"

        $encodedCommand = New-WinUtilElevationCommand -ScriptPath $targetScript -Parameters @{ Config = $hostileConfig } -Headless
        $bootstrap = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($encodedCommand))
        $previousChildFlag = $env:WINUTIL_HEADLESS_CHILD
        try {
            $output = & ([scriptblock]::Create($bootstrap))
        } finally {
            $env:WINUTIL_HEADLESS_CHILD = $previousChildFlag
        }

        $bootstrap | Should -Not -Match ([regex]::Escape($hostileConfig))
        $output | Should -Be $hostileConfig
        Test-Path -LiteralPath $markerPath | Should -BeFalse
    }

    It "propaga códigos diretos de -File sem encerrar um wrapper baseado em arquivo" {
        $harnessPath = Join-Path $TestDrive "headless-exit-harness.ps1"
        $wrapperPath = Join-Path $TestDrive "headless-exit-wrapper.ps1"
        @"
param([int]`$Code)
$($script:fileProcessFunction)
`$ownsProcess = Test-WinUtilOwnsFileProcess -ScriptPath `$PSCommandPath -CommandLineArgs ([Environment]::GetCommandLineArgs())
if (`$ownsProcess) { exit `$Code }
return `$Code
"@ | Set-Content -LiteralPath $harnessPath
        @'
param([string]$HarnessPath)
& $HarnessPath -Code 7 | Out-Null
exit 23
'@ | Set-Content -LiteralPath $wrapperPath

        $powerShellHosts = @(Get-Command pwsh.exe, powershell.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -Unique)
        $powerShellHosts.Count | Should -BeGreaterThan 0
        foreach ($powerShellHost in $powerShellHosts) {
            & $powerShellHost -ExecutionPolicy Bypass -NoProfile -File $harnessPath -Code 0 | Out-Null
            $LASTEXITCODE | Should -Be 0 -Because "$powerShellHost deve propagar sucesso"

            & $powerShellHost -ExecutionPolicy Bypass -NoProfile -File $harnessPath -Code 7 | Out-Null
            $LASTEXITCODE | Should -Be 7 -Because "$powerShellHost deve propagar falha"

            & $powerShellHost -ExecutionPolicy Bypass -NoProfile -f $harnessPath -Code 7 | Out-Null
            $LASTEXITCODE | Should -Be 7 -Because "$powerShellHost deve suportar o alias -f"

            if ((Split-Path -Leaf $powerShellHost) -like "pwsh*") {
                & $powerShellHost -NoProfile $harnessPath -Code 7 | Out-Null
                $LASTEXITCODE | Should -Be 7 -Because "$powerShellHost deve suportar um alvo de arquivo posicional"
            }

            & $powerShellHost -ExecutionPolicy Bypass -NoProfile -File $wrapperPath -HarnessPath $harnessPath | Out-Null
            $LASTEXITCODE | Should -Be 23 -Because "$powerShellHost deve permitir que o wrapper continue"
        }
    }

    It "propaga uma falha headless do WinUtil compilado sem encerrar seu wrapper" {
        $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
            [Security.Principal.WindowsBuiltInRole]::Administrator
        )
        if (-not $isAdmin) {
            Set-ItResult -Skipped -Because "o processo do WinUtil compilado abriria um prompt do UAC"
            return
        }

        & (Join-Path $script:repoRoot "Compile.ps1")
        $compiledPath = Join-Path $script:repoRoot "winutil.ps1"
        $missingConfig = Join-Path $TestDrive "missing-config.json"
        $wrapperPath = Join-Path $TestDrive "compiled-winutil-wrapper.ps1"
        @'
param([string]$WinUtilPath, [string]$MissingConfig)
$source = Get-Content -LiteralPath $WinUtilPath -Raw
& ([scriptblock]::Create($source)) -Config $MissingConfig | Out-Null
Write-Output "wrapper-continued"
exit 23
'@ | Set-Content -LiteralPath $wrapperPath

        $powerShellHosts = @(Get-Command pwsh.exe, powershell.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -Unique)
        foreach ($powerShellHost in $powerShellHosts) {
            & $powerShellHost -ExecutionPolicy Bypass -NoProfile -File $compiledPath -Config $missingConfig | Out-Null
            $LASTEXITCODE | Should -Be 1 -Because "$powerShellHost deve propagar a falha de importação de configuração do WinUtil"

            $wrapperOutput = @(& $powerShellHost -ExecutionPolicy Bypass -NoProfile -File $wrapperPath -WinUtilPath $compiledPath -MissingConfig $missingConfig)
            $LASTEXITCODE | Should -Be 23 -Because "$powerShellHost deve permitir que o wrapper baseado em arquivo continue"
            $wrapperOutput | Should -Contain "wrapper-continued"
        }
    }

    It "limpa mesmo quando a execução lança exceção" {
        # Sem um finally, uma execução com falha deixa o pool de workers aberto e o arquivo de log retido
        $script:mainScript | Should -Match '\} finally \{[\s\S]*Close-WinUtilRunspacePool[\s\S]*Close-WinUtilLog'
    }

    It "nomeia as predefinições existentes quando recebe uma que não existe" {
        $script:mainScript | Should -Match "Não existe uma predefinição chamada"
    }

    It "aguarda a execução elevada e devolve seu código" {
        # Start-Process sem -Wait retorna imediatamente, então o chamador veria sucesso
        # independentemente do que a execução fez
        $script:startScript | Should -Match '\$elevated = Start-Process[^\r\n]*-Wait -PassThru'
        $script:startScript | Should -Match '\$env:WINUTIL_HEADLESS_CHILD = ''1'''
        $script:startScript | Should -Match '\$global:LASTEXITCODE = \$elevated\.ExitCode[\s\S]*return \$elevated\.ExitCode'
        $script:startScript | Should -Match 'if \(\$script:WinUtilIsFileProcess\) \{ exit \$elevated\.ExitCode \}'
    }
}

Describe "Importação de configuração headless" {
    BeforeEach {
        $global:sync = [hashtable]::Synchronized(@{})
    }

    It "lança exceção quando a configuração solicitada não pode ser carregada" {
        $missingConfig = Join-Path $TestDrive "missing.json"

        { Invoke-WPFImpex -type "import" -Config $missingConfig -ThrowOnError } | Should -Throw
    }
}

Describe "Invoke-WinUtilAutoRun" {
    BeforeAll {
        . (Join-Path $script:functionRoot "public\Invoke-WinUtilAutoRun.ps1")
    }

    BeforeEach {
        $global:sync = [hashtable]::Synchronized(@{})
        $sync.selectedTweaks = [System.Collections.Generic.List[string]]::new()
        $sync.selectedToggles = [System.Collections.Generic.List[string]]::new()
        $sync.selectedApps = [System.Collections.Generic.List[string]]::new()
        $sync.selectedFeatures = [System.Collections.Generic.List[string]]::new()
        $sync.selectedAppx = [System.Collections.Generic.List[string]]::new()
        $sync.LoggedErrors = [System.Collections.ArrayList]::Synchronized([System.Collections.ArrayList]::new())
        $sync.ActiveJob = $null

        Mock Write-WinUtilLog { }
        Mock Write-WinUtilTimingSummary { }
        Mock Write-WinUtilErrorRecord { }
    }

    It "não faz nada e avisa quando nada está selecionado" {
        $summary = Invoke-WinUtilAutoRun

        @($summary.Steps).Count | Should -Be 0
        Should -Invoke -CommandName Write-WinUtilLog -ParameterFilter { $Level -eq "WARN" -and $Message -like "*nada a fazer*" }
    }

    It "aplica interruptores, o que nada fora da janela fazia" {
        $sync.selectedToggles.Add("WPFToggleDarkMode")
        Mock Invoke-WPFToggleSelections { }

        $summary = Invoke-WinUtilAutoRun

        Should -Invoke -CommandName Invoke-WPFToggleSelections -Times 1 -Exactly
        @($summary.Steps | Where-Object { $_.Name -eq "Interruptores" }).Count | Should -Be 1
    }

    It "executa apenas as etapas que têm algo selecionado" {
        $sync.selectedApps.Add("WPFInstall7zip")
        Mock Invoke-WPFInstall { }
        Mock Invoke-WPFtweaksbutton { }

        $summary = Invoke-WinUtilAutoRun

        @($summary.Steps).Count | Should -Be 1
        $summary.Steps[0].Name | Should -Be "Aplicativos"
        Should -Invoke -CommandName Invoke-WPFtweaksbutton -Times 0 -Exactly
    }

    It "desiste de uma etapa que nunca termina em vez de travar para sempre" {
        $sync.selectedApps.Add("WPFInstall7zip")
        # um job que define a flag e nunca a limpa
        Mock Invoke-WPFInstall { $sync.ActiveJob = "Install" }

        $summary = Invoke-WinUtilAutoRun -StepTimeoutSeconds 1

        $summary.TimedOut | Should -Be 1
        # e a flag deve ser liberada, ou todas as etapas posteriores seriam recusadas
        $sync.ActiveJob | Should -BeNullOrEmpty
    }

    It "abandona as etapas restantes quando um worker com tempo esgotado não para" {
        $sync.selectedTweaks.Add("WPFTweaksAH")
        $sync.selectedApps.Add("WPFInstall7zip")
        # a primeira etapa atinge o tempo limite e seu worker ainda está em execução depois
        Mock Invoke-WPFtweaksbutton { $sync.ActiveJob = "Tweaks" }
        Mock Invoke-WPFInstall { }
        Mock Stop-WinUtilActiveWork { }
        Mock Test-WinUtilActiveWorkRunning { return $true }

        $summary = Invoke-WinUtilAutoRun -StepTimeoutSeconds 1 -StopTimeoutSeconds 1

        $summary.TimedOut | Should -Be 1
        # a etapa posterior não deve rodar junto com trabalho que ainda está alterando a máquina
        Should -Invoke -CommandName Invoke-WPFInstall -Times 0 -Exactly
        Should -Invoke -CommandName Stop-WinUtilActiveWork -Times 1 -Exactly
    }

    It "conta os erros de uma etapa contra a execução" {
        $sync.selectedApps.Add("WPFInstall7zip")
        Mock Invoke-WPFInstall { $null = $sync.LoggedErrors.Add("boom") }

        $summary = Invoke-WinUtilAutoRun

        $summary.Failed | Should -Be 1
        $summary.Errors | Should -Be 1
    }

    It "relata avisos produzidos por um job concluído" {
        $sync.selectedApps.Add("WPFInstall7zip")
        Mock Invoke-WPFInstall {
            $sync.LastJobResult = [pscustomobject]@{ Errors = 0; Warnings = 1 }
        }

        $summary = Invoke-WinUtilAutoRun

        $summary.Failed | Should -Be 0
        $summary.Warnings | Should -Be 1
        $summary.Steps[0].Warnings | Should -Be 1
    }

    It "continua após uma etapa lançar exceção em vez de abandonar a execução" {
        $sync.selectedTweaks.Add("WPFTweaksDiskCleanup")
        $sync.selectedApps.Add("WPFInstall7zip")
        Mock Invoke-WPFtweaksbutton { throw "tweaks blew up" }
        Mock Invoke-WPFInstall { }

        $summary = Invoke-WinUtilAutoRun

        Should -Invoke -CommandName Invoke-WPFInstall -Times 1 -Exactly
        @($summary.Steps).Count | Should -Be 2
    }
}

Describe "Write-WinUtilAutoRunSummary" {
    BeforeAll {
        . (Join-Path $script:functionRoot "public\Invoke-WinUtilAutoRun.ps1")
    }

    BeforeEach {
        $global:sync = @{ logPath = "C:\temp\winutil.log" }
        Mock Write-Host { }
    }

    It "retorna 0 quando todas as etapas estiveram limpas" {
        $summary = [pscustomobject]@{
            Steps = @([pscustomobject]@{ Name = "Tweaks"; Items = 1; Seconds = 1; Errors = 0; TimedOut = $false })
            Failed = 0; TimedOut = 0; Errors = 0
        }

        Write-WinUtilAutoRunSummary -Summary $summary | Should -Be 0
    }

    It "retorna 1 quando uma etapa falha ou atinge o tempo limite" {
        $failed = [pscustomobject]@{
            Steps = @([pscustomobject]@{ Name = "Tweaks"; Items = 1; Seconds = 1; Errors = 2; TimedOut = $false })
            Failed = 1; TimedOut = 0; Errors = 2
        }
        Write-WinUtilAutoRunSummary -Summary $failed | Should -Be 1

        $timedOut = [pscustomobject]@{
            Steps = @([pscustomobject]@{ Name = "Apps"; Items = 1; Seconds = 60; Errors = 0; TimedOut = $true })
            Failed = 0; TimedOut = 1; Errors = 0
        }
        Write-WinUtilAutoRunSummary -Summary $timedOut | Should -Be 1
    }

    It "retorna 2 quando nada foi selecionado, o que não é o mesmo que sucesso" {
        $summary = [pscustomobject]@{ Steps = @(); Failed = 0; TimedOut = 0; Errors = 0 }

        Write-WinUtilAutoRunSummary -Summary $summary | Should -Be 2
    }

    It "relata avisos sem transformar uma omissão esperada de pacote em falha" {
        $summary = [pscustomobject]@{
            Steps = @([pscustomobject]@{ Name = "Aplicativos"; Items = 1; Seconds = 1; Errors = 0; Warnings = 1; TimedOut = $false })
            Failed = 0; TimedOut = 0; Errors = 0; Warnings = 1
        }

        Write-WinUtilAutoRunSummary -Summary $summary | Should -Be 0
        Should -Invoke Write-Host -ParameterFilter { $Object -like "Concluído com avisos*" }
    }
}

Describe "Update-WinUtilSelections" {
    BeforeEach {
        $global:sync = [hashtable]::Synchronized(@{})
        foreach ($list in @("selectedApps","selectedTweaks","selectedToggles","selectedFeatures","selectedAppx")) {
            $sync.$list = [System.Collections.Generic.List[string]]::new()
        }
        # O classificador de seleção agora verifica cada chave no catálogo real antes de aceitá-la,
        # então a fixture precisa trazer as configurações que ele lê
        $sync.configs = @{
            applicationsHashtable = @{ "WPFInstall7zip" = @{} }
            appxHashtable         = @{ "WPFAppxBing" = @{} }
            tweaks                = [pscustomobject]@{ "WPFTweaksDiskCleanup" = @{}; "WPFToggleDarkMode" = @{} }
            feature               = [pscustomobject]@{ "WPFFeaturesdotnet" = @{} }
        }
        Mock Write-WinUtilLog { }
    }

    It "classifica cada prefixo em sua própria lista" {
        Update-WinUtilSelections -flatJson @("WPFInstall7zip","WPFTweaksDiskCleanup","WPFToggleDarkMode","WPFFeaturesdotnet","WPFAppxBing")

        $sync.selectedApps | Should -Contain "WPFInstall7zip"
        $sync.selectedTweaks | Should -Contain "WPFTweaksDiskCleanup"
        $sync.selectedToggles | Should -Contain "WPFToggleDarkMode"
        $sync.selectedFeatures | Should -Contain "WPFFeaturesdotnet"
        $sync.selectedAppx | Should -Contain "WPFAppxBing"
    }

    It "devolve uma entrada não reconhecida em vez de lançar exceção, do que depende a execução headless" {
        # O caminho headless passa SkipUnknown para que uma entrada aposentada se identifique e a execução
        # continue. Sem isso, a chamada é rigorosa, que é o que a janela deseja.
        $skipped = @(Update-WinUtilSelections -flatJson @("NotAWinUtilEntry") -SkipUnknown)

        $skipped | Should -Contain "NotAWinUtilEntry"
        { Update-WinUtilSelections -flatJson @("NotAWinUtilEntry") } | Should -Throw
    }

    It "não seleciona a mesma entrada duas vezes quando uma predefinição e uma configuração a listam" {
        Update-WinUtilSelections -flatJson @("WPFInstall7zip")
        Update-WinUtilSelections -flatJson @("WPFInstall7zip")

        @($sync.selectedApps).Count | Should -Be 1
    }
}
