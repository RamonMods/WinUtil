function Test-WinUtilPackageManager {
    <#
    .SYNOPSIS
        Verifica se o WinGet e/ou o Choco estão instalados.
    .PARAMETER winget
        Verifica se o WinGet está instalado.
    .PARAMETER choco
        Verifica se o Chocolatey está instalado.
    #>
    Param(
        [System.Management.Automation.SwitchParameter]$winget,
        [System.Management.Automation.SwitchParameter]$choco
    )

    # Trata a ausência do parâmetro - os chamadores dependem do valor retornado
    if (-not $winget -and -not $choco) { return "not-installed" }

    $cmds = @()
    if ($winget) { $cmds += "winget" }
    if ($choco) { $cmds += "choco" }

    foreach ($cmd in $cmds) {
        if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
            return "not-installed"
        }
    }
    return "installed"
}
