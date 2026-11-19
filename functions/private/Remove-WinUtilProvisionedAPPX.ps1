function Remove-WinUtilProvisionedAPPX {
    <#

    .SYNOPSIS
        Remove todos os pacotes AppX provisionados que correspondem aos nomes fornecidos

    .PARAMETER PackageList
        Uma matriz de nomes dos pacotes APPX a remover

    .EXAMPLE
        Remove-WinUtilProvisionedAPPX -PackageList @("Microsoft.Microsoft3DViewer", "Microsoft.WindowsCalculator")

    #>
    param (
        [string[]]$PackageList
    )

    if ($null -eq $PackageList -or $PackageList.Count -eq 0) {
        return
    }

    Write-Host "`nRemovendo pacotes provisionados..."
    Write-WinUtilLog -Component "AppX" -Message "Removendo pacotes AppX provisionados: $($PackageList -join ', ')"

    # Cmdlets DISM como Get-AppxProvisionedPackage costumam falhar com "Class not registered" ou travar no PowerShell 7.
    # Recorremos ao Windows PowerShell 5.1 (powershell.exe) para remover os pacotes provisionados de forma confiável.
    $ps5Command = {
        $pkgs = $args
        $provisionedPackages = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
        $failures = [System.Collections.Generic.List[string]]::new()

        foreach ($Package in $pkgs) {
            $provs = $provisionedPackages |
                Where-Object DisplayName -Like "*$Package*"

            if ($null -ne $provs) {
                foreach ($prov in $provs) {
                    try {
                        Remove-AppxProvisionedPackage -Online -PackageName $prov.PackageName -ErrorAction Stop | Out-Null
                    }
                    catch {
                        $failures.Add("Falha ao remover o pacote AppX provisionado $($prov.PackageName): $($_.Exception.Message)")
                    }
                }
            }
        }

        if ($failures.Count -gt 0) {
            throw ($failures -join [Environment]::NewLine)
        }
    }

    $removalOutput = powershell.exe -NoProfile -NonInteractive -Command $ps5Command -args $PackageList 2>&1
    if ($LASTEXITCODE -ne 0 -or $null -ne $removalOutput) {
        $failureDetails = ($removalOutput | Out-String).Trim()
        $errorMessage = "A remoção do pacote AppX provisionado falhou: $failureDetails"
        Write-WinUtilLog -Level "ERROR" -Component "AppX" -Message $errorMessage
        $exception = [System.InvalidOperationException]::new($errorMessage)
        $exception.Data["WinUtilErrorReported"] = $true
        throw $exception
    }

    Write-WinUtilLog -Component "AppX" -Message "Remoção de pacote AppX provisionado concluída."
}
