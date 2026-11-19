function Invoke-WinUtilTweaks {
    <#

    .SYNOPSIS
        Invoca a função associada a cada caixa de seleção fornecida

    .PARAMETER CheckBox
        A caixa de seleção a invocar

    .PARAMETER undo
        Indica se deve desfazer a operação contida na caixa de seleção

    .PARAMETER KeepServiceStartup
        Indica se deve substituir a inicialização de um serviço pela fornecida pelo WinUtil,
        ou manter a inicialização desse serviço, caso tenha sido alterada pelo usuário ou por outro programa em relação ao valor padrão.
    #>

    param(
        $CheckBox,
        $undo = $false,
        $KeepServiceStartup = $true
    )

    $action = if ($undo) { "desfeito" } else { "aplicado" }
    Write-WinUtilLog -Component "Tweaks" -Message "Ajuste $action`: $CheckBox"
    # A próxima leitura de status deve consultar o registro, e não um valor armazenado em cache antes desta alteração
    if ($sync.ToggleStatusCache) {
        $sync.ToggleStatusCache.Remove($CheckBox)
    }
    # O contador vive neste runspace, portanto um erro registrado por um job concorrente em seu próprio
    # runspace não pode ser atribuído a um interruptor alternado na thread da interface
    $errorsBefore = [int]$global:WinUtilJobErrorCount

    if ($undo) {
        $Values = @{
            Registry = "OriginalValue"
            Service = "OriginalType"
            ScriptType = "UndoScript"
        }

    } else {
        $Values = @{
            Registry = "Value"
            Service = "StartupType"
            OriginalService = "OriginalType"
            ScriptType = "InvokeScript"
        }
    }
    if ($sync.configs.tweaks.$CheckBox.service) {
        foreach ($item in $sync.configs.tweaks.$CheckBox.service) {
            $changeservice = $true

            # KeepServiceStartup protege um serviço que o usuário (ou outra ferramenta) alterou para longe do
            # valor esperado por este ajuste. Desfazer usa a mesma regra invertida: restaura
            # OriginalType somente quando o serviço ainda está no StartupType aplicado por este ajuste.
            # Isso compara o estado atual, não o histórico: um serviço já no StartupType
            # antes da aplicação é indistinguível de um alterado por este ajuste.
            $expectedType = if ($undo) { $item.StartupType } else { $item.$($values.OriginalService) }
            if ($KeepServiceStartup) {
                $serviceName = $item.Name
                try {
                    # Verifica se o serviço existe
                    $service = Get-Service -Name $serviceName -ErrorAction Stop
                    if(!($service.StartType.ToString() -eq $expectedType)) {
                        $changeservice = $false
                        # Informe isso, ou o log parecerá que o ajuste alterou um serviço que não foi tocado
                        $skipMessage = "O tipo de inicialização do serviço $serviceName é $($service.StartType), e não $expectedType como este ajuste espera; deixando-o inalterado."
                        Write-Warning $skipMessage
                        Write-WinUtilLog -Level "WARN" -Component "Service" -Message $skipMessage
                    }
                } catch {
                    if ($_.FullyQualifiedErrorId -like "NoServiceFoundForGivenName,*") {
                        $changeservice = $false
                        Write-Warning "Serviço $serviceName não encontrado."
                        Write-WinUtilLog -Level "WARN" -Component "Service" -Message "Serviço $serviceName não encontrado."
                    } else {
                        throw
                    }
                }
            }

            if ($changeservice) {
                Set-WinUtilService -Name $item.Name -StartupType $item.$($values.Service)
            }
        }
    }
    if ($sync.configs.tweaks.$CheckBox.registry) {
        foreach ($reg in $sync.configs.tweaks.$CheckBox.registry) {
            if ($reg.Values) { continue }
            Set-WinUtilRegistry -Name $reg.Name -Path $reg.Path -Type $reg.Type -Value $reg.$($values.registry)
        }
    }
    if ($sync.configs.tweaks.$CheckBox.$($values.ScriptType)) {
        foreach ($scr in $sync.configs.tweaks.$CheckBox.$($values.ScriptType)) {
            $Scriptblock = [scriptblock]::Create($scr)
            Invoke-WinUtilScript -ScriptBlock $scriptblock -Name $CheckBox
        }
    }

    if (!$undo -and $sync.configs.tweaks.$CheckBox.appx) {
        foreach ($pkg in $sync.configs.tweaks.$CheckBox.appx) {
            Remove-WinUtilAPPX -Name $pkg
        }
        Remove-WinUtilProvisionedAPPX -PackageList $sync.configs.tweaks.$CheckBox.appx
    }
    $errorCount = [int]$global:WinUtilJobErrorCount - $errorsBefore
    if ($errorCount -gt 0) {
        Write-WinUtilLog -Level "WARN" -Component "Tweaks" -Message "Ajuste $action com $errorCount erro(s): $CheckBox"
    } else {
        Write-WinUtilLog -Component "Tweaks" -Message "Ajuste $action concluído: $CheckBox"
    }
}
