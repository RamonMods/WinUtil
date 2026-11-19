function Measure-WinUtilStep {
    <#
        .SYNOPSIS
            Cronometra uma etapa de um pipeline e a registra para o resumo de tempos

        .DESCRIPTION
            A saída passa intacta, portanto isso pode envolver uma expressão existente sem
            alterar o que o chamador recebe. Cada etapa é registrada como uma linha "timing:" e mantida
            em $sync.StepTimings para que o resumo a ordene.

        .PARAMETER Name
            O que a etapa é, como deve aparecer no log.

        .PARAMETER ScriptBlock
            O trabalho a cronometrar.

        .PARAMETER Scope
            Agrupa etapas pertencentes à mesma execução, normalmente um nome de job ou "UI".
    #>
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,

        [Parameter(Mandatory, Position = 1)]
        [scriptblock]$ScriptBlock,

        [string]$Scope = "WinUtil"
    )

    $isUIDiagnostic = $Scope -in @("UI", "Tab")
    $captureTiming = -not $isUIDiagnostic -or $sync.IsLocalCompile
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        & $ScriptBlock
    } finally {
        $stopwatch.Stop()

        if ($captureTiming -and $null -ne $sync.StepTimings) {
            $null = $sync.StepTimings.Add([pscustomobject]@{
                Scope = $Scope
                Step = $Name
                Milliseconds = $stopwatch.ElapsedMilliseconds
            })
        }

        if ($captureTiming) {
            $level = if ($isUIDiagnostic) { "DEBUG" } else { "INFO" }
            Write-WinUtilLog -Level $level -Component $Scope -Message "timing: $Name levou $($stopwatch.ElapsedMilliseconds) ms"
        }
    }
}

function Write-WinUtilTimingSummary {
    <#
        .SYNOPSIS
            Registra no log as etapas mais lentas de um escopo, para que o log responda "o que demorou tanto"

        .PARAMETER Scope
            Qual grupo de etapas deve ser relatado.

        .PARAMETER Top
            Quantas das etapas mais lentas devem ser listadas.

        .PARAMETER TotalMilliseconds
            Total em tempo real. Sem ele, o resumo soma as etapas, omitindo o que aconteceu
            entre elas.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Scope,

        [int]$Top = 5,

        [long]$TotalMilliseconds = -1,

        [int]$StartIndex = 0
    )

    $isUIDiagnostic = $Scope -in @("UI", "Tab")
    if (($isUIDiagnostic -and -not $sync.IsLocalCompile) -or $null -eq $sync.StepTimings) {
        return
    }

    [System.Threading.Monitor]::Enter($sync.StepTimings.SyncRoot)
    try {
        $timingSnapshot = @($sync.StepTimings.ToArray())
    } finally {
        [System.Threading.Monitor]::Exit($sync.StepTimings.SyncRoot)
    }

    $steps = @($timingSnapshot | Select-Object -Skip $StartIndex | Where-Object { $_.Scope -eq $Scope })
    if ($steps.Count -eq 0) {
        return
    }

    $measured = ($steps | Measure-Object -Property Milliseconds -Sum).Sum
    $total = if ($TotalMilliseconds -ge 0) { $TotalMilliseconds } else { $measured }

    $level = if ($isUIDiagnostic) { "DEBUG" } else { "INFO" }
    Write-WinUtilLog -Level $level -Component $Scope -Message "timing summary: $($steps.Count) etapa(s), $measured ms medidos de $total ms no total"
    foreach ($step in ($steps | Sort-Object Milliseconds -Descending | Select-Object -First $Top)) {
        $share = if ($total -gt 0) { [int](($step.Milliseconds / $total) * 100) } else { 0 }
        Write-WinUtilLog -Level $level -Component $Scope -Message "timing summary:   $($step.Milliseconds) ms ($share%)  $($step.Step)"
    }
}
