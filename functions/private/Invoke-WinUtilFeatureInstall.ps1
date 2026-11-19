function Invoke-WinUtilFeatureInstall ($CheckBox) {
    Write-WinUtilLog -Component "Feature" -Message "Aplicando ação de recurso: $CheckBox"

    $featureFailed = $false
    if ($sync.configs.feature.$CheckBox.feature) {
        foreach ($feature in $sync.configs.feature.$CheckBox.feature) {
            Write-Host "Instalando $feature"
            Write-WinUtilLog -Component "Feature" -Message "Habilitando recurso opcional do Windows: $feature"
            try {
                Enable-WindowsOptionalFeature -Online -FeatureName $feature -All -NoRestart -ErrorAction Stop
                Write-WinUtilLog -Component "Feature" -Message "Recurso opcional do Windows habilitado: $feature"
            } catch {
                $featureFailed = $true
                # Um recurso ausente nesta edição (ex.: Windows Sandbox no Home) não deve
                # abortar os demais recursos selecionados
                Write-Warning "Não foi possível habilitar o recurso $feature`: $($_.Exception.Message)"
                Write-WinUtilLog -Level "ERROR" -Component "Feature" -Message "Não foi possível habilitar o recurso $feature`: $($_.Exception.Message)"
            }
        }
    }

    if ($featureFailed) {
        Write-WinUtilLog -Level "WARN" -Component "Feature" -Message "Ignorando scripts dependentes após a falha de um recurso opcional: $CheckBox"
    } elseif ($sync.configs.feature.$CheckBox.InvokeScript) {
        foreach ($script in $sync.configs.feature.$CheckBox.InvokeScript) {
            Write-Host "Executando script de $CheckBox"
            Write-WinUtilLog -Component "Feature" -Message "Executando script de recurso para: $CheckBox"
            Invoke-Command -ScriptBlock ([scriptblock]::Create($script)) -ErrorAction Stop
            Write-WinUtilLog -Component "Feature" -Message "Script de recurso concluído para: $CheckBox"
        }
    }
    Write-WinUtilLog -Component "Feature" -Message "Ação de recurso concluída: $CheckBox"
}
