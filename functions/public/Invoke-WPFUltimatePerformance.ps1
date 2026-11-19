function Invoke-WPFUltimatePerformance ([switch]$Enable) {
    <#

    .SYNOPSIS
        Adiciona ou remove o plano de energia Ultimate Performance

    #>

    if ($Enable) {
        Step-WinUtilJob -Status "Adicionando o plano de energia Ultimate Performance" -State "Indeterminate"
        Write-WinUtilLog -Component "Power" -Message "Duplicando e ativando o plano de energia Ultimate Performance."

        $duplicated = powercfg /duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61
        if ($LASTEXITCODE -ne 0) {
            throw "O powercfg não pôde duplicar o esquema Ultimate Performance (código de saída $LASTEXITCODE)."
        }

        $guid = ($duplicated | Select-String -Pattern '[A-Fa-f0-9-]{36}').Matches.Value
        if (-not $guid) {
            throw "O powercfg não reportou um GUID de esquema para ativar."
        }

        powercfg /setactive $guid
        if ($LASTEXITCODE -ne 0) {
            throw "O powercfg não pôde ativar o esquema Ultimate Performance (código de saída $LASTEXITCODE)."
        }

        Write-WinUtilLog -Component "Power" -Message "Plano de energia Ultimate Performance instalado e ativado."
    } else {
        Step-WinUtilJob -Status "Restaurando os planos de energia padrão" -State "Indeterminate"
        Write-WinUtilLog -Component "Power" -Message "Restaurando os esquemas de energia padrão."

        powercfg /restoredefaultschemes
        if ($LASTEXITCODE -ne 0) {
            throw "O powercfg não pôde restaurar os esquemas de energia padrão (código de saída $LASTEXITCODE)."
        }

        Write-WinUtilLog -Component "Power" -Message "Os planos de energia foram redefinidos para os padrões."
    }
}
