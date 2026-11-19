function Write-WinUtilLog {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet("INFO", "WARN", "ERROR", "DEBUG")]
        [string]$Level = "INFO",

        [string]$Component = "WinUtil",

        # Continuação de um erro já contabilizado, como um quadro da pilha
        [switch]$Detail,

        [switch]$FileOnly
    )

    # Os diagnósticos de desempenho da UI são úteis para desenvolvedores, mas são muito ruidosos para o
    # log de lançamento. Compile.ps1 marca os builds locais para que a saída DEBUG não vaze para os artefatos de CI.
    if ($Level -eq "DEBUG" -and ($null -eq $sync -or -not $sync.IsLocalCompile)) {
        return
    }

    if ($Level -eq "ERROR" -and -not $Detail -and $null -ne $sync.LoggedErrors) {
        $null = $sync.LoggedErrors.Add("[$Component] $Message")
    }

    # O escopo global é por runspace, então este contador só vê erros registrados pela runspace
    # que o possui: um worker de job lê o seu, e um ajuste na thread da UI lê o da thread da
    # UI
    if ($Level -eq "ERROR" -and -not $Detail) {
        $global:WinUtilJobErrorCount++
    }

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    $line = "[$timestamp] [$Level] [$Component] $Message"

    try {
        $writer = Get-WinUtilLogWriter
        if ($null -ne $writer) {
            [System.Threading.Monitor]::Enter($writer)
            try {
                $writer.WriteLine($line)
            } finally {
                [System.Threading.Monitor]::Exit($writer)
            }
        }
    } catch [System.IO.IOException] {
        Write-Verbose "Não foi possível gravar a entrada de log do WinUtil: $($_.Exception.Message)"
    } catch {
        Write-Warning "Não foi possível gravar a entrada de log do WinUtil: $($_.Exception.Message)"
    }

    if (-not $FileOnly) {
        Write-WinUtilHost $line
    }
}

# Abre o log da sessão uma vez para que todas as runspaces o compartilhem. Outras ainda podem lê-lo, por exemplo o relatório de ambiente.
function Get-WinUtilLogWriter {
    $state = $sync
    if ($null -eq $state) {
        if ([string]::IsNullOrWhiteSpace($env:LocalAppData)) {
            return $null
        }
        if ($null -eq $script:WinUtilLogState) {
            $script:WinUtilLogState = [hashtable]::Synchronized(@{
                winutildir = Join-Path $env:LocalAppData "winutil"
            })
        }
        $state = $script:WinUtilLogState
    }

    $writer = $state.LogWriter
    if ($null -ne $writer -and $state.LogWriterPath -eq $state.logPath) {
        return $writer
    }

    [System.Threading.Monitor]::Enter($state.SyncRoot)
    try {
        if ([string]::IsNullOrWhiteSpace($state.logPath)) {
            if ([string]::IsNullOrWhiteSpace($state.winutildir)) {
                return $null
            }
            $state.logPath = Join-Path (Join-Path $state.winutildir "logs") "winutil_$(Get-Date -Format "yyyy-MM-dd_HH-mm-ss").log"
        }

        if ($null -ne $state.LogWriter -and $state.LogWriterPath -eq $state.logPath) {
            return $state.LogWriter
        }

        if ($null -ne $state.LogWriter) {
            $state.LogWriter.Dispose()
            $state.LogWriter = $null
        }

        $logDirectory = Split-Path -Path $state.logPath -Parent
        if (-not (Test-Path -LiteralPath $logDirectory)) {
            New-Item -Path $logDirectory -ItemType Directory -Force | Out-Null
        }

        $stream = [System.IO.FileStream]::new(
            $state.logPath,
            [System.IO.FileMode]::Append,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::Read)
        $newWriter = [System.IO.StreamWriter]::new($stream, [System.Text.UTF8Encoding]::new($true))
        $newWriter.AutoFlush = $true

        $state.LogWriterPath = $state.logPath
        $state.LogWriter = $newWriter
        return $newWriter
    } finally {
        [System.Threading.Monitor]::Exit($state.SyncRoot)
    }
}

# Libera o arquivo de log quando o WinUtil sai, para que o terminal em que ele rodou não o mantenha bloqueado
function Close-WinUtilLog {
    $state = if ($null -ne $sync) { $sync } else { $script:WinUtilLogState }
    if ($null -eq $state -or $null -eq $state.LogWriter) {
        return
    }

    $writer = $state.LogWriter
    [System.Threading.Monitor]::Enter($writer)
    try {
        $state.LogWriter = $null
        $state.LogWriterPath = $null
        $writer.Dispose()
    } finally {
        [System.Threading.Monitor]::Exit($writer)
    }
}

# Saída apenas no console, como banners e progresso. Diferente de Write-Host, um job não a registra em log.
function Write-WinUtilHost {
    param(
        [string]$Object = "",
        [Nullable[System.ConsoleColor]]$ForegroundColor,
        [Nullable[System.ConsoleColor]]$BackgroundColor,
        [switch]$NoNewline
    )

    $rawUI = $Host.UI.RawUI
    if ($null -eq $rawUI -or ($null -eq $ForegroundColor -and $null -eq $BackgroundColor)) {
        if ($NoNewline) {
            $Host.UI.Write($Object)
        } else {
            $Host.UI.WriteLine($Object)
        }
        return
    }

    $foreground = if ($null -ne $ForegroundColor) { $ForegroundColor } else { $rawUI.ForegroundColor }
    $background = if ($null -ne $BackgroundColor) { $BackgroundColor } else { $rawUI.BackgroundColor }

    if ($NoNewline) {
        $Host.UI.Write($foreground, $background, $Object)
    } else {
        $Host.UI.WriteLine($foreground, $background, $Object)
    }
}

# Registra um aviso, erro ou registro de Write-Host de outra runspace e também o exibe, a menos que -Shown indique que ele já foi exibido
function Write-WinUtilStreamRecord {
    param(
        [Parameter(Mandatory)]
        $Record,

        [string]$Component = "WinUtil",

        [switch]$Shown
    )

    if ($Record -is [System.Management.Automation.WarningRecord]) {
        Write-WinUtilLog -Level "WARN" -Component $Component -Message $Record.Message -FileOnly:$Shown
    } elseif ($Record -is [System.Management.Automation.ErrorRecord]) {
        Write-WinUtilErrorRecord -ErrorRecord $Record -Component $Component -Context "Non-terminating error"
    } elseif ($Record -is [System.Management.Automation.InformationRecord]) {
        $message = $Record.MessageData

        if (-not $Shown -and $message -is [System.Management.Automation.HostInformationMessage]) {
            Write-WinUtilHost -Object $message.Message -ForegroundColor $message.ForegroundColor `
                -BackgroundColor $message.BackgroundColor -NoNewline:([bool]$message.NoNewLine)
        }

        $text = "$message".TrimEnd()
        if ($text) {
            Write-WinUtilLog -Component $Component -Message $text -FileOnly
        }
    }
}

# Registra e limpa os avisos, erros e a saída de Write-Host de uma runspace. Nunca lança exceção, pois é executado na thread principal.
function Receive-WinUtilStreamOutput {
    param(
        [Parameter(Mandatory)]
        $PowerShell,

        [string]$Component = "WinUtil"
    )

    try {
        foreach ($record in $PowerShell.Streams.Information.ReadAll()) {
            Write-WinUtilStreamRecord -Record $record -Component $Component -Shown
        }
        foreach ($record in $PowerShell.Streams.Warning.ReadAll()) {
            Write-WinUtilStreamRecord -Record $record -Component $Component -Shown
        }
        foreach ($record in $PowerShell.Streams.Error.ReadAll()) {
            Write-WinUtilStreamRecord -Record $record -Component $Component
        }
    } catch {
        Write-Warning "Não foi possível registrar a saída de $($Component): $($_.Exception.Message)"
    }
}
