function Start-WinUtilBackgroundQueue {
    <#
        .SYNOPSIS
            Esvazia uma fila de trabalho da interface, um item por vez, entre as ações do usuário

        .DESCRIPTION
            Para trabalho que precisa rodar na thread da interface mas que ninguém espera: abas
            não abertas, itens da lista de aplicativos. Um item por operação enfileirada, para que
            a entrada seja respondida entre eles e não depois da lista inteira.

            Republicado em vez de repetido em laço: só voltar ao dispatcher permite que ele atenda
            a entrada. Publicado como ação compilada em vez de via Invoke-WPFUIThread, cujo corpo
            atravessa runspaces como texto e seria recompilado em cada uma das centenas de
            publicações que uma lista de aplicativos completa custa.

        .PARAMETER Name
            Identifica a fila em $sync para que um bombeamento republicado encontre seu estado.

        .PARAMETER Queue
            A fila a esvaziar. Os itens significam o que Step disser que significam.

        .PARAMETER Step
            Executa um item. Recebe o item retirado da fila.

        .PARAMETER OnComplete
            Executa uma vez na thread da interface após o último item.

        .PARAMETER RequiresTab
            O trabalho que desenha nesta aba espera enquanto outra aba é exibida.

        .PARAMETER DeferWhile
            Motivo extra para adiar, testado a cada rodada. Deixa uma fila mais urgente ir primeiro.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        $Queue,

        [Parameter(Mandatory)]
        [scriptblock]$Step,

        [scriptblock]$OnComplete,

        [string]$RequiresTab,

        [scriptblock]$DeferWhile
    )

    if ($null -eq $sync.BackgroundQueues) {
        $sync.BackgroundQueues = [hashtable]::Synchronized(@{})
    }

    $sync.BackgroundQueues[$Name] = @{
        Queue = $Queue
        Step = $Step
        OnComplete = $OnComplete
        RequiresTab = $RequiresTab
        DeferWhile = $DeferWhile
    }

    # Sem janela não há dispatcher para distribuir o trabalho e nada competindo pela thread
    if (-not (Test-WinUtilUIAlive)) {
        while ($Queue.Count -gt 0) {
            # Um item com falha não pode abandonar o resto nem deixar o estado preso, igual ao
            # caminho do dispatcher
            try {
                & $Step $Queue.Dequeue()
            } catch {
                Write-WinUtilErrorRecord -ErrorRecord $_ -Component "UI" -Context "Fila em segundo plano '$Name'"
            }
        }
        if ($OnComplete) { & $OnComplete }
        $sync.BackgroundQueues.Remove($Name)
        return
    }

    Request-WinUtilBackgroundQueueStep -Name $Name
}

function Request-WinUtilBackgroundQueueStep {
    <#
        .SYNOPSIS
            Publica o próximo passo de uma fila com prioridade de segundo plano

        .PARAMETER Name
            Qual fila avançar.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    if (-not (Test-WinUtilUIAlive)) {
        return
    }

    # O nome viaja como argumento do dispatcher, não capturado: esta função já retornou quando o
    # bloco executa, e um closure ligaria a busca de comandos a um escopo copiado.
    $null = $sync.Form.Dispatcher.BeginInvoke(
        [System.Windows.Threading.DispatcherPriority]::Background,
        [System.Windows.Threading.DispatcherOperationCallback]{
            param($QueueName)
            Invoke-WinUtilBackgroundQueueStep -Name $QueueName
            return $null
        },
        $Name)
}

function Invoke-WinUtilBackgroundQueueStep {
    <#
        .SYNOPSIS
            Executa um item de uma fila e pede o próximo, ou termina

        .PARAMETER Name
            Qual fila avançar.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    $state = $sync.BackgroundQueues[$Name]
    if ($null -eq $state) {
        return
    }

    if ($state.Queue.Count -gt 0) {
        $defer = (Test-WinUtilDeferBackgroundWork -RequiresTab $state.RequiresTab) -or
                 ($state.DeferWhile -and (& $state.DeferWhile))

            # Espera em vez de competir com o que o usuário está fazendo
        if ($defer) {
            Invoke-WinUtilWhenIdle -Argument $Name -Callback {
                param($QueueName)
                Invoke-WinUtilBackgroundQueueStep -Name $QueueName
            }
            return
        }

        try {
            & $state.Step $state.Queue.Dequeue()
        } catch {
            Write-WinUtilErrorRecord -ErrorRecord $_ -Component "UI" -Context "Fila em segundo plano '$Name'"
        }
    }

    if ($state.Queue.Count -gt 0) {
        Request-WinUtilBackgroundQueueStep -Name $Name
        return
    }

    $sync.BackgroundQueues.Remove($Name)
    if ($state.OnComplete) { & $state.OnComplete }
}
