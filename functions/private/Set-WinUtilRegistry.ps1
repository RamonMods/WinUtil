function Set-WinUtilRegistry {
    <#

    .SYNOPSIS
        Modifica o registro com base nos valores informados

    .PARAMETER Name
        O nome do valor a modificar

    .PARAMETER Path
        O caminho da chave

    .PARAMETER Type
        O tipo de valor a ser definido na chave

    .PARAMETER Value
        O valor a ser definido na chave

    .EXAMPLE
        Set-WinUtilRegistry -Name "PublishUserActivities" -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Type "DWord" -Value "0"

    #>
    param (
        $Name,
        $Path,
        $Type,
        $Value
    )

    try {
        if(!(Test-Path 'HKU:\')) {New-PSDrive -PSProvider Registry -Name HKU -Root HKEY_USERS | Out-Null}

        if ($Value -eq "<RemoveEntry>") {
            # Um valor que não existe já está no estado solicitado. Reportá-lo como
            # erro fazia falhar o desfazer de um ajuste que nunca foi aplicado, e a chave acabaria
            # sendo criada abaixo apenas para que nada fosse removido dela. Apenas uma chave ou valor
            # ausente conta como inexistente; uma falha de acesso ou do provedor ainda chega aos
            # tratadores abaixo.
            $valueExists = $true
            try {
                Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop | Out-Null
            } catch [System.Management.Automation.PSArgumentException] {
                # O provedor de registro usa PSArgumentException quando um valor nomeado está ausente
                $valueExists = $false
            } catch [System.Management.Automation.ItemNotFoundException] {
                $valueExists = $false
            }

            if (-not $valueExists) {
                Write-Host "$Path\$Name já está ausente"
                Write-WinUtilLog -Component "Registry" -Message "O valor de registro $Path\$Name já está ausente; nada a remover"
                return
            }
        }

        If (!(Test-Path $Path)) {
            Write-Host "$Path não foi encontrado. Criando..."
            Write-WinUtilLog -Component "Registry" -Message "Criando o caminho de registro: $Path"
            New-Item -Path $Path -Force -ErrorAction Stop | Out-Null
        }

        if ($Value -ne "<RemoveEntry>") {
            Write-Host "Definindo $Path\$Name como $Value"
            Write-WinUtilLog -Component "Registry" -Message "Definindo $Path\$Name ($Type) como $Value"
            Set-ItemProperty -Path $Path -Name $Name -Type $Type -Value $Value -Force -ErrorAction Stop | Out-Null
        }
        else{
            Write-Host "Remover $Path\$Name"
            Write-WinUtilLog -Component "Registry" -Message "Removendo $Path\$Name"
            Remove-ItemProperty -Path $Path -Name $Name -Force -ErrorAction Stop | Out-Null
        }
    } catch [System.Security.SecurityException] {
        Write-Warning "Não foi possível definir $Path\$Name como $Value devido a uma exceção de segurança."
        Write-WinUtilLog -Level "ERROR" -Component "Registry" -Message "Exceção de segurança ao alterar $Path\$Name para $Value`: $($psitem.Exception.Message)"
    } catch [System.Management.Automation.ItemNotFoundException] {
        Write-Warning $psitem.Exception.ErrorRecord
        Write-WinUtilLog -Level "ERROR" -Component "Registry" -Message "Item de registro não encontrado ao alterar $Path\$Name`: $($psitem.Exception.Message)"
    } catch [System.UnauthorizedAccessException] {
       Write-Warning $psitem.Exception.Message
       Write-WinUtilLog -Level "ERROR" -Component "Registry" -Message "Sem autorização ao alterar $Path\$Name`: $($psitem.Exception.Message)"
    } catch {
        Write-Warning "Não foi possível definir $Name devido a uma exceção não tratada."
        Write-Warning $psitem.Exception.StackTrace
        Write-WinUtilLog -Level "ERROR" -Component "Registry" -Message "Exceção não tratada ao alterar $Path\$Name`: $($psitem.Exception.Message)"
    }
}
