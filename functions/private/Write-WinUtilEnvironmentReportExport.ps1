function Copy-WinUtilEnvironmentReportExportFile {
    param(
        [Parameter(Mandatory)]
        [string]$SourcePath,

        [Parameter(Mandatory)]
        [string]$DestinationPath,

        [switch]$Overwrite
    )

    [System.IO.File]::Copy($SourcePath, $DestinationPath, $Overwrite)
}

function Remove-WinUtilEnvironmentReportExportFile {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    [System.IO.File]::Delete($Path)
}

function Write-WinUtilEnvironmentReportExport {
    <#
    .SYNOPSIS
        Publica um relatório de ambiente e seu arquivo de log opcional como uma única exportação.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$JsonPath,

        [Parameter(Mandatory)]
        [string]$Json,

        [Parameter(Mandatory)]
        [string]$LogsPath,

        [AllowNull()]
        [string]$Logs,

        [switch]$IncludeLogs
    )

    $suffix = [guid]::NewGuid().ToString("N")
    $jsonTempPath = "$JsonPath.$suffix.tmp"
    $logsTempPath = "$LogsPath.$suffix.tmp"
    $jsonBackupPath = "$JsonPath.$suffix.bak"
    $logsBackupPath = "$LogsPath.$suffix.bak"
    $hadJson = [System.IO.File]::Exists($JsonPath)
    $hadLogs = $IncludeLogs -and [System.IO.File]::Exists($LogsPath)
    $encoding = [System.Text.UTF8Encoding]::new($false)
    $retainJsonBackup = $false
    $retainLogsBackup = $false

    try {
        # Prepara ambas as saídas antes de substituir qualquer destino. Se a coleta ou uma
        # gravação temporária falhar, a exportação anterior permanece intacta.
        [System.IO.File]::WriteAllText($jsonTempPath, $Json, $encoding)
        if ($IncludeLogs) {
            [System.IO.File]::WriteAllText($logsTempPath, $Logs, $encoding)
        }

        if ($hadJson) {
            Copy-WinUtilEnvironmentReportExportFile -SourcePath $JsonPath -DestinationPath $jsonBackupPath
        }
        if ($hadLogs) {
            Copy-WinUtilEnvironmentReportExportFile -SourcePath $LogsPath -DestinationPath $logsBackupPath
        }

        try {
            Copy-WinUtilEnvironmentReportExportFile -SourcePath $jsonTempPath -DestinationPath $JsonPath -Overwrite
            if ($IncludeLogs) {
                Copy-WinUtilEnvironmentReportExportFile -SourcePath $logsTempPath -DestinationPath $LogsPath -Overwrite
            }
        } catch {
            $publishError = $_
            $rollbackErrors = [System.Collections.Generic.List[string]]::new()

            # A substituição de dois arquivos não é atômica no Windows. Restaura ambos os
            # destinos se a segunda publicação falhar, para um arquivo antigo não parecer pertencer ao novo JSON.
            try {
                if ($hadJson) {
                    Copy-WinUtilEnvironmentReportExportFile -SourcePath $jsonBackupPath -DestinationPath $JsonPath -Overwrite
                } elseif ([System.IO.File]::Exists($JsonPath)) {
                    Remove-WinUtilEnvironmentReportExportFile -Path $JsonPath
                }
            } catch {
                $retainJsonBackup = $hadJson
                $recoveryNote = if ($hadJson) { " Recovery copy retained at $jsonBackupPath." } else { "" }
                $rollbackErrors.Add("Falha ao restaurar o JSON: $($_.Exception.Message).$recoveryNote")
            }

            if ($IncludeLogs) {
                try {
                    if ($hadLogs) {
                        Copy-WinUtilEnvironmentReportExportFile -SourcePath $logsBackupPath -DestinationPath $LogsPath -Overwrite
                    } elseif ([System.IO.File]::Exists($LogsPath)) {
                        Remove-WinUtilEnvironmentReportExportFile -Path $LogsPath
                    }
                } catch {
                    $retainLogsBackup = $hadLogs
                    $recoveryNote = if ($hadLogs) { " Recovery copy retained at $logsBackupPath." } else { "" }
                    $rollbackErrors.Add("Falha ao restaurar os logs: $($_.Exception.Message).$recoveryNote")
                }
            }

            if ($rollbackErrors.Count -gt 0) {
                $message = "Falha ao publicar a exportação de ambiente: $($publishError.Exception.Message) A reversão também falhou: $($rollbackErrors -join ' ')"
                throw [System.IO.IOException]::new($message, $publishError.Exception)
            }

            throw $publishError
        }
    } finally {
        $cleanupTargets = @(
            [pscustomobject]@{ Path = $jsonTempPath; Retain = $false },
            [pscustomobject]@{ Path = $logsTempPath; Retain = $false },
            [pscustomobject]@{ Path = $jsonBackupPath; Retain = $retainJsonBackup },
            [pscustomobject]@{ Path = $logsBackupPath; Retain = $retainLogsBackup }
        )
        foreach ($cleanupTarget in $cleanupTargets) {
            if (-not $cleanupTarget.Retain -and [System.IO.File]::Exists($cleanupTarget.Path)) {
                try {
                    Remove-WinUtilEnvironmentReportExportFile -Path $cleanupTarget.Path
                } catch {
                    Write-Warning "Não foi possível remover o arquivo temporário de exportação de ambiente $($cleanupTarget.Path): $($_.Exception.Message)"
                }
            }
        }
    }
}
