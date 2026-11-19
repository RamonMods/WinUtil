function Complete-WinUtilPackageRun {
    <#
        .SYNOPSIS
            Relata o que uma execução de pacotes realmente fez e falha o job em erros inesperados

        .DESCRIPTION
            Os gerenciadores de pacotes relatam falha por código de saída, que é fácil de ignorar.
            Sem isso, a camada de job mostraria um check verde para uma execução em que nada
            mudou. Falhas inesperadas encerram o job; as omissões esperadas por contexto elevado
            geram um aviso, para que o job não possa afirmar que toda ação solicitada foi concluída.

        .PARAMETER Action
            Install ou Uninstall, usados no texto do resumo.

    #>
    param(
        [Parameter(Mandatory)]
        [string]$Action,

        [object[]]$Results = @()
    )

    $succeeded = @($Results | Where-Object { $_.Outcome -eq "Succeeded" })
    $skipped = @($Results | Where-Object { $_.Outcome -eq "Skipped" })
    $failed = @($Results | Where-Object { $_.Outcome -eq "Failed" })

    $summary = "$($succeeded.Count) com sucesso, $($skipped.Count) ignorados, $($failed.Count) com falha"
    Write-WinUtilLog -Component "Package" -Message "Resumo de ${Action}: $summary"
    Write-Host "Resumo de ${Action}: $summary"

    foreach ($result in $skipped) {
        Write-Host "  ignorado  $($result.Package) - $($result.Detail)"
    }
    foreach ($result in $failed) {
        Write-Host "  falhou   $($result.Package) - $($result.Detail)" -ForegroundColor Red
    }

    $adminContextSkipped = @($skipped | Where-Object { $_.ExitCode -eq -1978335107 })
    if ($adminContextSkipped.Count -gt 0) {
        Write-Warning "$($adminContextSkipped.Count) ação(ões) de pacote foram ignoradas porque o WinUtil elevado não pode modificar instalações do escopo do usuário."
    }

    if ($failed.Count -gt 0) {
        $names = ($failed | ForEach-Object { $_.Package }) -join ', '
        $reasons = @($failed | ForEach-Object { $_.Detail } | Sort-Object -Unique)

        $message = if ($reasons.Count -eq 1) {
            "$($failed.Count) de $($Results.Count) pacote(s) falharam: $names. $($reasons[0])"
        } else {
            "$($failed.Count) de $($Results.Count) pacote(s) falharam: $names. Veja as linhas acima para cada motivo."
        }
        # Cada pacote com falha já foi registrado no log pelo adaptador do gerenciador de pacotes.
        # Leve esse fato junto com a exceção de resumo, para que o wrapper do job acrescente contexto sem outra contagem de erros.
        $exception = [System.InvalidOperationException]::new($message)
        $exception.Data["WinUtilErrorReported"] = $true
        throw $exception
    }
}
