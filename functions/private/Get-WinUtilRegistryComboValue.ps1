function Get-WinUtilRegistryComboValue {
    <#
    .SYNOPSIS
        Lê um valor de registro para um estado de lista suspensa baseado no registro.

    .PARAMETER Setting
        A configuração de registro vinda da configuração da lista suspensa.
    #>
    param(
        [Parameter(Mandatory)]
        $Setting
    )

    try {
        $item = Get-ItemProperty -Path $Setting.Path -Name $Setting.Name -ErrorAction Stop
        $property = $item.PSObject.Properties[$Setting.Name]
        return [pscustomobject]@{ Exists = $null -ne $property; Value = $property.Value }
    } catch [System.Management.Automation.PSArgumentException] {
        # O provedor de registro usa PSArgumentException quando um valor nomeado está ausente.
        return [pscustomobject]@{ Exists = $false; Value = $null }
    } catch [System.Management.Automation.ItemNotFoundException] {
        return [pscustomobject]@{ Exists = $false; Value = $null }
    }
}
