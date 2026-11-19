function Test-WinUtilUIAlive {
    <#
        .SYNOPSIS
            Se existe uma janela na qual ainda é possível postar

        .DESCRIPTION
            Falso para uma execução sem interface e para uma janela fechada durante uma tarefa em
            andamento: um dispatcher desligado aceita postagens e as descarta.
    #>

    return $null -ne $sync.Form -and $null -ne $sync.Form.Dispatcher -and -not $sync.Form.Dispatcher.HasShutdownStarted
}

function Test-WinUtilDispatcherShutdownException {
    param([System.Exception]$Exception)

    while ($null -ne $Exception) {
        if ($Exception -is [System.OperationCanceledException] -or
            $Exception -is [System.InvalidOperationException]) {
            return $true
        }
        $Exception = $Exception.InnerException
    }

    return $false
}

function Invoke-WPFUIThread {
    <#
        .SYNOPSIS
            Executa um scriptblock na thread da interface

        .DESCRIPTION
            Os controles só podem ser acessados pela thread que possui a janela.

            O corpo é entregue como texto e reconstruído no runspace da interface, em vez de empacotado
            como scriptblock: um scriptblock mantém o estado da sessão em que foi escrito, e executá-lo
            entre runspaces custa cerca de vinte vezes mais por comando. Por isso, os valores entram
            por Parameters em vez de serem capturados do escopo do chamador.

            Não faz nada quando a janela desaparece, para que um job que sobreviva à interface termine
            silenciosamente.

        .PARAMETER ScriptBlock
            O trabalho a executar na thread da interface. Declare um bloco param para o que ele precisar.

        .PARAMETER Parameters
            Valores passados ao corpo por nome.

        .PARAMETER Async
            Posta e retorna em vez de esperar. Para progresso e logs, que nunca devem bloquear o chamador.

        .PARAMETER PassThru
            Retorna o que o corpo produziu. Desativado por padrão, para que um chamador que só queria
            atualizar um controle não receba saída indesejada.
    #>
    param(
        [Parameter(Mandatory, Position = 0)]
        [scriptblock]$ScriptBlock,

        [hashtable]$Parameters = @{},

        [switch]$Async,

        [switch]$PassThru
    )

    if (-not (Test-WinUtilUIAlive)) {
        return
    }
    $dispatcher = $sync.Form.Dispatcher

    if (-not $Async -and $dispatcher.CheckAccess()) {
        $inlineResult = & $ScriptBlock @Parameters
        if ($PassThru) { return $inlineResult }
        return
    }

    $executor = $sync.UIDispatchDelegate
    if ($null -eq $executor) {
        # Não há runspace da interface para entregar o trabalho, então o próprio bloco é empacotado.
        # Ele precisa receber seus parâmetros e retornar o que produziu, e [action] não faz nem isso.
        if ($Async) {
            # Os valores viajam como argumento do dispatcher, pois esta chamada retorna antes de o
            # bloco executar e qualquer coisa capturada daqui já teria desaparecido até então
            try {
                $null = $dispatcher.BeginInvoke(
                    [Windows.Threading.DispatcherPriority]::Background,
                    [System.Windows.Threading.DispatcherOperationCallback]{
                        param($Work)
                        $body = $Work.Body
                        $arguments = $Work.Parameters
                        if ($arguments -and $arguments.Count -gt 0) {
                            $null = & $body @arguments
                        } else {
                            $null = & $body
                        }
                        return $null
                    },
                    @{ Body = $ScriptBlock; Parameters = $Parameters })
            } catch {
                $shutdownFailure = Test-WinUtilDispatcherShutdownException -Exception $_.Exception
                if ($shutdownFailure -and -not (Test-WinUtilUIAlive)) { return }
                throw
            }
            return
        }

        # Síncrono, então este frame ainda está vivo enquanto o bloco executa e pode ser capturado daqui
        try {
            $fallbackResult = $dispatcher.Invoke([System.Func[object]]{ & $ScriptBlock @Parameters })
        } catch {
            $shutdownFailure = Test-WinUtilDispatcherShutdownException -Exception $_.Exception
            if ($shutdownFailure -and -not (Test-WinUtilUIAlive)) { return }
            throw
        }
        if ($PassThru) { return $fallbackResult }
        return
    }

    $work = @{
        Body = $ScriptBlock.ToString()
        Parameters = $Parameters
        # Um chamador síncrono aguarda uma transferência obrigatória para a interface e precisa ver a falha.
        # Postagens sem retorno não têm ninguém para receber uma exceção, então o delegado só a registra no log.
        PropagateErrors = -not $Async
    }

    if ($Async) {
        try {
            $null = $dispatcher.BeginInvoke([Windows.Threading.DispatcherPriority]::Background, $executor, $work)
        } catch {
            $shutdownFailure = Test-WinUtilDispatcherShutdownException -Exception $_.Exception
            if ($shutdownFailure -and -not (Test-WinUtilUIAlive)) { return }
            throw
        }
        return
    }

    try {
        $result = $dispatcher.Invoke($executor, @($work))
    } catch {
        $shutdownFailure = Test-WinUtilDispatcherShutdownException -Exception $_.Exception
        if ($shutdownFailure -and -not (Test-WinUtilUIAlive)) { return }
        throw
    }
    if ($PassThru) { return $result }
}
