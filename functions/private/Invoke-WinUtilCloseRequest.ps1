function Invoke-WinUtilCloseRequest {
    <#
        .SYNOPSIS
            Pergunta o que fazer com o trabalho que ainda está em execução quando a janela é fechada

        .DESCRIPTION
            Uma instalação ou execução de ajustes pela metade não é encerrada sem perguntar. Ou ela
            termina sem a janela, reportando no console e então saindo, ou é interrompida e tudo
            fecha agora.

        .PARAMETER RunningJob
            O nome da tarefa em andamento, para que a pergunta diga o que está em jogo. Sem nada
            em execução e apenas com tarefas na fila, a pergunta é só se elas devem ser descartadas.

        .PARAMETER QueuedCount
            Quantas tarefas na fila o fechamento vai descartar, para que não sejam uma surpresa.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$RunningJob,

        [int]$QueuedCount = 0
    )

    if (-not $sync.ActiveJob) {
        $discard = Show-WinUtilJobCloseMessage -Button "YesNo" -Icon "Warning" -Title "Operações na fila" -Message "Nada está em execução. $QueuedCount operação(ões) na fila serão descartadas.`n`nFechar o WinUtil mesmo assim?"
        if ("$discard" -ne "Yes") {
            Write-WinUtilLog -Component "UI" -Message "Fechamento cancelado, $QueuedCount operação(ões) ainda estão na fila."
            return
        }

        # Verifica novamente sob o bloqueio da fila, caso um chamador concorrente tenha assumido a vaga
        # antes de o prompt pausar as trocas. O fechamento precisa perguntar sobre essa tarefa em vez de
        # interrompê-la silenciosamente.
        $startedMeanwhile = Stop-WinUtilQueuedWork -OnlyIfIdle
        if ($startedMeanwhile) {
            Invoke-WinUtilCloseRequest -RunningJob $startedMeanwhile -QueuedCount $sync.JobQueue.Count
            return
        }

        Write-WinUtilLog -Component "UI" -Message "Fechamento solicitado: fechando com $QueuedCount operação(ões) na fila descartada(s)."
        $sync.ForceClose = $true
        Request-WinUtilWindowClose
        return
    }

    $queuedNote = if ($QueuedCount -gt 0) { "`n$QueuedCount operação(ões) na fila serão descartadas.`n" } else { "" }

    # A pergunta carrega o significado em vez de nomear os botões: o Windows os rotula no idioma
    # dele, então "Yes" no texto não corresponderia a um botão escrito "Sim". O limite de minutos
    # informado é o padrão de Wait-WinUtilRemainingWork, então quem escolhe esperar sabe quando a
    # parada será solicitada de qualquer forma.
    $answer = Show-WinUtilJobCloseMessage -Button "YesNoCancel" -Icon "Warning" -Title "$RunningJob ainda está em execução" -Message @"
$RunningJob ainda não terminou.
$queuedNote
Fechar a janela e deixá-lo terminar no console?

O WinUtil sairá sozinho quando a tarefa terminar. Ele espera até 120
minutos e então solicita que a tarefa pare e sai. Se você optar por não
esperar, o WinUtil solicita a parada e fecha agora. Um instalador já em
execução pode continuar até retornar. Cancelar mantém o WinUtil aberto.
"@

    switch ("$answer") {
        "Yes" {
            Write-WinUtilLog -Component "UI" -Message "Fechamento solicitado: fechando a janela, $RunningJob continua no console."
            $sync.FinishInConsole = $true
            $sync.ForceClose = $true

            Write-Host ""
            Write-Host "A janela do WinUtil está fechada. $RunningJob ainda está em execução aqui, e esta janela fechará quando ele terminar." -ForegroundColor Cyan
            Write-Host ""

            # Postado em vez de fechado de dentro do manipulador que já está desenrolando
            Request-WinUtilWindowClose
        }
        "No" {
            Write-WinUtilLog -Component "UI" -Message "Fechamento solicitado: interrompendo $RunningJob."
            # O fim da tarefa não deve entregar sua vaga a uma tarefa da fila enquanto a janela fecha
            $null = Stop-WinUtilQueuedWork
            Step-WinUtilJob -Status "Interrompendo $RunningJob" -State "Indeterminate"
            $sync.ForceClose = $true

            # Fecha a janela primeiro. A thread principal cuida do encerramento do pool depois que
            # ShowDialog retorna, então o worker pode concluir seu bloco finally de despacho de UI
            # antes de o runspace da UI ser descartado. Esperar por ele aqui travaria o dispatcher.
            Request-WinUtilWindowClose
        }
        default {
            Write-WinUtilLog -Component "UI" -Message "Fechamento cancelado, $RunningJob ainda está em execução."
        }
    }
}

function Show-WinUtilJobCloseMessage {
    <#
        .SYNOPSIS
            Segura o trabalho enfileirado até o usuário responder qual trabalho pode sobreviver à janela
    #>
    param($Button, $Icon, $Title, $Message)

    [System.Threading.Monitor]::Enter($sync.SyncRoot)
    try {
        $alreadyOpen = [bool]$sync.JobClosePromptOpen
        $sync.JobClosePromptOpen = $true
    } finally {
        [System.Threading.Monitor]::Exit($sync.SyncRoot)
    }
    try {
        Show-WinUtilMessage @PSBoundParameters
    } finally {
        if (-not $alreadyOpen) {
            [System.Threading.Monitor]::Enter($sync.SyncRoot)
            try {
                $sync.JobClosePromptOpen = $false
                $resume = -not $sync.ActiveJob -and $sync.JobQueue.Count -gt 0
            } finally {
                [System.Threading.Monitor]::Exit($sync.SyncRoot)
            }
            if ($resume) {
                # O trabalho postado roda depois que o chamador aplica as flags de encerramento/console da resposta.
                Invoke-WPFUIThread -Async -ScriptBlock { Start-WinUtilNextQueuedJob }
            }
        }
    }
}

function Stop-WinUtilQueuedWork {
    <#
        .SYNOPSIS
            Impede a fila de entregar a vaga porque o WinUtil está prestes a fechar

        .DESCRIPTION
            Define a flag de encerramento que a fila respeita, descarta o que está enfileirado e
            encerra qualquer entrega, em um único passo sob o bloqueio, para que uma tarefa não
            comece no meio.

        .PARAMETER OnlyIfIdle
            Não faz nada e retorna o nome da tarefa em execução se uma tarefa ocupar a vaga. Caso
            contrário, retorna $null.
    #>
    param([switch]$OnlyIfIdle)

    [System.Threading.Monitor]::Enter($sync.SyncRoot)
    try {
        if ($OnlyIfIdle -and $sync.ActiveJob) {
            return $sync.ActiveJob
        }
        $sync.ShuttingDown = $true
        $null = Clear-WinUtilJobQueue
        $sync.JobHandoff = $false
        return $null
    } finally {
        [System.Threading.Monitor]::Exit($sync.SyncRoot)
    }
}

function Request-WinUtilWindowClose {
    <#
        .SYNOPSIS
            Fecha a janela de fora do manipulador que está cancelando o fechamento

    #>
    if (-not (Test-WinUtilUIAlive)) {
        return
    }

    $sync.Form.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, [action]{
        $sync.Form.Close()
    }) | Out-Null
}

function Wait-WinUtilRemainingWork {
    <#
        .SYNOPSIS
            Aguarda o trabalho que sobreviveu à janela, reportando no console

        .DESCRIPTION
            Roda na thread principal depois que a interface sumiu. A tarefa ainda está no pool de
            workers e continua registrando log, então isto apenas espera e mantém a espera visível.

        .PARAMETER TimeoutMinutes
            Limite superior, para que um worker que nunca retorna não mantenha o processo vivo.
    #>
    param(
        # Double em vez de int: um int truncaria silenciosamente um valor fracionário para zero, o
        # que transforma o limite em "não esperar de jeito nenhum"
        [double]$TimeoutMinutes = 120
    )

    if (-not $sync.FinishInConsole -or -not $sync.ActiveJob) {
        return
    }

    $job = $sync.ActiveJob
    Write-WinUtilLog -Component "UI" -Message "Janela fechada, aguardando $job terminar."
    Write-Host "Aguardando $job terminar..." -ForegroundColor Cyan

    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sync.ActiveJob -and $clock.Elapsed.TotalMinutes -lt $TimeoutMinutes) {
        Start-Sleep -Milliseconds 250
    }

    # A última linha de progresso da tarefa ainda está aberta, então o que vier depois precisa de uma linha nova
    Complete-WinUtilConsoleProgress

    if ($sync.ActiveJob) {
        Write-WinUtilLog -Level "WARN" -Component "UI" -Message "$job não terminou em $TimeoutMinutes minutos, saindo de qualquer forma."
        Write-Host "$job está demorando mais de $TimeoutMinutes minutos. Saindo." -ForegroundColor Yellow
        return
    }

    Write-WinUtilLog -Component "UI" -Message "$job terminou depois do fechamento da janela, em $([int]$clock.Elapsed.TotalSeconds)s."
    Write-Host "$job terminou. Fechando." -ForegroundColor Green
}
