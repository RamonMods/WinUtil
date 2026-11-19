function Get-WinUtilInstalledAPPX {
    <#

    .SYNOPSIS
        Obtém os nomes dos pacotes AppX instalados para todos os usuários

    #>

    # O carregamento automático do módulo AppX pode deixar o PowerShell 7 dependente de um proxy
    # de compatibilidade temporário do Windows PowerShell. Execute a consulta no Windows PowerShell 5.1
    # para que ela continue disponível depois que esses arquivos de proxy temporários forem removidos.
    $ps5Command = {
        Get-AppxPackage -AllUsers -ErrorAction Stop | Select-Object -ExpandProperty Name
    }

    $packageOutput = powershell.exe -NoProfile -NonInteractive -Command $ps5Command 2>&1
    if ($LASTEXITCODE -ne 0) {
        $failureDetails = ($packageOutput | Out-String).Trim()
        Write-WinUtilLog -Level "ERROR" -Component "AppX" -Message "Falha ao obter os pacotes AppX instalados: $failureDetails"
        return @()
    }

    return @($packageOutput)
}
