function Write-WinUtilConsoleProgress {
    <#
        .SYNOPSIS
            Relata o progresso do job no console para execuções que não têm janela

        .DESCRIPTION
            A barra de progresso é a única coisa que informa ao usuário o quanto um job avançou,
            então uma execução sem interface precisa da mesma informação no único lugar que tem.

            No console, a linha é reescrita no mesmo lugar, porque um pacote que relata a cada
            poucas centenas de milissegundos acabaria rolando uma tela inteira para uma única
            instalação. Quando a saída é redirecionada, não há cursor para mover, então cada
            atualização é sua própria linha e elas são fortemente limitadas.
    #>
    param(
        [string]$Status,
        [int]$Percent = -1
    )

    if ([string]::IsNullOrWhiteSpace($Status) -and $Percent -lt 0) {
        return
    }

    if ($null -eq $sync.ConsoleProgressState) {
        $sync.ConsoleProgressState = [hashtable]::Synchronized(@{
            LastText = ""
            LastWrite = [datetime]::MinValue
            LineLength = 0
            LineOpen = $false
        })
    }
    $state = $sync.ConsoleProgressState

    $text = if ([string]::IsNullOrWhiteSpace($Status)) { $state.LastText } else { $Status }
    if ([string]::IsNullOrWhiteSpace($text)) {
        return
    }

    $redirected = [Console]::IsOutputRedirected
    $throttleMs = if ($redirected) { 1000 } else { 150 }

    $now = Get-Date
    $sinceLast = ($now - $state.LastWrite).TotalMilliseconds

    # A saída redirecionada não pode ser reescrita no mesmo lugar, então cada atualização é sua
    # própria linha e o limite se aplica mesmo quando o texto mudou. Um job que reporta por pacote
    # acabaria rolando uma tela inteira.
    if ($redirected) {
        if ($sinceLast -lt $throttleMs) { return }
    } elseif ($text -eq $state.LastText -and $sinceLast -lt $throttleMs) {
        return
    }

    $state.LastText = $text
    $state.LastWrite = $now

    $prefix = if ($Percent -ge 0) { "[{0,3}%] " -f $Percent } else { "[   =] " }
    $line = "$prefix$text"

    if ($redirected) {
        Write-WinUtilHost $line -ForegroundColor DarkCyan
        return
    }

    # Preenche até o comprimento anterior para que uma linha mais curta não deixe o final da mais longa
    $padding = [Math]::Max(0, $state.LineLength - $line.Length)
    Write-WinUtilHost ("`r$line" + (" " * $padding)) -NoNewline -ForegroundColor DarkCyan
    $state.LineLength = $line.Length
    $state.LineOpen = $true
}

function Complete-WinUtilConsoleProgress {
    <#
        .SYNOPSIS
            Encerra a linha de progresso para que a próxima coisa impressa comece em sua própria linha

        .DESCRIPTION
            A linha é reescrita no mesmo lugar e, portanto, fica sem quebra de linha. Qualquer outra
            coisa que chegue ao console precisa fechá-la primeiro, ou cairá sobre o progresso.
    #>

    $state = $sync.ConsoleProgressState
    if ($null -eq $state -or -not $state.LineOpen) {
        return
    }

    Write-WinUtilHost ""
    $state.LineOpen = $false
    $state.LineLength = 0
    $state.LastText = ""
}
