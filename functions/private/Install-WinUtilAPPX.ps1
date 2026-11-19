function Install-WinUtilAPPX {
    <#

    .SYNOPSIS
        Registra um pacote AppX local ou o instala pela Microsoft Store

    .PARAMETER Name
        O nome do pacote AppX a instalar

    .PARAMETER StoreId
        O ID de produto opcional da Microsoft Store usado quando não há manifesto local disponível

    #>
    param (
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [string]$StoreId
    )

    Write-WinUtilLog -Component "AppX" -Message "Instalando pacote AppX: $Name"

    # Os cmdlets AppX e DISM são mais confiáveis no Windows PowerShell 5.1. Consulte os metadados
    # dos pacotes instalados e provisionados, pois qualquer um dos dois pode expor um manifesto local que pode ser registrado.
    $ps5Command = {
        $packageName = $args[0]
        $manifestPaths = [System.Collections.Generic.List[string]]::new()

        Get-AppxPackage -AllUsers -Name $packageName -ErrorAction SilentlyContinue |
            Sort-Object -Property Version -Descending |
            ForEach-Object {
                if (-not [string]::IsNullOrWhiteSpace($_.InstallLocation)) {
                    $manifestPaths.Add((Join-Path $_.InstallLocation "AppxManifest.xml"))
                }
            }

        Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
            Where-Object DisplayName -EQ $packageName |
            ForEach-Object {
                if (-not [string]::IsNullOrWhiteSpace($_.InstallLocation)) {
                    $manifestPaths.Add((Join-Path $_.InstallLocation "AppxManifest.xml"))
                }
            }

        $manifestPath = $manifestPaths |
            Select-Object -Unique |
            Where-Object { Test-Path -LiteralPath $_ } |
            Select-Object -First 1

        if ($null -ne $manifestPath) {
            Add-AppxPackage -Register $manifestPath -DisableDevelopmentMode -ErrorAction Stop
            Write-Output $manifestPath
        }
    }

    $manifestOutput = powershell.exe -NoProfile -NonInteractive -Command $ps5Command -args $Name 2>&1
    if ($LASTEXITCODE -eq 0 -and $null -ne $manifestOutput) {
        $manifestPath = ($manifestOutput | Select-Object -Last 1).ToString().Trim()
        if (-not [string]::IsNullOrWhiteSpace($manifestPath)) {
            Write-WinUtilLog -Component "AppX" -Message "Manifesto AppX local registrado para $Name`: $manifestPath"
            return [pscustomobject]@{
                Package = $Name
                Manager = "appx"
                Action = "Install"
                ExitCode = 0
                Outcome = "Succeeded"
                Detail = "manifesto local registrado"
            }
        }
    }

    if ($LASTEXITCODE -ne 0) {
        $failureDetails = ($manifestOutput | Out-String).Trim()
        Write-WinUtilLog -Level "WARN" -Component "AppX" -Message "Falha no registro do AppX local para $Name`: $failureDetails"
    }

    if ([string]::IsNullOrWhiteSpace($StoreId)) {
        # Um pacote sem manifesto local e sem ID da Store não pode ser instalado. Reporte como
        # resultado em vez de lançar exceção, para que os demais pacotes selecionados ainda sejam
        # executados e o resumo da tarefa cite este; Complete-WinUtilPackageRun falha a tarefa com o resultado Failed.
        $errorMessage = "Não foi possível instalar $Name porque não há manifesto local nem ID da Microsoft Store disponível."
        Write-WinUtilLog -Level "ERROR" -Component "AppX" -Message $errorMessage
        return [pscustomobject]@{
            Package  = $Name
            Manager  = "appx"
            Action   = "Install"
            ExitCode = 1
            Outcome  = "Failed"
            Detail   = $errorMessage
        }
    }

    Write-WinUtilLog -Component "AppX" -Message "Nenhum manifesto local utilizável encontrado para $Name. Instalando o produto $StoreId da Microsoft Store."
    $null = Install-WinUtilWinget
    Install-WinUtilProgramWinget -Action Install -Programs @("msstore:$StoreId")
}
