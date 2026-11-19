function Write-WinUtilErrorRecord {
    <#
        .SYNOPSIS
            Registra uma falha com contexto suficiente para agir sobre ela

        .DESCRIPTION
            Um simples "You cannot call a method on a null-valued expression." não diz nada sobre
            sua origem. Isto registra a mensagem junto com o tipo de exceção, o comando e a linha
            que a gerou, e a pilha de script, sob um nome de componente.

        .PARAMETER ErrorRecord
            O erro a relatar, normalmente $_ de um bloco catch.

        .PARAMETER Component
            Qual parte do WinUtil estava em execução, por exemplo Instalar ou UI.

        .PARAMETER Context
            O que estava sendo tentado, por exemplo o nome do botão ou o pacote.
    #>
    param(
        [Parameter(Mandatory)]
        $ErrorRecord,

        [string]$Component = "WinUtil",

        [string]$Context,

        # A falha subjacente já foi registrada e contabilizada; mantém o contexto e a pilha desta
        # chamada como detalhe de diagnóstico sem adicionar um segundo erro principal.
        [switch]$DetailOnly
    )

    $headline = if ($Context) { "$Context : $($ErrorRecord.Exception.Message)" } else { $ErrorRecord.Exception.Message }
    Write-WinUtilLog -Level "ERROR" -Component $Component -Message $headline -Detail:$DetailOnly

    $invocation = $ErrorRecord.InvocationInfo
    if ($invocation) {
        $where = "$($invocation.ScriptName):$($invocation.ScriptLineNumber)"
        if ([string]::IsNullOrWhiteSpace($invocation.ScriptName)) {
            $where = "linha $($invocation.ScriptLineNumber)"
        }
        Write-WinUtilLog -Level "ERROR" -Detail -Component $Component -Message "  em $where em $($invocation.MyCommand): $($invocation.Line.Trim())"
    }

    Write-WinUtilLog -Level "ERROR" -Detail -Component $Component -Message "  tipo $($ErrorRecord.Exception.GetType().FullName), categoria $($ErrorRecord.CategoryInfo.Category)"

    if ($ErrorRecord.ScriptStackTrace) {
        foreach ($frame in ($ErrorRecord.ScriptStackTrace -split "`r?`n")) {
            if (-not [string]::IsNullOrWhiteSpace($frame)) {
                Write-WinUtilLog -Level "ERROR" -Detail -Component $Component -Message "  $($frame.Trim())"
            }
        }
    }

    if (-not $DetailOnly) {
        Write-WinUtilHost "$Component : $headline" -ForegroundColor Red
    }
}
