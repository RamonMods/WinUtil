function Get-WinUtilRunspacePoolLock {
    <#
        .SYNOPSIS
            Retorna o lock que serializa a inicialização e o encerramento do pool de workers
    #>

    [System.Threading.Monitor]::Enter($sync.SyncRoot)
    try {
        if ($null -eq $sync.RunspacePoolLock) {
            $sync.RunspacePoolLock = [object]::new()
        }

        return $sync.RunspacePoolLock
    } finally {
        [System.Threading.Monitor]::Exit($sync.SyncRoot)
    }
}
