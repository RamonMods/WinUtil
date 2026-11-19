function Get-WinUtilTweakDisplayName {
    <#
        .SYNOPSIS
            Retorna o rótulo voltado ao usuário para uma chave de ajuste

        .DESCRIPTION
            O texto de status deve ser lido como a caixa de seleção ("Activity
            History - Disable"), não como a chave de predefinição ("WPFTweaksActivity"). Recai
            na própria chave quando as configurações não estão disponíveis (execuções sem interface,
            testes) ou quando a entrada não tem rótulo, para que os chamadores não precisem de
            verificações de existência. Consulta pura de dados, segura para chamar de um worker de job.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Key
    )

    $entry = $null
    if ($null -ne $sync -and $null -ne $sync.configs -and $null -ne $sync.configs.tweaks) {
        $entry = $sync.configs.tweaks.$Key
    }

    if ($null -ne $entry -and -not [string]::IsNullOrWhiteSpace($entry.Content)) {
        return $entry.Content
    }

    return $Key
}
