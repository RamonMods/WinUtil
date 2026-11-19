function Register-WinUtilRunspaceCleanup {
    <#
        .SYNOPSIS
            Descarta uma instância do PowerShell e qualquer runspace de sua propriedade quando seu trabalho termina

        .DESCRIPTION
            Encerra a invocação e descarta a instância a partir de um callback do pool de threads, para
            que nada precise esperar a conclusão de um runspace "fire-and-forget" apenas para limpá-lo.

        .PARAMETER PowerShell
            A instância a descartar.

        .PARAMETER Handle
            O identificador retornado por seu BeginInvoke.

        .PARAMETER Runspace
            Um runspace dedicado pertencente à invocação. Invocações em pool compartilhado o omitem.
    #>
    param(
        [Parameter(Mandatory)]
        $PowerShell,

        [Parameter(Mandatory)]
        $Handle,

        $Runspace
    )

    # Versiona o auxiliar CLR porque as definições Add-Type sobrevivem a execuções repetidas do WinUtil em memória.
    # Sessões antigas podem já conter o tipo V1, cujo objeto de estado não tem a propriedade Runspace.
    if (-not ("WinUtilRunspaceCleanupV3" -as [type])) {
        Add-Type @"
using System;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Threading;

public sealed class WinUtilRunspaceCleanupStateV3
{
    public PowerShell PowerShell { get; set; }
    public IAsyncResult Handle { get; set; }
    public Runspace Runspace { get; set; }
}

public static class WinUtilRunspaceCleanupV3
{
    public static readonly System.Threading.WaitOrTimerCallback Callback = Cleanup;

    public static bool Register(WinUtilRunspaceCleanupStateV3 state)
    {
        try
        {
            ThreadPool.RegisterWaitForSingleObject(state.Handle.AsyncWaitHandle, Callback, state, -1, true);
            return true;
        }
        catch
        {
            // O registro normalmente não falha, mas o trabalho já começou. Uma thread de espera em segundo plano
            // preserva a limpeza assíncrona sem bloquear o dispatcher do WPF.
            try
            {
                var thread = new Thread(() =>
                {
                    try
                    {
                        state.Handle.AsyncWaitHandle.WaitOne();
                    }
                    catch
                    {
                    }
                    Cleanup(state, false);
                });
                thread.IsBackground = true;
                thread.Name = "WinUtil runspace cleanup fallback";
                thread.Start();
                return true;
            }
            catch
            {
                return false;
            }
        }
    }

    public static void Cleanup(object state, bool timedOut)
    {
        var cleanupState = state as WinUtilRunspaceCleanupStateV3;
        if (cleanupState == null || cleanupState.PowerShell == null || cleanupState.Handle == null)
        {
            return;
        }

        try
        {
            cleanupState.PowerShell.EndInvoke(cleanupState.Handle);
        }
        catch
        {
        }
        finally
        {
            cleanupState.PowerShell.Dispose();
            if (cleanupState.Runspace != null)
            {
                try
                {
                    cleanupState.Runspace.Close();
                }
                catch
                {
                }
                finally
                {
                    cleanupState.Runspace.Dispose();
                }
            }
        }
    }
}
"@
    }

    $cleanupState = [WinUtilRunspaceCleanupStateV3]::new()
    $cleanupState.PowerShell = $PowerShell
    $cleanupState.Handle = $Handle
    $cleanupState.Runspace = $Runspace
    $registered = [WinUtilRunspaceCleanupV3]::Register($cleanupState)
    if (-not $registered) {
        Write-WinUtilLog -Level "WARN" -Component "UI" -Message "Não foi possível registrar a limpeza assíncrona para o trabalho em segundo plano; ela será recuperada quando trabalho posterior ou o desligamento a inspecionar."
    }
}
