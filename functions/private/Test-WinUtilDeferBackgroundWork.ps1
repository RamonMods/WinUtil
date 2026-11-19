function Register-WinUtilInputWatch {
    <#
        .SYNOPSIS
            Registra quando o usuário fez algo pela última vez, para que o trabalho em segundo plano possa sair da frente

        .DESCRIPTION
            Eventos de preview rodam antes de o controle tratar a entrada, então o carimbo é definido
            mesmo para um clique em que o controle depois gasta tempo.
    #>

    $sync.LastInputAt = [datetime]::MinValue

    $stamp = { $sync.LastInputAt = [datetime]::Now }
    $sync.Form.Add_PreviewMouseDown($stamp)
    $sync.Form.Add_PreviewKeyDown($stamp)
    $sync.Form.Add_PreviewMouseWheel($stamp)
}

function Test-WinUtilDeferBackgroundWork {
    <#
        .SYNOPSIS
            Se trabalho especulativo deve esperar em vez de rodar agora

        .DESCRIPTION
            Prioridade em segundo plano enfileira o trabalho atrás da entrada, mas não o torna interrompível:
            o que está rodando deve terminar antes de um clique ser examinado, e é por isso que as partes
            são mantidas curtas. Espera enquanto o usuário está ativo, ou enquanto o trabalho desenha em uma aba
            que não está na tela.

        .PARAMETER RequiresTab
            A aba na qual este trabalho desenha. Trabalho para uma aba oculta espera.
    #>
    param(
        [string]$RequiresTab
    )

    if ($sync.LastInputAt) {
        $sinceInput = ([datetime]::Now - $sync.LastInputAt).TotalMilliseconds
        # longo o suficiente para cobrir um clique e o trabalho que ele inicia, curto o suficiente para não ser notado
        if ($sinceInput -lt 400) {
            return $true
        }
    }

    if ($RequiresTab -and $sync.currentTab -and $sync.currentTab -ne $RequiresTab) {
        return $true
    }

    return $false
}

function Invoke-WinUtilWhenIdle {
    <#
        .SYNOPSIS
            Executa um retorno de chamada quando a interface não está em uso

        .DESCRIPTION
            Um temporizador de disparo único, não uma postagem no dispatcher: uma postagem em prioridade de
            segundo plano roda imediatamente, e o objetivo é deixar uma pausa.

        .PARAMETER Callback
            O que executar quando a espera terminar.

        .PARAMETER Argument
            Passado ao retorno de chamada. Levado no temporizador em vez de capturado, para que o retorno
            resolva comandos onde foi escrito, e não em um escopo copiado.

        .PARAMETER DelayMilliseconds
            Quanto tempo esperar antes de verificar novamente.
    #>
    param(
        [Parameter(Mandatory)]
        [scriptblock]$Callback,

        $Argument,

        [int]$DelayMilliseconds = 150
    )

    if (-not (Test-WinUtilUIAlive)) {
        return
    }

    # Vinculado explicitamente ao dispatcher da interface: o padrão pega o da thread chamadora,
    # o que só está correto enquanto todo chamador chega aqui por uma postagem da interface
    $timer = New-Object System.Windows.Threading.DispatcherTimer([System.Windows.Threading.DispatcherPriority]::Background, $sync.Form.Dispatcher)
    $timer.Interval = [timespan]::FromMilliseconds($DelayMilliseconds)
    $timer.Tag = @{ Callback = $Callback; Argument = $Argument }
    # Remetente retirado do argumento, seguindo como o restante deste código trata os ticks do temporizador
    $timer.Add_Tick({
        param($eventSender)
        $ticked = [System.Windows.Threading.DispatcherTimer]$eventSender
        $ticked.Stop()
        & $ticked.Tag.Callback $ticked.Tag.Argument
    })
    $timer.Start()
}
