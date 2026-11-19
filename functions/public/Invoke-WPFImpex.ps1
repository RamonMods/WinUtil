function Invoke-WPFImpex {
    <#

    .SYNOPSIS
        Manipula a importação e exportação das caixas de seleção marcadas na seção de ajustes

    .PARAMETER type
        Indica se deve 'import' ou 'export'

    .PARAMETER checkbox
        A caixa de seleção a exportar para um arquivo ou à qual aplicar o arquivo importado

    .EXAMPLE
        Invoke-WPFImpex -type "export"

    #>
    param(
        $type,
        $Config = $null,

        # Adiciona à seleção atual em vez de substituí-la. Usado quando uma predefinição já
        # definiu uma base que o arquivo importado deve estender.
        [switch]$Merge,

        # Execuções sem interface não podem mostrar uma caixa de diálogo e devem falhar em vez de aplicar uma solicitação parcial.
        [switch]$ThrowOnError
    )

    function ConfigDialog {
        if (!$Config) {
            switch ($type) {
                "export" { $FileBrowser = New-Object System.Windows.Forms.SaveFileDialog }
                "import" { $FileBrowser = New-Object System.Windows.Forms.OpenFileDialog }
            }
            $FileBrowser.InitialDirectory = [Environment]::GetFolderPath('Desktop')
            $FileBrowser.Filter = "Arquivos JSON (*.json)|*.json"
            $FileBrowser.ShowDialog() | Out-Null

            if ($FileBrowser.FileName -eq "") {
                return $null
            } else {
                return $FileBrowser.FileName
            }
        } else {
            return $Config
        }
    }

    switch ($type) {
        "export" {
            try {
                $Config = ConfigDialog
                if ($Config) {
                    $allConfs = ($sync.selectedApps + $sync.selectedTweaks + $sync.selectedToggles + $sync.selectedFeatures + $sync.selectedAppx) | ForEach-Object { [string]$_ }
                    if (-not $allConfs) {
                        Show-WinUtilMessage -Message (
                            "Nenhuma configuração está selecionada para exportar. Selecione pelo menos um aplicativo, ajuste, interruptor, recurso ou pacote AppX antes de exportar."
                        ) -Title "Nada para exportar" -Button "OK" -Icon "Warning" | Out-Null
                        return
                    }
                    $jsonFile = $allConfs | ConvertTo-Json
                    $jsonFile | Out-File -LiteralPath $Config -Force
                    # Mantém o caminho literal quando o comando copiado é colado no PowerShell.
                    $escapedConfig = [System.Management.Automation.Language.CodeGeneration]::EscapeSingleQuotedStringContent($Config)
                    "& ([ScriptBlock]::Create((Invoke-RestMethod 'https://github.com/RamonMods/WinUtil/releases/latest/download/winutil.ps1'))) -Config '$escapedConfig'" | Set-Clipboard
                }
            } catch {
                Write-Error "Ocorreu um erro durante a exportação: $_"
            }
        }
        "import" {
            try {
                $Config = ConfigDialog
                if ($Config) {
                    try {
                        if ($Config -match '^https?://') {
                            $jsonFile = (Invoke-WebRequest "$Config" -UseBasicParsing -ErrorAction Stop).Content | ConvertFrom-Json
                        } else {
                            $jsonFile = Get-Content -LiteralPath $Config -ErrorAction Stop | ConvertFrom-Json
                        }
                    } catch {
                        $message = "Falha ao carregar o arquivo JSON do caminho ou URL especificados: $_"
                        if ($ThrowOnError) { throw $message }
                        Write-Error $message
                        return
                    }
                    $isLegacyConfig = $jsonFile -is [System.Management.Automation.PSCustomObject] -and
                        $null -ne $jsonFile.PSObject.Properties["Install"] -and
                        $null -ne $jsonFile.PSObject.Properties["WPFInstall"]
                    if ($isLegacyConfig) {
                        Write-WinUtilLog -Component "Impex" -Message "Estrutura de configuração herdada do WinUtil detectada; achatando o objeto de importação."
                        # Exportações antigas armazenavam as chaves das caixas de seleção em WPFInstall e duplicavam
                        # os metadados de origem dos pacotes em Install. Os IDs de pacote atuais vêm do catálogo de
                        # aplicativos, portanto apenas as propriedades de chave de seleção são restauradas.
                        $flattenedJson = @(
                            foreach ($property in $jsonFile.PSObject.Properties) {
                                if ($property.Name -notmatch '^WPF(?:Install|Tweaks|Toggle|Feature|Appx)') {
                                    continue
                                }

                                foreach ($selection in @($property.Value)) {
                                    if ($selection -is [string] -and -not [string]::IsNullOrWhiteSpace($selection)) {
                                        $selection
                                    }
                                }
                            }
                        )
                    } else {
                        # Configuração no formato novo: array simples de strings
                        $flattenedJson = $jsonFile
                    }

                    if (-not $flattenedJson) {
                        Show-WinUtilMessage -Message "O arquivo selecionado não contém configurações para importar. Nenhuma alteração foi feita." -Title "Configuração vazia" -Button "OK" -Icon "Warning" | Out-Null
                        return
                    }

                    # Substitui, a menos que esta importação esteja sendo mesclada com algo já selecionado,
                    # o que ocorre no caminho sem interface quando recebe uma predefinição e uma configuração
                    $replaceMode = @{}
                    if (-not $Merge) { $replaceMode["Replace"] = $true }

                    # Configurações modernas permanecem rígidas. Configurações antigas podem referenciar entradas que
                    # não existem mais, portanto restaura as seleções compatíveis e relata as chaves desativadas.
                    if ($isLegacyConfig) {
                        $skippedSelections = @(Update-WinUtilSelections -flatJson $flattenedJson @replaceMode -SkipUnknown)

                        if ($skippedSelections.Count -gt 0) {
                            $skippedSummary = $skippedSelections -join ", "
                            Write-WinUtilLog -Component "Impex" -Level "WARN" -Message "Seleções herdadas sem suporte ignoradas: $skippedSummary"
                        }

                        if ($skippedSelections.Count -eq @($flattenedJson).Count) {
                            if ($sync.Form) {
                                Show-WinUtilMessage -Message "Esta configuração herdada não contém nenhuma configuração compatível com esta versão do WinUtil. Nenhuma alteração foi feita." -Title "Configuração herdada sem suporte" -Icon "Warning" | Out-Null
                            }
                            return
                        }

                        if ($skippedSelections.Count -gt 0) {
                            $skippedDisplay = @($skippedSelections | Select-Object -First 10) -join ", "
                            if ($skippedSelections.Count -gt 10) {
                                $skippedDisplay += "`n...e mais $($skippedSelections.Count - 10). Consulte o log do WinUtil para obter detalhes."
                            }
                            if ($sync.Form) {
                                Show-WinUtilMessage -Message "As configurações compatíveis foram importadas. As seguintes configurações desativadas foram ignoradas:`n`n$skippedDisplay" -Title "Configuração herdada importada parcialmente" -Icon "Warning" | Out-Null
                            }
                        }
                    } else {
                        # Cria e valida cada seleção importada antes de substituir o estado
                        # atual. Isso evita que uma configuração malformada deixe seleções parciais.
                        Update-WinUtilSelections -flatJson $flattenedJson @replaceMode
                    }

                    if ($sync.Form) {
                        Reset-WPFCheckBoxes -doToggles $true
                    }
                }
            } catch {
                if ($ThrowOnError) { throw }
                Write-Error "Ocorreu um erro durante a importação: $_"
            }
        }
    }
}
