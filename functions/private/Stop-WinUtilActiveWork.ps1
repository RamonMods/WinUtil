function Test-WinUtilShellRunning {
    <#
        .SYNOPSIS
            Se uma instância ainda está em execução, tratando uma descartada como concluída
    #>
    param($PowerShell)

    try {
        return $PowerShell.InvocationStateInfo.State -in @(
            [System.Management.Automation.PSInvocationState]::Running,
            [System.Management.Automation.PSInvocationState]::Stopping
        )
    } catch {
        return $false
    }
}

function Register-WinUtilActiveShell {
    <#
        .SYNOPSIS
            Registra uma instância do PowerShell que está rodando no pool de workers

        .DESCRIPTION
            Uma instância ainda enfileirada quando o pool fecha inicia em um runspace em fechamento, lança uma
            exceção em uma thread do pool onde nada a captura, e derruba o processo junto.
            Acompanhar o que está em andamento permite interromper essas primeiro.
    #>
    param(
        [Parameter(Mandatory)]
        $PowerShell
    )

    # Synchronized protege uma operação, não um teste seguido de uma atribuição, então a
    # coleção é criada sob o bloqueio compartilhado
    [System.Threading.Monitor]::Enter($sync.SyncRoot)
    try {
        if ($null -eq $sync.ActiveShells) {
            $sync.ActiveShells = [System.Collections.ArrayList]::Synchronized([System.Collections.ArrayList]::new())
        }
    } finally {
        [System.Threading.Monitor]::Exit($sync.SyncRoot)
    }

    # Nada descarta estas na saída, então as concluídas são removidas aqui, em vez de
    # se acumularem durante toda a sessão
    foreach ($finished in (Get-WinUtilActiveShell)) {
        if (-not (Test-WinUtilShellRunning $finished)) {
            try {
                $sync.ActiveShells.Remove($finished)
            } catch {
                Write-WinUtilLog -Level "WARN" -Component "UI" -Message "Não foi possível remover um worker concluído do conjunto ativo: $_"
            }
        }
    }

    $null = $sync.ActiveShells.Add($PowerShell)
}

function Get-WinUtilActiveShell {
    <#
        .SYNOPSIS
            Um instantâneo das instâncias acompanhadas, copiado sob o bloqueio da própria coleção

        .DESCRIPTION
            Enumerar um ArrayList sincronizado não é, por si só, sincronizado; um Add ou Remove
            concorrente lança no meio do laço. SyncRoot é a correção documentada.
    #>

    if ($null -eq $sync.ActiveShells) {
        return @()
    }

    [System.Threading.Monitor]::Enter($sync.ActiveShells.SyncRoot)
    try {
        return @($sync.ActiveShells.ToArray())
    } finally {
        [System.Threading.Monitor]::Exit($sync.ActiveShells.SyncRoot)
    }
}

function Stop-WinUtilActiveWork {
    <#
        .SYNOPSIS
            Pede a tudo que roda no pool de workers para parar, e espera

        .DESCRIPTION
            Parar é um pedido, não uma morte: um comando já dentro de um instalador roda até
            retornar. A espera é limitada para que um worker que nunca retorna não possa manter a janela
            aberta.

        .PARAMETER TimeoutSeconds
            Quanto tempo esperar antes de desistir.
    #>
    param(
        [int]$TimeoutSeconds = 15,

        # Emite a parada e retorna. O chamador consulta Test-WinUtilActiveWorkRunning em vez de
        # bloquear aqui, o que importa na thread da interface, onde uma espera congela a janela.
        [switch]$NoWait
    )

    $shells = Get-WinUtilActiveShell
    if ($shells.Count -eq 0) {
        return $true
    }

    Write-WinUtilLog -Component "UI" -Message "Parando $($shells.Count) item(ns) em execução antes de fechar."

    foreach ($shell in $shells) {
        if (Test-WinUtilShellRunning $shell) {
            try {
                $null = $shell.BeginStop($null, $null)
            } catch {
                Write-WinUtilLog -Level "WARN" -Component "UI" -Message "Não foi possível pedir a parada de um worker: $_"
            }
        }
    }

    if ($NoWait) {
        return $false
    }

    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    while ($clock.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        $stillRunning = @(Get-WinUtilActiveShell | Where-Object { Test-WinUtilShellRunning $_ }).Count

        if ($stillRunning -eq 0) {
            Write-WinUtilLog -Component "UI" -Message "Tudo parou após $($clock.ElapsedMilliseconds) ms."
            return $true
        }

        Start-Sleep -Milliseconds 100
    }

    Write-WinUtilLog -Level "WARN" -Component "UI" -Message "Desistiu de esperar a parada do trabalho após $TimeoutSeconds segundos, fechando mesmo assim."
    return $false
}

function Test-WinUtilActiveWorkRunning {
    <#
        .SYNOPSIS
            Se alguma instância acompanhada ainda está em execução
    #>

    foreach ($shell in (Get-WinUtilActiveShell)) {
        if (Test-WinUtilShellRunning $shell) { return $true }
    }

    return $false
}
