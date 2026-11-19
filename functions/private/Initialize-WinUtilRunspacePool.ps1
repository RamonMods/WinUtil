function Initialize-WinUtilRunspacePool {
    <#
        .SYNOPSIS
            Abre o pool de workers compartilhado em que Start-WinUtilJob executa os corpos dos jobs
    #>

    $poolLock = Get-WinUtilRunspacePoolLock
    [System.Threading.Monitor]::Enter($poolLock)
    try {
        if ($sync.runspace -and $sync.runspace.RunspacePoolStateInfo.State -eq [System.Management.Automation.Runspaces.RunspacePoolState]::Opened) {
            return $sync.runspace
        }

        if ($sync.runspace) {
            # Uma substituição, não um encerramento
            Close-WinUtilRunspacePool -Recycle
        }

        # Define o número máximo de threads do RunspacePool como o número de threads da máquina.
        $maxthreads = [Math]::Max([int]$env:NUMBER_OF_PROCESSORS, 1)

        $sync.runspace = [runspacefactory]::CreateRunspacePool(
            1,                            # Número mínimo de threads
            $maxthreads,                  # Número máximo de threads
            (New-WinUtilSessionState),    # Estado de sessão inicial
            $Host                         # Máquina em que os runspaces serão criados
        )

        $sync.runspace.Open()
        return $sync.runspace
    } finally {
        [System.Threading.Monitor]::Exit($poolLock)
    }
}
