function Remove-WinUtilAPPX {
    <#

    .SYNOPSIS
        Remove todos os pacotes APPX que correspondem ao nome fornecido

    .PARAMETER Name
        O nome do pacote APPX a remover

    .EXAMPLE
        Remove-WinUtilAPPX -Name "Microsoft.Microsoft3DViewer"

    #>
    param (
        $Name
    )

    Write-Host "Removendo $Name"
    Write-WinUtilLog -Component "AppX" -Message "Removendo padrão de pacote AppX: $Name"

    # Percorremos os pacotes explicitamente em vez de usar o pipeline porque a vinculação do pipeline do PowerShell 7
    # para Remove-AppxPackage falha silenciosamente, e Get-AppxPackage -AllUsers retorna objetos duplicados para cada perfil de usuário.
    $pkgs = Get-AppxPackage "*$Name*" -AllUsers | Sort-Object -Property PackageFullName -Unique
    if ($null -ne $pkgs) {
        foreach ($pkg in $pkgs) {
            try {
                Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop
            }
            catch {
                Write-WinUtilLog -Level "ERROR" -Component "AppX" -Message "Falha ao remover o pacote AppX $($pkg.PackageFullName): $($_.Exception.Message)"
            }
        }
    }

    Write-WinUtilLog -Component "AppX" -Message "Remoção de AppX concluída para o padrão de pacote: $Name"
}
