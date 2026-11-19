function Get-WinUtilRegistryComboState {
    <#
    .SYNOPSIS
        Encontra o estado de lista suspensa configurado que corresponde aos valores atuais do registro.

    .PARAMETER Registry
        Configurações de registro contendo um mapeamento de valor para cada estado suportado.

    .OUTPUTS
        O nome do estado correspondente.
    #>
    param(
        [Parameter(Mandatory)]
        $Registry
    )

    foreach ($state in $Registry[0].Values.PSObject.Properties) {
        $stateMatches = $true
        foreach ($setting in @($Registry)) {
            $currentValue = Get-WinUtilRegistryComboValue -Setting $setting
            $actualValue = if ($currentValue.Exists -and $null -ne $currentValue.Value) { $currentValue.Value } else { $setting.DefaultValue }
            $configuredValue = $setting.Values.PSObject.Properties[$state.Name].Value
            # A remoção representa o padrão efetivo do Windows ao comparar o estado atual.
            $expectedValue = if ($configuredValue -eq "<RemoveEntry>") { $setting.DefaultValue } else { $configuredValue }
            if ([string]$actualValue -ne [string]$expectedValue) {
                $stateMatches = $false
                break
            }
        }
        if ($stateMatches) {
            return $state.Name
        }
    }

    throw "Os valores do registro não correspondem a nenhum estado suportado."
}
