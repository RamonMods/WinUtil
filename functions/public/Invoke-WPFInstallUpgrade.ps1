function Invoke-WPFInstallUpgrade {
    <#

    .SYNOPSIS
        Atualiza todos os pacotes que têm uma atualização disponível

    .DESCRIPTION
        Executa no worker como qualquer outro trabalho de pacote, portanto a barra de progresso, o item da barra de tarefas
        e o log o reportam da mesma forma que uma instalação.

    #>

    param([string]$ManagerPreference = $sync.preferences.packagemanager)

    # O trabalho enfileirado recebe a preferência selecionada quando o usuário solicitou a atualização.
    if ($ManagerPreference -eq "Choco") {
        Step-WinUtilJob -Status "Preparando o Chocolatey" -State "Indeterminate"
        Install-WinUtilChoco

        Write-WinUtilLog -Component "Install" -Message "Atualizando todos os pacotes do Chocolatey."
        Step-WinUtilJob -Status "Atualizando todos os pacotes do Chocolatey" -State "Indeterminate"

        # "all" é o nome usado pelo próprio choco para todos os pacotes instalados, portanto isso continua sendo uma única chamada
        $result = Measure-WinUtilStep -Scope "Install" -Name "choco upgrade all" -ScriptBlock {
            Install-WinUtilProgramChoco -Action Upgrade -Programs @("all")
        }
        Complete-WinUtilPackageRun -Action "Upgrade" -Results @($result)
        return
    }

    Step-WinUtilJob -Status "Preparando o WinGet" -State "Indeterminate"
    Install-WinUtilWinget

    Write-WinUtilLog -Component "Install" -Message "Atualizando todos os pacotes do WinGet."
    Step-WinUtilJob -Status "Atualizando todos os pacotes do WinGet" -State "Indeterminate"

    # Deixe o WinGet resolver cada pacote em relação à sua origem registrada. Analisar a tabela localizada
    # e truncada por largura faz perder identificadores e informações de origem.
    $result = Measure-WinUtilStep -Scope "Install" -Name "winget upgrade --all" -ScriptBlock {
        Install-WinUtilProgramWinget -Action Upgrade -Programs @("all")
    }
    Complete-WinUtilPackageRun -Action "Upgrade" -Results @($result)
}
