function Invoke-WPFExportEnvironmentReport {
    <#
    .SYNOPSIS
        Exporta como JSON um relatório de ambiente somente leitura e com lista de permissões, com um
        pacote opcional dos logs recentes do WinUtil.
    #>

    try {
        $includeLogs = (Show-WinUtilMessage `
            -Message "Deseja incluir também os últimos 7 dias de logs do WinUtil? O arquivo complementar contém logs brutos e pode incluir caminhos locais, comandos e detalhes de erros. Revise-o antes de compartilhar." `
            -Title "Relatório de Ambiente" -Button "YesNo" -Icon "Question") -eq "Yes"

        Add-Type -AssemblyName System.Windows.Forms
        $dialog = [System.Windows.Forms.SaveFileDialog]::new()
        $dialog.Title = "Exportar Relatório de Ambiente"
        $dialog.Filter = "Arquivos JSON (*.json)|*.json"
        $dialog.FileName = "WinUtilEnvironmentReport_$(Get-Date -Format 'yyyyMMdd').json"
        $dialog.InitialDirectory = [Environment]::GetFolderPath("Desktop")

        if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
            return
        }

        $jsonPath = $dialog.FileName
        $logsPath = Get-WinUtilEnvironmentReportLogsPath -JsonPath $jsonPath

        # O próprio aviso de substituição do SaveFileDialog cobre apenas $jsonPath. Um arquivo complementar
        # derivado de uma exportação anterior não deve ser substituído silenciosamente nem parecer pertencer ao novo JSON.
        if (Test-Path -LiteralPath $logsPath) {
            if (-not $includeLogs) {
                Show-WinUtilMessage `
                    -Message "Já existe um arquivo de logs em:`n$logsPath`n`nEscolha outro nome para o relatório ou inclua e substitua os logs existentes." `
                    -Title "Relatório de Ambiente" -Button "OK" -Icon "Warning" | Out-Null
                return
            }

            $replaceLogs = (Show-WinUtilMessage `
                -Message "Já existe um arquivo de logs em:`n$logsPath`n`nSubstituí-lo?" `
                -Title "Relatório de Ambiente" -Button "YesNo" -Icon "Warning") -eq "Yes"
            if (-not $replaceLogs) {
                return
            }
        }

        # As leituras do Registro em cada ajuste/interruptor e a leitura do pacote de logs somam alguns
        # segundos, então a camada de jobs mantém o manipulador de Configurações responsivo e cuida do
        # progresso, do estado da barra de tarefas, do log e do relatório de erros.
        Start-WinUtilJob -Name "EnvironmentReport" -Description "Exportando relatório de ambiente" -Parameters @{
            JsonPath = $jsonPath
            LogsPath = $logsPath
            IncludeLogs = $includeLogs
        } -ScriptBlock {
            param($JsonPath, $LogsPath, $IncludeLogs)

            Step-WinUtilJob -Status "Coletando relatório de ambiente" -Percent 10
            $report = Get-WinUtilEnvironmentReport
            $json = $report | ConvertTo-Json -Depth 6

            if ($IncludeLogs) {
                Step-WinUtilJob -Status "Coletando os logs recentes do WinUtil" -Percent 60
                $logs = Get-WinUtilRecentLogs
            }

            Step-WinUtilJob -Status "Gravando a exportação do ambiente" -Percent 80
            Write-WinUtilEnvironmentReportExport -JsonPath $JsonPath -Json $json `
                -LogsPath $LogsPath -Logs $logs -IncludeLogs:$IncludeLogs

            Write-WinUtilLog -Component "EnvironmentReport" -Message "Relatório de ambiente exportado para $JsonPath."
            Step-WinUtilJob -Status "Exportação do ambiente concluída" -Percent 100
        }
    } catch {
        Write-WinUtilLog -Component "EnvironmentReport" -Level "ERROR" -Message "A exportação do relatório de ambiente falhou: $($_.Exception.Message)"
        Show-WinUtilMessage -Message "Não foi possível exportar o relatório de ambiente. $($_.Exception.Message)" `
            -Title "Relatório de Ambiente" -Button "OK" -Icon "None" | Out-Null
    }
}
