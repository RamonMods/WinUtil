function Install-WinUtilWinget {
    <#

    .SYNOPSIS
        Instala o WinGet se ele ainda não estiver instalado.

    .DESCRIPTION
        instala o WinGet caso necessário
    #>
    param(
        [switch]$Force
    )

    # A ação de reparo precisa executar Repair-WinGetPackageManager mesmo quando o winget é detectado,
    # que é exatamente o caso de uma instalação quebrada
    if (-not $Force -and (Test-WinUtilPackageManager -winget) -eq "installed") {
        return
    }

    if ($Force) {
        Write-Host "Reparando a instalação do WinGet..." -ForegroundColor Yellow
    } else {
        Write-Host "O WinGet não está instalado. Instalando agora..." -ForegroundColor Red
    }

    Install-PackageProvider -Name NuGet -Force
    Install-Module -Name Microsoft.WinGet.Client -Force
    Repair-WinGetPackageManager -AllUsers
}
