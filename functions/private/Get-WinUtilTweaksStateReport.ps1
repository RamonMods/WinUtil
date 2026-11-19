function Get-WinUtilTweaksStateReport {
    <#
    .SYNOPSIS
        Agrupa o estado aplicado real de cada entrada de config/tweaks.json por categoria, reutilizando a mesma
        detecção que Invoke-WPFGetInstalled usa para marcar as caixas de seleção de "Select Installed Tweaks".
    #>

    $categoryFieldNames = [ordered]@{
        "Essential Tweaks"                    = "essentialTweaks"
        "Customize Preferences"               = "customizePreferences"
        "z__Advanced Tweaks - CAUTION"         = "advancedTweaks"
        "Performance Plans - NOT FOR LAPTOPS" = "performancePlans"
    }

    $grouped = [ordered]@{}
    foreach ($fieldName in $categoryFieldNames.Values) {
        $grouped[$fieldName] = [ordered]@{}
    }
    $notEvaluable = [System.Collections.Generic.List[string]]::new()
    $collectionStatus = "collected"

    try {
        $appliedTweaks = [System.Collections.Generic.HashSet[string]]::new(
            [string[]]@(Invoke-WinUtilCurrentSystem -CheckBox "tweaks" `
                -BypassToggleStatusCache -StopOnReadError)
        )

        foreach ($property in $sync.configs.tweaks.PSObject.Properties) {
            $tweakKey = $property.Name
            $entry = $property.Value
            $fieldName = $categoryFieldNames[[string]$entry.category]

            # Botões embutidos no painel de ajustes (ex.: os iniciadores OOSU/Ultimate Performance)
            # são ações, não ajustes com estado, então ficam totalmente fora do escopo deste relatório.
            if (-not $fieldName -or $entry.Type -eq "Button") {
                continue
            }

            # Ajustes do tipo combobox e ajustes apenas de script, sem esquema de registro/serviço, não têm
            # estado atual detectável. Liste-os para que o relatório não os descarte silenciosamente.
            if ($entry.Type -eq "Combobox" -or (-not $entry.registry -and -not $entry.service)) {
                $notEvaluable.Add($tweakKey)
                continue
            }

            $grouped[$fieldName][$tweakKey] = $appliedTweaks.Contains($tweakKey)
        }
    } catch {
        Write-WinUtilLog -Component "EnvironmentReport" -Level "WARN" -Message "Falha ao coletar o estado de ajustes/interruptores: $($_.Exception.Message)"
        $collectionStatus = "unavailable"
    }

    # Grupos vazios de uma coleta com falha seriam indistinguíveis no JSON de uma
    # varredura bem-sucedida que nada encontrou de notável, então registre se a coleta realmente rodou.
    $result = [ordered]@{ collectionStatus = $collectionStatus }
    foreach ($fieldName in $categoryFieldNames.Values) {
        $result[$fieldName] = [pscustomobject]$grouped[$fieldName]
    }
    $result.notEvaluable = @($notEvaluable)

    return [pscustomobject]$result
}
