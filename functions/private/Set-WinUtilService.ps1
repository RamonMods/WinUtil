Function Set-WinUtilService {
    <#

    .SYNOPSIS
        Altera o tipo de inicialização do serviço informado

    .PARAMETER Name
        O nome do serviço a modificar

    .PARAMETER StartupType
        O tipo de inicialização a ser definido no serviço

    .EXAMPLE
        Set-WinUtilService -Name "HomeGroupListener" -StartupType "Manual"

    #>
    param (
        $Name,
        $StartupType
    )
    try {
        Write-Host "Definindo o serviço $Name como $StartupType"
        Write-WinUtilLog -Component "Service" -Message "Definindo o tipo de inicialização do serviço $Name como $StartupType"

        # Verifica se o serviço existe
        $service = Get-Service -Name $Name -ErrorAction Stop

        if (($service.PSObject.Properties.Name -contains "StartType") -and ([string]$service.StartType -eq [string]$StartupType) ) {
            Write-Host "O serviço $Name já está definido como $StartupType"
            Write-WinUtilLog -Component "Service" -Message "O tipo de inicialização do serviço $Name já é $StartupType; nenhuma alteração necessária."
            return
        }

        # O serviço existe, prossegue com a alteração de propriedades -- tratando a inicialização automática atrasada no PWSH 5
        if (($PSVersionTable.PSVersion.Major -lt 7) -and ($StartupType -eq "AutomaticDelayedStart")) {
            sc.exe config $Name start= delayed-auto
            if ($LASTEXITCODE -ne 0) {
                throw "sc.exe config falhou com o código de saída $LASTEXITCODE"
            }
        } else {
            $service | Set-Service -StartupType $StartupType -ErrorAction Stop
        }
        Write-WinUtilLog -Component "Service" -Message "Tipo de inicialização do serviço $Name definido como $StartupType"
    } catch {
        if ($_.FullyQualifiedErrorId -like "NoServiceFoundForGivenName,*") {
            Write-Warning "O serviço $Name não foi encontrado."
            Write-WinUtilLog -Level "WARN" -Component "Service" -Message "O serviço $Name não foi encontrado."
        } else {
            Write-Warning "Não foi possível definir $Name devido a uma exceção não tratada."
            Write-Warning $_.Exception.Message
            Write-WinUtilLog -Level "ERROR" -Component "Service" -Message "Não foi possível definir o serviço $Name como $StartupType`: $($_.Exception.Message)"
        }
    }

}
