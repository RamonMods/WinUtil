function Get-WinUtilEntryToolTip {
    <#
        .SYNOPSIS
            Monta o texto da dica de uma entrada de app/ajuste/recurso: sua descrição mais sua chave JSON de predefinição

        .PARAMETER Description
            A descrição da entrada vinda do JSON de configuração. Pode ser nula ou vazia.

        .PARAMETER Key
            A chave JSON da entrada, como usada nos arquivos de predefinição (ex.: WPFInstallbrave, WPFTweaksTele).
    #>
    param(
        [Parameter(Mandatory = $false)]
        [string]$Description,

        [Parameter(Mandatory = $true)]
        [string]$Key
    )

    if ([string]::IsNullOrWhiteSpace($Description)) {
        return "Preset key: $Key"
    }

    return "$Description`n`nPreset key: $Key"
}
