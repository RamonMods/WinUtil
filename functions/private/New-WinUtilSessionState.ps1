function New-WinUtilSessionState {
    <#
        .SYNOPSIS
            Cria o InitialSessionState a partir do qual todo runspace do WinUtil é criado

        .DESCRIPTION
            O runspace da interface e o pool de workers partem do mesmo estado: a hashtable
            compartilhada $sync, as globais do script compilado e todas as funções do WinUtil. É isso
            que permite à interface montar uma aba e ao corpo de um job chamar qualquer auxiliar sem injetar
            definições manualmente. As funções próprias do PowerShell são ignoradas, pois o estado de sessão
            padrão já as contém.

            Em cache: um InitialSessionState é um modelo a partir do qual qualquer número de runspaces é criado,
            e construí-lo não é gratuito.
    #>

    if ($sync.SessionState) {
        return $sync.SessionState
    }

    $initialSessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()

    $variables = @(
        @{ Name = "sync"; Value = $sync },
        @{ Name = "PARAM_OFFLINE"; Value = $PARAM_OFFLINE },
        @{ Name = "inputXML"; Value = $inputXML },
        @{ Name = "WinUtilAutounattendXml"; Value = $WinUtilAutounattendXml }
    )

    foreach ($variable in $variables) {
        $initialSessionState.Variables.Add(
            (New-Object System.Management.Automation.Runspaces.SessionStateVariableEntry -ArgumentList $variable.Name, $variable.Value, $null)
        )
    }

    $builtInFunctions = [System.Collections.Generic.HashSet[string]]::new(
        [string[]]@($initialSessionState.Commands |
            Where-Object { $_ -is [System.Management.Automation.Runspaces.SessionStateFunctionEntry] } |
            ForEach-Object { $_.Name }),
        [StringComparer]::OrdinalIgnoreCase
    )

    foreach ($function in (Get-ChildItem function:\)) {
        if ($builtInFunctions.Contains($function.Name)) {
            continue
        }

        $initialSessionState.Commands.Add(
            (New-Object System.Management.Automation.Runspaces.SessionStateFunctionEntry -ArgumentList $function.Name, $function.Definition)
        )
    }

    $sync.SessionState = $initialSessionState
    return $initialSessionState
}
