function Install-WinUtilProgramChoco {
    <#

    .SYNOPSIS
        Instala, atualiza ou desinstala pacotes com o Chocolatey e reporta cada resultado

    .DESCRIPTION
        Um pacote por chamada ao choco, para que a barra de progresso avance pela lista e uma falha
        identifique o pacote que falhou em vez do lote inteiro. A saída do próprio choco vai para o
        log em vez do console, do mesmo modo que o caminho do WinGet reporta.

    .PARAMETER Action
        Install, Upgrade ou Uninstall.

    .PARAMETER Programs
        Os nomes dos pacotes. Para Upgrade, a entrada única "all" atualiza tudo.

    .PARAMETER ProgressBase
        Onde esta chamada começa dentro da barra de progresso geral da tarefa.

    .PARAMETER ProgressSpan
        Quanto da barra geral estes pacotes representam. Zero não reporta nada.

    #>
    param (
        [Parameter(Mandatory=$true)]
        [ValidateSet("Install", "Uninstall", "Upgrade")]
        [string]$Action,

        [Parameter(Mandatory=$true)]
        [string[]]$Programs,

        [int]$ProgressBase = 0,

        [int]$ProgressSpan = 0
    )

    # O Chocolatey reporta "nada precisava ser feito" e "funcionou, agora reinicie" por códigos de saída
    # em vez de como falhas
    $rebootCodes = @{
        1641 = "instalado, o instalador iniciou uma reinicialização"
        3010 = "instalado, é preciso reiniciar para concluir"
    }
    $nothingToDo = @{
        2 = "nada a fazer"
    }
    $verb = $Action.ToLowerInvariant()
    $chocoAvailable = $null -ne (Get-Command choco -ErrorAction SilentlyContinue)

    $packages = @($Programs | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $total = $packages.Count
    $index = 0

    foreach ($program in $packages) {
        $index++
        if ($ProgressSpan -gt 0 -and $total -gt 0) {
            $percent = $ProgressBase + [int]((($index - 1) / $total) * $ProgressSpan)
            Step-WinUtilJob -Status "$Action $program ($index/$total)" -Percent $percent
        }

        Write-WinUtilLog -Component "Package" -Message "Pacote choco ($Action): $program"

        # --no-progress evita que o choco redesenhe uma linha de porcentagem que só faz sentido em um
        # console que ninguém está observando
        $arguments = @($verb, $program, "-y", "--no-progress")
        # Cada runspace de trabalho tem seu próprio escopo global. Redefina ali o resultado do comando
        # nativo para que "comando não encontrado" não herde um código bem-sucedido do trabalho anterior no mesmo pool.
        $global:LASTEXITCODE = $null
        if (-not $chocoAvailable) {
            $output = "O Chocolatey não está instalado ou não está disponível no PATH."
            $exitCode = -1
        } else {
            $output = & choco @arguments 2>&1
            $exitCode = if ($null -eq $global:LASTEXITCODE) { -1 } else { [int]$global:LASTEXITCODE }
        }

        if ($exitCode -eq 0) {
            $outcome = "Succeeded"
            $detail = "código de saída 0"
        } elseif ($rebootCodes.ContainsKey($exitCode)) {
            $outcome = "Succeeded"
            $detail = $rebootCodes[$exitCode]
        } elseif ($nothingToDo.ContainsKey($exitCode)) {
            $outcome = "Skipped"
            $detail = $nothingToDo[$exitCode]
        } else {
            $outcome = "Failed"
            $detail = if ($exitCode -eq -1) { "O comando do Chocolatey não iniciou" } else { "código de saída $exitCode" }
        }

        $level = if ($outcome -eq "Failed") { "ERROR" } else { "INFO" }
        Write-WinUtilLog -Level $level -Component "Package" -Message "Pacote choco ($Action) $($outcome.ToLowerInvariant()): $program ($detail)"

        if ($outcome -eq "Failed") {
            # O motivo está em algum lugar da saída do choco, e sem ele o log diz apenas que
            # um número retornou
            foreach ($line in @($output | Select-Object -Last 15)) {
                $text = ([string]$line).Trim()
                if ($text) { Write-WinUtilLog -Level "WARN" -Component "Package" -Detail -Message $text }
            }
        }

        if ($ProgressSpan -gt 0 -and $total -gt 0) {
            Step-WinUtilJob -Status "$Action $program ($index/$total)" -Percent ($ProgressBase + [int](($index / $total) * $ProgressSpan))
        }

        [pscustomobject]@{
            Package = $program
            Manager = "choco"
            Action = $Action
            ExitCode = $exitCode
            Outcome = $outcome
            Detail = $detail
        }
    }
}
