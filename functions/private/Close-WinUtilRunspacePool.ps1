function Close-WinUtilRunspacePool {
    <#
        .SYNOPSIS
            Para o que ainda estiver em execução e fecha o pool de workers

        .DESCRIPTION
            Fechar o pool com trabalho ainda dentro dele é o que produzia uma exceção
            InvalidRunspaceStateException não tratada: uma instância na fila começa em um runspace
            que já está fechando, lança exceção em uma thread do pool de threads e derruba o
            processo. Por isso, pede-se que o que estiver em andamento pare, e espera-se por isso,
            antes de o pool ser fechado.
    #>
    param(
        [int]$StopTimeoutSeconds = 15,

        # Deixa ShuttingDown limpo: nada o redefine, então defini-lo aqui recusaria toda
        # ação posterior pelo resto da sessão
        [switch]$Recycle
    )

    if ($null -eq $sync) {
        return
    }

    $poolLock = Get-WinUtilRunspacePoolLock
    [System.Threading.Monitor]::Enter($poolLock)
    try {
        # Definido antes de parar, para que nada que esteja terminando enfileire trabalho novo atrás de nós
        if (-not $Recycle) {
            $sync.ShuttingDown = $true
        }

        if (-not $sync.ContainsKey("runspace") -or $null -eq $sync.runspace) {
            return
        }

        $stopped = $true
        try {
            $stopped = Stop-WinUtilActiveWork -TimeoutSeconds $StopTimeoutSeconds
        } catch {
            $stopped = $false
            Write-WinUtilLog -Level "WARN" -Component "UI" -Message "Não foi possível parar o trabalho em execução de forma limpa: $($_.Exception.Message)"
        }

        $pool = $sync.runspace
        $cleanupDeferred = $false
        try {
            $poolState = $pool.RunspacePoolStateInfo.State
            $terminalStates = @(
                [System.Management.Automation.Runspaces.RunspacePoolState]::Closed,
                [System.Management.Automation.Runspaces.RunspacePoolState]::Broken
            )

            if (-not $stopped -and $poolState -notin $terminalStates) {
                # Close e Dispose aguardam uma invocação que ignorou BeginStop. Entrega
                # a limpeza ao pool de threads para que o timeout acima continue sendo um limite superior real.
                $cleanupDeferred = $true
                if ($poolState -ne [System.Management.Automation.Runspaces.RunspacePoolState]::Closing) {
                    Register-WinUtilRunspacePoolCleanup -RunspacePool $pool
                }
            } elseif ($poolState -notin ($terminalStates + [System.Management.Automation.Runspaces.RunspacePoolState]::Closing)) {
                $pool.Close()
            }
        } catch {
            # Um pool que não fecha de forma limpa não pode impedir a janela de fechar
            Write-WinUtilLog -Level "WARN" -Component "UI" -Message "O pool de workers não fechou de forma limpa: $($_.Exception.Message)"
        } finally {
            if (-not $cleanupDeferred) {
                try {
                    $pool.Dispose()
                } catch {
                    Write-WinUtilLog -Level "WARN" -Component "UI" -Message "O pool de workers não foi liberado de forma limpa: $($_.Exception.Message)"
                }
            }
            $sync.Remove("runspace")
            if ($sync.ActiveShells) { $sync.ActiveShells.Clear() }
        }
    } finally {
        [System.Threading.Monitor]::Exit($poolLock)
    }
}

function Register-WinUtilRunspacePoolCleanup {
    <#
        .SYNOPSIS
            Fecha e libera um pool de workers sem bloquear a thread chamadora
    #>
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Runspaces.RunspacePool]$RunspacePool
    )

    if (-not ("WinUtilRunspacePoolCleanup" -as [type])) {
        Add-Type @"
using System;
using System.Management.Automation.Runspaces;

public sealed class WinUtilRunspacePoolCleanupState
{
    public RunspacePool RunspacePool { get; set; }
    public IAsyncResult Handle { get; set; }
}

public static class WinUtilRunspacePoolCleanup
{
    public static readonly System.Threading.WaitOrTimerCallback Callback = Cleanup;

    public static void Cleanup(object state, bool timedOut)
    {
        var cleanupState = state as WinUtilRunspacePoolCleanupState;
        if (cleanupState == null || cleanupState.RunspacePool == null || cleanupState.Handle == null)
        {
            return;
        }

        try
        {
            cleanupState.RunspacePool.EndClose(cleanupState.Handle);
        }
        catch
        {
        }
        finally
        {
            try
            {
                cleanupState.RunspacePool.Dispose();
            }
            catch
            {
            }
        }
    }
}
"@
    }

    $cleanupState = [WinUtilRunspacePoolCleanupState]::new()
    $cleanupState.RunspacePool = $RunspacePool
    $cleanupState.Handle = $RunspacePool.BeginClose($null, $null)
    [System.Threading.ThreadPool]::RegisterWaitForSingleObject(
        $cleanupState.Handle.AsyncWaitHandle,
        [WinUtilRunspacePoolCleanup]::Callback,
        $cleanupState,
        -1,
        $true
    ) | Out-Null
}
