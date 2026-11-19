function Start-WinUtilNextQueuedJob {
    <#
        .SYNOPSIS
            Inicia o job enfileirado mais antigo se o slot estiver livre

        .DESCRIPTION
            Roda na thread da interface, postado por Clear-WinUtilActiveJob quando um job termina
            com sucesso ou não. Até que o job iniciado tome o slot, $sync.JobHandoff
            mantém novas ações enfileiradas atrás dele, e toda saída daqui limpa a sinalização.
    #>
    if ($sync.ShuttingDown -or $sync.FinishInConsole) {
        Reset-WinUtilJobHandoff
        return
    }

    $next = $null
    [System.Threading.Monitor]::Enter($sync.SyncRoot)
    try {
        if ($sync.JobClosePromptOpen) { return }
        if (-not $sync.ActiveJob -and $sync.JobQueue.Count -gt 0) {
            $next = $sync.JobQueue[0]
            $sync.JobQueue.RemoveAt(0)
        } else {
            $sync.JobHandoff = $false
        }
    } finally {
        [System.Threading.Monitor]::Exit($sync.SyncRoot)
    }

    if ($null -eq $next) {
        Update-WinUtilJobQueueUI
        return
    }

    Write-WinUtilLog -Component $next.Name -Message "Iniciando o job enfileirado $($next.Name)."
    # FromQueue limpa a entrega no mesmo bloqueio que toma o slot, ou quando recusa
    Start-WinUtilJob -Name $next.Name -Description $next.Description -ScriptBlock ([scriptblock]::Create($next.ScriptBlock)) -Parameters $next.Parameters -DisableAppList:$next.DisableAppList -FromQueue
}

function Reset-WinUtilJobHandoff {
    <#
        .SYNOPSIS
            Permite que novas ações tomem o slot novamente após uma entrega que não se completará
    #>
    [System.Threading.Monitor]::Enter($sync.SyncRoot)
    try {
        $sync.JobHandoff = $false
    } finally {
        [System.Threading.Monitor]::Exit($sync.SyncRoot)
    }
}

function Get-WinUtilQueuedJobIndex {
    <#
        .SYNOPSIS
            Encontra um job enfileirado pelo Id, ou -1. O chamador detém o bloqueio SyncRoot.
    #>
    param([string]$Id)

    for ($index = 0; $index -lt $sync.JobQueue.Count; $index++) {
        if ($sync.JobQueue[$index].Id -eq $Id) {
            return $index
        }
    }
    return -1
}

function Move-WinUtilQueuedJob {
    <#
        .SYNOPSIS
            Move um job enfileirado uma posição antes ou depois, não fazendo nada em nenhuma extremidade

        .PARAMETER Id
            O Id do job enfileirado.

        .PARAMETER Direction
            Up executa mais cedo, Down mais tarde.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Id,

        [Parameter(Mandatory)]
        [ValidateSet("Up", "Down")]
        [string]$Direction
    )

    $moved = $null
    [System.Threading.Monitor]::Enter($sync.SyncRoot)
    try {
        $index = Get-WinUtilQueuedJobIndex -Id $Id
        $target = if ($Direction -eq "Up") { $index - 1 } else { $index + 1 }
        if ($index -ge 0 -and $target -ge 0 -and $target -lt $sync.JobQueue.Count) {
            $moved = $sync.JobQueue[$index]
            $sync.JobQueue.RemoveAt($index)
            $sync.JobQueue.Insert($target, $moved)
        }
    } finally {
        [System.Threading.Monitor]::Exit($sync.SyncRoot)
    }

    if ($moved) {
        Write-WinUtilLog -Component $moved.Name -Message "Movido o job enfileirado $($moved.Name) $($Direction.ToLower())."
        Update-WinUtilJobQueueUI
    }
}

function Remove-WinUtilQueuedJob {
    <#
        .SYNOPSIS
            Cancela um job enfileirado antes de ele iniciar

        .PARAMETER Id
            O Id do job enfileirado. Um job que já iniciou não está na fila.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Id
    )

    $removed = $null
    [System.Threading.Monitor]::Enter($sync.SyncRoot)
    try {
        $index = Get-WinUtilQueuedJobIndex -Id $Id
        if ($index -ge 0) {
            $removed = $sync.JobQueue[$index]
            $sync.JobQueue.RemoveAt($index)
        }
    } finally {
        [System.Threading.Monitor]::Exit($sync.SyncRoot)
    }

    if ($removed) {
        Write-WinUtilLog -Component $removed.Name -Message "Cancelado o job enfileirado $($removed.Name)."
        Update-WinUtilJobQueueUI
    }
}

function Clear-WinUtilJobQueue {
    <#
        .SYNOPSIS
            Descarta todos os jobs enfileirados e retorna quantos foram descartados

        .DESCRIPTION
            Para o fechamento da janela: nada enfileirado pode iniciar depois que ela se foi.
    #>
    $dropped = 0
    [System.Threading.Monitor]::Enter($sync.SyncRoot)
    try {
        $dropped = $sync.JobQueue.Count
        $sync.JobQueue.Clear()
    } finally {
        [System.Threading.Monitor]::Exit($sync.SyncRoot)
    }

    if ($dropped -gt 0) {
        Write-WinUtilLog -Component "UI" -Message "Descartados $dropped job(s) enfileirado(s) porque a janela está fechando."
    }
    return $dropped
}

function Update-WinUtilJobQueueUI {
    <#
        .SYNOPSIS
            Mostra o botão da fila enquanto algo roda ou espera, e reconstrói a lista suspensa aberta

        .DESCRIPTION
            Somente na thread da interface. Outras threads a postam por meio de Invoke-WPFUIThread.
    #>
    if ($null -eq $sync.JobQueueButton) {
        return
    }

    # Uma cópia, para que as linhas sejam construídas sem manter o bloqueio que os workers precisam
    [System.Threading.Monitor]::Enter($sync.SyncRoot)
    try {
        $queued = $sync.JobQueue.ToArray()
        $running = $sync.ActiveJob
    } finally {
        [System.Threading.Monitor]::Exit($sync.SyncRoot)
    }

    $busy = $running -or $queued.Count -gt 0
    $sync.JobQueueButton.Visibility = if ($busy) { "Visible" } else { "Collapsed" }
    $sync.JobQueueCount.Text = if ($queued.Count -gt 0) { [string]$queued.Count } else { "" }

    if (-not $busy) {
        $sync.JobQueuePopup.IsOpen = $false
    }
    if (-not $sync.JobQueuePopup.IsOpen) {
        return
    }

    $sync.JobQueueRunning.Text = if ($running) { "Em execução: $running" } else { "Nada em execução" }
    $sync.JobQueueItems.Children.Clear()

    for ($index = 0; $index -lt $queued.Count; $index++) {
        $row = New-Object Windows.Controls.Grid
        $row.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{Width = "*"}))
        for ($column = 0; $column -lt 3; $column++) {
            $row.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{Width = "30"}))
        }

        # Cortado com uma dica porque a lista suspensa tem largura fixa
        $label = New-Object Windows.Controls.TextBlock
        $label.Text = $queued[$index].Name
        $label.ToolTip = $queued[$index].Name
        $label.TextTrimming = "CharacterEllipsis"
        $label.VerticalAlignment = "Center"
        $label.Margin = "5,0,5,0"
        $label.SetResourceReference([Windows.Controls.TextBlock]::FontSizeProperty, "ButtonFontSize")
        $label.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, "MainForegroundColor")
        $row.Children.Add($label) | Out-Null

        $column = 1
        foreach ($action in @(
            @{ Glyph = 0xE70E; Tip = "Executar antes"; Enabled = $index -gt 0; Click = { Move-WinUtilQueuedJob -Id $this.Tag -Direction Up } },
            @{ Glyph = 0xE70D; Tip = "Executar depois"; Enabled = $index -lt ($queued.Count - 1); Click = { Move-WinUtilQueuedJob -Id $this.Tag -Direction Down } },
            @{ Glyph = 0xE711; Tip = "Cancelar"; Enabled = $true; Click = { Remove-WinUtilQueuedJob -Id $this.Tag } }
        )) {
            $button = New-Object Windows.Controls.Button
            $button.FontFamily = "Segoe MDL2 Assets"
            $button.Content = [string][char]$action.Glyph
            $button.ToolTip = $action.Tip
            [Windows.Automation.AutomationProperties]::SetName($button, "$($action.Tip): $($queued[$index].Name)")
            $button.Tag = $queued[$index].Id
            $button.IsEnabled = $action.Enabled
            $button.Opacity = if ($action.Enabled) { 1 } else { 0.3 }
            $button.SetResourceReference([Windows.Controls.Control]::ForegroundProperty, "MainForegroundColor")
            $button.SetResourceReference([Windows.Controls.Control]::StyleProperty, "HoverButtonStyle")
            $button.Add_Click($action.Click)
            [System.Windows.Controls.Grid]::SetColumn($button, $column++)
            $row.Children.Add($button) | Out-Null
        }

        $sync.JobQueueItems.Children.Add($row) | Out-Null
    }
}
