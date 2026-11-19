function Get-WinUtilRecentLogs {
    <#
    .SYNOPSIS
        Concatena os logs de sessão do WinUtil dos últimos N dias em um único bloco de texto.

    .PARAMETER Days
        Quantos dias para trás incluir. O padrão é 7, igual ao que o fórum/servidor de suporte
        normalmente pede aos usuários.

    .PARAMETER LogDirectory
        Substitui o diretório de logs (normalmente $sync.winutildir\logs). Principalmente para testes.
    #>
    param(
        [int]$Days = 7,
        [string]$LogDirectory
    )

    if ([string]::IsNullOrWhiteSpace($LogDirectory)) {
        if ($null -eq $sync -or -not $sync.ContainsKey("winutildir") -or [string]::IsNullOrWhiteSpace($sync.winutildir)) {
            return ""
        }
        $LogDirectory = Join-Path $sync.winutildir "logs"
    }

    if (-not (Test-Path -LiteralPath $LogDirectory -ErrorAction Stop)) {
        return ""
    }

    $cutoff = (Get-Date).AddDays(-$Days)
    $logFiles = Get-ChildItem -LiteralPath $LogDirectory -Filter "winutil_*.log" -File -ErrorAction Stop |
        Where-Object { $_.LastWriteTime -ge $cutoff } |
        Sort-Object LastWriteTime

    $sections = foreach ($logFile in $logFiles) {
        "=== $($logFile.Name) ===`n$(Get-Content -LiteralPath $logFile.FullName -Raw -ErrorAction Stop)"
    }

    return ($sections -join "`n`n")
}
