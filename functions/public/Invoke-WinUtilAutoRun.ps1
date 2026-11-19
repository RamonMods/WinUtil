function Invoke-WinUtilAutoRun {
    <#

    .SYNOPSIS
        Executa cada ação selecionada até o fim sem janela

    .DESCRIPTION
        O caminho sem interface. Cada ação é o mesmo trabalho que o botão iniciaria, executado
        uma por vez porque a camada de jobs permite apenas um por vez, e aguardado até que o
        worker limpe o sinalizador de ocupado.

        Retorna um resumo do que foi executado para que quem chamou possa decidir o código de
        saída. Nada aqui toca a interface, então o comportamento é o mesmo com ou sem janela.

    .PARAMETER StopTimeoutSeconds
        Quanto tempo uma etapa que estourou o tempo recebe para parar antes de a execução
        desistir do restante.

    .PARAMETER StepTimeoutSeconds
        Quanto tempo uma única ação pode levar antes de a execução desistir dela. Sem um teto,
        um instalador esperando por algo que nunca vai chegar trava a execução de vez.

    #>
    param(
        [int]$StepTimeoutSeconds = 3600,

        [int]$StopTimeoutSeconds = 30
    )

    $steps = @(
        [pscustomobject]@{ Name = "Tweaks";          Count = @($sync.selectedTweaks).Count;   Action = { Invoke-WPFtweaksbutton } }
        [pscustomobject]@{ Name = "Toggles";         Count = @($sync.selectedToggles).Count;  Action = { Invoke-WPFToggleSelections } }
        [pscustomobject]@{ Name = "Features";        Count = @($sync.selectedFeatures).Count; Action = { Invoke-WPFFeatureInstall } }
        [pscustomobject]@{ Name = "Applications";    Count = @($sync.selectedApps).Count;     Action = { Invoke-WPFInstall } }
        [pscustomobject]@{ Name = "AppX removal";    Count = @($sync.selectedAppx).Count;     Action = { Invoke-WPFAppxRemoval } }
    )

    $planned = @($steps | Where-Object { $_.Count -gt 0 })
    if ($planned.Count -eq 0) {
        Write-WinUtilLog -Level "WARN" -Component "AutoRun" -Message "Nada foi selecionado, então não há nada a fazer."
        return [pscustomobject]@{ Steps = @(); Failed = 0; TimedOut = 0; Errors = 0; Warnings = 0 }
    }

    Write-WinUtilLog -Component "AutoRun" -Message "Iniciando execução sem interface: $(($planned | ForEach-Object { "$($_.Name) ($($_.Count))" }) -join ', ')"

    $results = New-Object System.Collections.ArrayList
    $runClock = [System.Diagnostics.Stopwatch]::StartNew()

    foreach ($step in $planned) {
        $errorsBefore = if ($sync.LoggedErrors) { $sync.LoggedErrors.Count } else { 0 }
        $sync.LastJobResult = $null
        $stepClock = [System.Diagnostics.Stopwatch]::StartNew()
        $timedOut = $false

        Write-WinUtilLog -Component "AutoRun" -Message "$($step.Name): iniciando $($step.Count) item(ns)."

        try {
            & $step.Action
        } catch {
            Write-WinUtilErrorRecord -ErrorRecord $_ -Component "AutoRun" -Context "Iniciando $($step.Name)"
        }

        # A ação inicia um job e retorna; a execução termina quando o worker limpa o sinalizador
        while ($sync.ActiveJob) {
            if ($stepClock.Elapsed.TotalSeconds -ge $StepTimeoutSeconds) {
                $timedOut = $true
                Write-WinUtilLog -Level "ERROR" -Component "AutoRun" -Message "$($step.Name) não terminou em $StepTimeoutSeconds segundos, seguindo adiante."
                break
            }
            Start-Sleep -Milliseconds 200
        }

        $stepClock.Stop()
        $newErrors = if ($sync.LoggedErrors) { $sync.LoggedErrors.Count - $errorsBefore } else { 0 }
        $newWarnings = if ($null -ne $sync.LastJobResult) { [int]$sync.LastJobResult.Warnings } else { 0 }

        $null = $results.Add([pscustomobject]@{
            Name = $step.Name
            Items = $step.Count
            Seconds = [int]$stepClock.Elapsed.TotalSeconds
            Errors = $newErrors
            Warnings = $newWarnings
            TimedOut = $timedOut
        })

        $outcome = if ($timedOut) { "timed out" } elseif ($newErrors -gt 0) { "finished with $newErrors error(s)" } elseif ($newWarnings -gt 0) { "finished with $newWarnings warning(s)" } else { "finished" }
        Write-WinUtilLog -Component "AutoRun" -Message "$($step.Name): $outcome after $([int]$stepClock.Elapsed.TotalSeconds)s."

        if ($timedOut) {
            # The worker is still on the pool. Clearing the slot on its own would let the next
            # step start beside it, so two runs would be changing the machine at once.
            Stop-WinUtilActiveWork -NoWait | Out-Null

            $stopDeadline = (Get-Date).AddSeconds($StopTimeoutSeconds)
            while ((Test-WinUtilActiveWorkRunning) -and (Get-Date) -lt $stopDeadline) {
                Start-Sleep -Milliseconds 200
            }

            # A job that never cleared the flag would make every later step refuse to start
            $null = Clear-WinUtilActiveJob

            if (Test-WinUtilActiveWorkRunning) {
                Write-WinUtilLog -Level "ERROR" -Component "AutoRun" -Message "$($step.Name) could not be stopped, so the remaining steps are abandoned rather than run beside it."
                break
            }
        }
    }

    $runClock.Stop()
    Write-WinUtilTimingSummary -Scope "AutoRun" -TotalMilliseconds $runClock.ElapsedMilliseconds

    return [pscustomobject]@{
        Steps = @($results)
        Failed = @($results | Where-Object { $_.Errors -gt 0 }).Count
        TimedOut = @($results | Where-Object { $_.TimedOut }).Count
        Errors = (@($results | Measure-Object -Property Errors -Sum).Sum)
        Warnings = (@($results | Measure-Object -Property Warnings -Sum).Sum)
    }
}

function Write-WinUtilAutoRunSummary {
    <#
        .SYNOPSIS
            Prints what a headless run did and returns the exit code it should end with
    #>
    param(
        [Parameter(Mandatory)]
        $Summary
    )

    Write-Host ""
    Write-Host "=== WinUtil headless run ===" -ForegroundColor Cyan

    foreach ($step in @($Summary.Steps)) {
        $state = if ($step.TimedOut) { "TIMED OUT" } elseif ($step.Errors -gt 0) { "$($step.Errors) error(s)" } elseif ($step.Warnings -gt 0) { "$($step.Warnings) warning(s)" } else { "ok" }
        $colour = if ($step.TimedOut -or $step.Errors -gt 0 -or $step.Warnings -gt 0) { "Yellow" } else { "Green" }
        Write-Host ("  {0,-14} {1,3} item(s)  {2,5}s  {3}" -f $step.Name, $step.Items, $step.Seconds, $state) -ForegroundColor $colour
    }

    if (@($Summary.Steps).Count -eq 0) {
        Write-Host "  nothing was selected" -ForegroundColor Yellow
        Write-Host ""
        return 2
    }

    if ($Summary.TimedOut -gt 0 -or $Summary.Failed -gt 0) {
        Write-Host ""
        Write-Host "Finished with problems. See $($sync.logPath)" -ForegroundColor Yellow
        Write-Host ""
        return 1
    }

    if ($Summary.Warnings -gt 0) {
        Write-Host ""
        Write-Host "Completed with warnings. See $($sync.logPath)" -ForegroundColor Yellow
        Write-Host ""
        return 0
    }

    Write-Host ""
    Write-Host "All steps completed. Log: $($sync.logPath)" -ForegroundColor Green
    Write-Host ""
    return 0
}
