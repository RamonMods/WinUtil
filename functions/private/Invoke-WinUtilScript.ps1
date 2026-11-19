function Invoke-WinUtilScript {
    <#

    .SYNOPSIS
        Invoca o bloco de script fornecido. Destinado a coisas que não podem ser tratadas pelas outras funções.

    .PARAMETER Name
        O nome do bloco de script que está sendo invocado

    .PARAMETER scriptblock
        O bloco de script a ser invocado

    .EXAMPLE
        $Scriptblock = [scriptblock]::Create({"Write-output 'Hello World'"})
        Invoke-WinUtilScript -ScriptBlock $scriptblock -Name "Hello World"

    #>
    param (
        $Name,
        [scriptblock]$scriptblock
    )

    try {
        Write-Host "Executando script para $Name"
        Write-WinUtilLog -Component "Script" -Message "Executando script para $Name"
        Invoke-Command $scriptblock -ErrorAction Stop
        Write-WinUtilLog -Component "Script" -Message "Script concluído para $Name"
    } catch [System.Management.Automation.CommandNotFoundException] {
        Write-Warning "O comando especificado não foi encontrado."
        Write-Warning $PSItem.Exception.message
        Write-WinUtilLog -Level "ERROR" -Component "Script" -Message "Comando não encontrado ao executar o script para $Name`: $($PSItem.Exception.Message)"
    } catch [System.Management.Automation.RuntimeException] {
        Write-Warning "Ocorreu uma exceção de tempo de execução."
        Write-Warning $PSItem.Exception.message
        Write-WinUtilLog -Level "ERROR" -Component "Script" -Message "Exceção de tempo de execução ao executar o script para $Name`: $($PSItem.Exception.Message)"
    } catch [System.Security.SecurityException] {
        Write-Warning "Ocorreu uma exceção de segurança."
        Write-Warning $PSItem.Exception.message
        Write-WinUtilLog -Level "ERROR" -Component "Script" -Message "Exceção de segurança ao executar o script para $Name`: $($PSItem.Exception.Message)"
    } catch [System.UnauthorizedAccessException] {
        Write-Warning "Acesso negado. Você não tem permissão para executar esta operação."
        Write-Warning $PSItem.Exception.message
        Write-WinUtilLog -Level "ERROR" -Component "Script" -Message "Acesso negado ao executar o script para $Name`: $($PSItem.Exception.Message)"
    } catch {
        # Bloco catch genérico para tratar qualquer outro tipo de exceção
        Write-Warning "Não foi possível executar o script para $Name devido a uma exceção não tratada."
        Write-Warning $psitem.Exception.StackTrace
        Write-WinUtilLog -Level "ERROR" -Component "Script" -Message "Exceção não tratada ao executar o script para $Name`: $($psitem.Exception.Message)"
    }

}
