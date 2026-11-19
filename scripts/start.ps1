<#
.NOTES
    Author         : Ramon @RamonMods
    Runspace Author: @DeveloperDurp
    GitHub         : https://github.com/RamonMods
    Version        : #{replaceme}
#>

param (
    [string]$Config,
    [ValidateSet("Standard", "Minimal", "Advanced", "")]
    [string]$Preset,
    [switch]$Offline
)

function Test-WinUtilOwnsFileProcess {
    <#
        .SYNOPSIS
            Indica se o processo atual foi iniciado com este script como seu arquivo de destino
    #>
    param(
        [string]$ScriptPath = $PSCommandPath,
        [string[]]$CommandLineArgs = [Environment]::GetCommandLineArgs()
    )

    if ([string]::IsNullOrWhiteSpace($ScriptPath)) { return $false }

    $hostOptionKinds = [ordered]@{
        Command           = "Command"
        EncodedCommand    = "Command"
        CommandWithArgs   = "Command"
        File              = "File"
        ConfigurationFile = "Value"
        ConfigurationName = "Value"
        CustomPipeName    = "Value"
        ExecutionPolicy   = "Value"
        InputFormat       = "Value"
        Interactive       = "Switch"
        Login             = "Switch"
        MTA               = "Switch"
        NoLogo            = "Switch"
        NonInteractive    = "Switch"
        NoProfile         = "Switch"
        NoProfileLoadTime = "Switch"
        OutputFormat      = "Value"
        PSConsoleFile     = "Value"
        SettingsFile      = "Value"
        SSHServerMode     = "Switch"
        STA               = "Switch"
        Version           = "Value"
        WindowStyle       = "Value"
        WorkingDirectory  = "Value"
        NoExit            = "NoExit"
    }
    $hostOptionAliases = @{
        c = "Command"; cwa = "Command"; e = "Command"; ec = "Command"; f = "File"
        noe = "NoExit"
        config = "Value"; ConfigName = "Value"; CustomPipe = "Value"; ep = "Value"; ex = "Value"
        i = "Switch"; Input = "Value"; In = "Value"; if = "Value"
        Output = "Value"; Out = "Value"; of = "Value"
        Settings = "Value"; Window = "Value"; w = "Value"; Working = "Value"; wd = "Value"
    }

    function Get-WinUtilHostOptionKind {
        param([string]$Argument)

        if ([string]::IsNullOrWhiteSpace($Argument) -or -not $Argument.StartsWith("-")) {
            return $null
        }

        $optionName = $Argument.TrimStart("-")
        if ($hostOptionAliases.ContainsKey($optionName)) {
            return $hostOptionAliases[$optionName]
        }

        # O pwsh aceita qualquer prefixo não ambíguo de uma opção do host, como -WorkingD.
        $matchingOptions = @($hostOptionKinds.Keys | Where-Object {
            $_.StartsWith($optionName, [StringComparison]::OrdinalIgnoreCase)
        })
        $matchingKinds = @($matchingOptions | ForEach-Object { $hostOptionKinds[$_] } | Select-Object -Unique)
        if ($matchingKinds.Count -eq 1) {
            return $matchingKinds[0]
        }

        return $null
    }

    :hostArguments for ($index = 1; $index -lt $CommandLineArgs.Count; $index++) {
        $optionKind = Get-WinUtilHostOptionKind -Argument $CommandLineArgs[$index]
        switch ($optionKind) {
            "Command" { return $false }
            "NoExit" { return $false }
            "Switch" { continue hostArguments }
            "File" {
                if ($index + 1 -ge $CommandLineArgs.Count) { return $false }
                $fileTarget = $CommandLineArgs[$index + 1]
                if ([string]::IsNullOrWhiteSpace($fileTarget) -or $fileTarget -eq "-") {
                    return $false
                }

                return [string]::Equals(
                    [IO.Path]::GetFullPath($fileTarget),
                    [IO.Path]::GetFullPath($ScriptPath),
                    [StringComparison]::OrdinalIgnoreCase
                )
            }
            "Value" {
                $index++
                continue hostArguments
            }
        }

        if ($CommandLineArgs[$index].StartsWith("-")) {
            continue
        }

        return [string]::Equals(
            [IO.Path]::GetFullPath($CommandLineArgs[$index]),
            [IO.Path]::GetFullPath($ScriptPath),
            [StringComparison]::OrdinalIgnoreCase
        )
    }

    return $false
}

# Um script headless iniciado com powershell.exe/pwsh.exe -File é dono do próprio processo e precisa
# definir o código de saída desse processo. Um script invocado ou em memória deve retornar sem fechar quem o chamou.
$script:WinUtilIsFileProcess = Test-WinUtilOwnsFileProcess

$PARAM_OFFLINE = $false
if ($Offline) {
    $PARAM_OFFLINE = $true
}

if ($ExecutionContext.SessionState.LanguageMode -ne 'FullLanguage') {
    Write-Host "O WinUtil não consegue ser executado no seu sistema. A execução do PowerShell está restrita por políticas de segurança." -ForegroundColor Red
    $global:LASTEXITCODE = 1
    if ($env:WINUTIL_HEADLESS_CHILD -eq "1" -or $script:WinUtilIsFileProcess) { exit 1 }
    return 1
}

function New-WinUtilElevationCommand {
    <#
        .SYNOPSIS
            Codifica o destino de relançamento e os parâmetros vinculados como dados para um processo filho elevado
    #>
    param(
        [string]$ScriptPath,
        [hashtable]$Parameters = @{},
        [switch]$Headless
    )

    $launchData = @{
        ScriptPath = $ScriptPath
        Parameters = $Parameters
        Headless = [bool]$Headless
    }
    $serializedLaunch = [System.Management.Automation.PSSerializer]::Serialize($launchData)
    $launchPayload = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($serializedLaunch))

    # Apenas base64 é embutido no texto executável. Valores controlados pelo usuário são desserializados e
    # repassados como dados de parâmetro no processo filho, então aspas em Config não podem virar código PowerShell.
    $bootstrap = @"
`$launchXml = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$launchPayload'))
`$launch = [System.Management.Automation.PSSerializer]::Deserialize(`$launchXml)
`$invokeParameters = `$launch.Parameters
if (`$launch.Headless) { `$env:WINUTIL_HEADLESS_CHILD = '1' }
if (`$launch.ScriptPath) {
    & `$launch.ScriptPath @invokeParameters
} else {
    `$remoteScript = [ScriptBlock]::Create((Invoke-RestMethod 'https://github.com/RamonMods/WinUtil/releases/latest/download/winutil.ps1'))
    & `$remoteScript @invokeParameters
}
"@

    return [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($bootstrap))
}

if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Output "O WinUtil precisa ser executado como Administrador. Tentando reiniciar."
    $elevationParameters = @{}
    foreach ($parameter in $PSBoundParameters.GetEnumerator()) {
        $elevationParameters[$parameter.Key] = if ($parameter.Value -is [switch]) {
            [bool]$parameter.Value
        } else {
            $parameter.Value
        }
    }

    $powershellCmd = if (Get-Command pwsh -ErrorAction SilentlyContinue) { "pwsh" } else { "powershell" }

    # Um chamador headless está esperando um resultado deste processo, então a execução elevada precisa
    # ser aguardada e ter seu código devolvido. Uma aba de terminal é dispensada pelo mesmo motivo: o
    # código de saída do wt.exe é dele próprio, não o da execução.
    if ($Config -or $Preset) {
        # Um pedido do UAC recusado gera exceção, o que deixaria $elevated nulo e sairia com 0: o chamador
        # que espera este processo interpretaria isso como uma execução bem-sucedida
        try {
            $elevationCommand = New-WinUtilElevationCommand -ScriptPath $PSCommandPath -Parameters $elevationParameters -Headless
            $elevated = Start-Process $powershellCmd -ArgumentList @("-ExecutionPolicy", "Bypass", "-NoProfile", "-EncodedCommand", $elevationCommand) -Verb RunAs -Wait -PassThru -ErrorAction Stop
        } catch {
            Write-Host "A elevação foi recusada ou falhou: $($_.Exception.Message)" -ForegroundColor Red
            $global:LASTEXITCODE = 1
            if ($script:WinUtilIsFileProcess) { exit 1 }
            return 1
        }
        $global:LASTEXITCODE = $elevated.ExitCode
        if ($script:WinUtilIsFileProcess) { exit $elevated.ExitCode }
        return $elevated.ExitCode
    }

    $processCmd = if (Get-Command wt.exe -ErrorAction SilentlyContinue) { "wt.exe" } else { "$powershellCmd" }
    $elevationCommand = New-WinUtilElevationCommand -ScriptPath $PSCommandPath -Parameters $elevationParameters

    if ($processCmd -eq "wt.exe") {
        Start-Process $processCmd -ArgumentList "$powershellCmd -ExecutionPolicy Bypass -NoProfile -EncodedCommand $elevationCommand" -Verb RunAs
    } else {
        Start-Process $processCmd -ArgumentList @("-ExecutionPolicy", "Bypass", "-NoProfile", "-EncodedCommand", $elevationCommand) -Verb RunAs
    }

    break
}

# Variável para sincronizar entre runspaces
$sync = [Hashtable]::Synchronized(@{})
$sync.version = "#{replaceme}"
$sync.IsLocalCompile = "#{islocalcompile}" -eq "true"
$sync.configs = @{}
$sync.Buttons = [System.Collections.Generic.List[PSObject]]::new()
$sync.preferences = @{}
# Nome do job em execução no momento, ou $null quando ocioso. Pertence a Start-WinUtilJob.
$sync.ActiveJob = $null
# Ações do usuário aguardando a vaga, a mais antiga primeiro. Alterado apenas sob $sync.SyncRoot.
$sync.JobQueue = [System.Collections.Generic.List[object]]::new()
# True desde a liberação de um job até o job enfileirado seguinte assumir a vaga, para que uma nova ação
# não pegue a vaga na frente da fila.
$sync.JobHandoff = $false
# Uma pergunta modal de fechamento não deve iniciar outro job enfileirado por trás do seu prompt.
$sync.JobClosePromptOpen = $false
# Serializa a inicialização do pool de workers com a reciclagem e o encerramento.
$sync.RunspacePoolLock = [object]::new()
# Serializa os renderizadores de sobreposição da barra de tarefas, o especulativo e o da thread de UI.
$sync.AssetRenderLock = [object]::new()
$sync.RenderedAssetCache = [Hashtable]::Synchronized(@{})
# Cada etapa registrada por Measure-WinUtilStep, de qualquer thread
$sync.StepTimings = [System.Collections.ArrayList]::Synchronized([System.Collections.ArrayList]::new())
# Todo erro registrado, para que um job consiga relatar que algo deu errado mesmo sem ter lançado exceção
$sync.LoggedErrors = [System.Collections.ArrayList]::Synchronized([System.Collections.ArrayList]::new())
$sync.StartedAt = Get-Date
$sync.selectedAppx = [System.Collections.Generic.List[string]]::new()
$sync.selectedApps = [System.Collections.Generic.List[string]]::new()
$sync.selectedTweaks = [System.Collections.Generic.List[string]]::new()
$sync.selectedToggles = [System.Collections.Generic.List[string]]::new()
$sync.selectedFeatures = [System.Collections.Generic.List[string]]::new()
$sync.currentTab = "Install"

$dateTime = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$winutildir = "$env:LocalAppData\winutil"
$sync.winutildir = $winutildir

# Escrito por Write-WinUtilLog. Não é um transcript, já que esse só registra este runspace e perde
# tudo que vem da thread de UI e dos jobs.
$sync.logPath = "$winutildir\logs\winutil_$dateTime.log"

$Host.UI.RawUI.WindowTitle = "WinUtil"
Clear-Host
