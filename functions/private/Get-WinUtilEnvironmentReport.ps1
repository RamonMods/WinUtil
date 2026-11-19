function Get-WinUtilEnvironmentReport {
    <#
    .SYNOPSIS
        Coleta os dados permitidos usados pelo relatório de ambiente do WinUtil.
    #>

    $reportWarnings = [System.Collections.Generic.List[string]]::new()

    $windows = [ordered]@{
        edition      = $null
        version      = $null
        buildNumber  = $null
        architecture = $null
    }
    $hardware = [ordered]@{
        cpuModel              = $null
        logicalProcessorCount = $null
        totalMemoryGB         = $null
    }

    try {
        $operatingSystem = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $windows.edition = $operatingSystem.Caption
        $windows.version = $operatingSystem.Version
        $windows.buildNumber = $operatingSystem.BuildNumber
        $windows.architecture = $operatingSystem.OSArchitecture

        if ($null -ne $operatingSystem.TotalVisibleMemorySize) {
            $hardware.totalMemoryGB = [math]::Round(([double]$operatingSystem.TotalVisibleMemorySize / 1MB), 2)
        }
    } catch {
        $message = "Falha ao coletar informações do Windows/memória de Win32_OperatingSystem: $($_.Exception.Message)"
        Write-WinUtilLog -Component "EnvironmentReport" -Level "WARN" -Message $message
        [void]$reportWarnings.Add($message)
    }

    try {
        $processors = @(Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop)
        if ($processors.Count -gt 0) {
            $hardware.cpuModel = $processors[0].Name
            $hardware.logicalProcessorCount = [int](($processors | Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum)
        }
    } catch {
        $message = "Falha ao coletar informações da CPU de Win32_Processor: $($_.Exception.Message)"
        Write-WinUtilLog -Component "EnvironmentReport" -Level "WARN" -Message $message
        [void]$reportWarnings.Add($message)
    }

    $powershell = [ordered]@{
        edition         = $PSVersionTable.PSEdition
        version         = $PSVersionTable.PSVersion.ToString()
        executionPolicy = $null
    }

    try {
        $powershell.executionPolicy = (Get-ExecutionPolicy).ToString()
    } catch {
        $message = "Falha ao ler a política de execução do PowerShell: $($_.Exception.Message)"
        Write-WinUtilLog -Component "EnvironmentReport" -Level "WARN" -Message $message
        [void]$reportWarnings.Add($message)
    }

    # Reutiliza a funcionalidade embutida
    $chocolatey = [ordered]@{ installed = $false; version = $null }
    try {
        $chocolatey.installed = (Test-WinUtilPackageManager -choco 6>$null) -eq "installed"
    } catch {
        $message = "Falha ao verificar a disponibilidade do Chocolatey: $($_.Exception.Message)"
        Write-WinUtilLog -Component "EnvironmentReport" -Level "WARN" -Message $message
        [void]$reportWarnings.Add($message)
    }

    if ($chocolatey.installed) {
        try {
            $global:LASTEXITCODE = 0
            $versionOutput = @(choco -v 2>&1)
            if ($LASTEXITCODE -ne 0) {
                throw "A sondagem da versão do Chocolatey terminou com o código $LASTEXITCODE."
            }
            $chocolatey.version = ($versionOutput | Select-Object -First 1).ToString().Trim()
        } catch {
            $message = "Falha ao ler a versão do Chocolatey: $($_.Exception.Message)"
            Write-WinUtilLog -Component "EnvironmentReport" -Level "WARN" -Message $message
            [void]$reportWarnings.Add($message)
        }
    }

    $winget = [ordered]@{ installed = $false; version = $null }
    try {
        $winget.installed = (Test-WinUtilPackageManager -winget 6>$null) -eq "installed"
    } catch {
        $message = "Falha ao verificar a disponibilidade do WinGet: $($_.Exception.Message)"
        Write-WinUtilLog -Component "EnvironmentReport" -Level "WARN" -Message $message
        [void]$reportWarnings.Add($message)
    }

    if ($winget.installed) {
        try {
            $global:LASTEXITCODE = 0
            $versionOutput = @(winget -v 2>&1)
            if ($LASTEXITCODE -ne 0) {
                throw "A sondagem da versão do WinGet terminou com o código $LASTEXITCODE."
            }
            $winget.version = ($versionOutput | Select-Object -First 1).ToString().Trim()
        } catch {
            $message = "Falha ao ler a versão do WinGet: $($_.Exception.Message)"
            Write-WinUtilLog -Component "EnvironmentReport" -Level "WARN" -Message $message
            [void]$reportWarnings.Add($message)
        }
    }

    # Nulo significa que o estado do registro não pôde ser lido. Não transforme uma falha de acesso
    # ou do provedor em um resultado enganoso de "nenhuma reinicialização necessária".
    $system = [ordered]@{ pendingRebootRequired = $null }
    try {
        $rebootPaths = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending",
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"
        )

        # Um valor PendingFileRenameOperations presente, mas vazio, ainda retorna um objeto não nulo, então
        # verifique as entradas de verdade em vez de apenas a existência da propriedade.
        $pendingFileRenameOperations = @(
            (Get-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" `
                -ErrorAction Stop).PendingFileRenameOperations |
                Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
        )
        $system.pendingRebootRequired = ($rebootPaths | Where-Object {
            Test-Path -LiteralPath $_ -ErrorAction Stop
        }).Count -gt 0 -or
            $pendingFileRenameOperations.Count -gt 0
    } catch {
        $message = "Falha ao verificar o estado de reinicialização pendente no registro: $($_.Exception.Message)"
        Write-WinUtilLog -Component "EnvironmentReport" -Level "WARN" -Message $message
        [void]$reportWarnings.Add($message)
    }

    $tweaksState = Get-WinUtilTweaksStateReport
    if ($tweaksState.collectionStatus -ne "collected") {
        $message = "Falha ao coletar o estado completo dos ajustes para o relatório de ambiente."
        Write-WinUtilLog -Component "EnvironmentReport" -Level "WARN" -Message $message
        [void]$reportWarnings.Add($message)
    }

    foreach ($message in $reportWarnings) {
        Write-Warning $message
    }

    return [pscustomobject][ordered]@{
        schemaVersion    = "1.0"
        generatedAtUtc   = [DateTime]::UtcNow.ToString("o")
        windows          = [pscustomobject]$windows
        hardware         = [pscustomobject]$hardware
        powershell       = [pscustomobject]$powershell
        packageManagers  = [pscustomobject][ordered]@{
            winget     = [pscustomobject]$winget
            chocolatey = [pscustomobject]$chocolatey
        }
        system           = [pscustomobject]$system
        tweaksState      = $tweaksState
    }
}
