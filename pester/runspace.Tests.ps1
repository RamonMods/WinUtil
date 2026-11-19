#===========================================================================
# Testes - Comportamento do runspace

BeforeAll {
    $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
    . (Join-Path $script:repoRoot "functions\private\Get-WinUtilRunspacePoolLock.ps1")
    . (Join-Path $script:repoRoot "functions\private\Close-WinUtilRunspacePool.ps1")
    . (Join-Path $script:repoRoot "functions\private\Stop-WinUtilActiveWork.ps1")
    . (Join-Path $script:repoRoot "functions\private\Initialize-WinUtilRunspacePool.ps1")
    . (Join-Path $script:repoRoot "functions\private\Register-WinUtilRunspaceCleanup.ps1")
        . (Join-Path $script:repoRoot "functions\public\Invoke-WPFRunspace.ps1")
    function Write-WinUtilLog { }
    function Start-WinUtilJob {
        param([string]$Name, [scriptblock]$ScriptBlock, [hashtable]$Parameters, [string]$Description, [switch]$DisableAppList)
    }
    function Show-WinUtilMessage {
        param($Message, $Title, $Button, $Icon)
    }
    . (Join-Path $script:repoRoot "functions\public\Invoke-WPFFeatureInstall.ps1")
    . (Join-Path $script:repoRoot "functions\public\Invoke-WPFAppxRemoval.ps1")
    . (Join-Path $script:repoRoot "functions\public\Invoke-WPFundoall.ps1")

    function script:New-WinUtilRunspaceTestContext {
        param([hashtable]$InitialSync = @{})

        $script:sync = [Hashtable]::Synchronized($InitialSync)
        $initialSessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
        $syncVariable = New-Object System.Management.Automation.Runspaces.SessionStateVariableEntry -ArgumentList "sync", $script:sync, $null
        $initialSessionState.Variables.Add($syncVariable)
        $script:sync.runspace = [runspacefactory]::CreateRunspacePool(1, 2, $initialSessionState, $Host)
        $script:sync.runspace.Open()
    }

    function script:Clear-WinUtilRunspaceTestContext {
        if ($script:sync -and $script:sync.runspace) {
            $script:sync.runspace.Close()
            $script:sync.runspace.Dispose()
        }

        Remove-Variable -Name sync -Scope Script -ErrorAction SilentlyContinue
    }

    function script:Assert-WinUtilAsyncHandle {
        param($Handle)

        ($Handle -is [System.IAsyncResult]) | Should -BeTrue
        ($Handle -is [array]) | Should -BeFalse
        $Handle.AsyncWaitHandle.WaitOne(5000) | Should -BeTrue
    }
}

Describe "Comportamento de Invoke-WPFRunspace" {
    BeforeEach {
        New-WinUtilRunspaceTestContext -InitialSync @{ Marker = "shared" }
    }

    AfterEach {
        Clear-WinUtilRunspaceTestContext
    }

    It "retorna um único handle assíncrono sem lista de argumentos" {
        $script:sync.Result = $null

        $handle = Invoke-WPFRunspace -ScriptBlock {
            Start-Sleep -Milliseconds 100
            $sync.Result = "no-args|$($sync.Marker)"
        }

        Assert-WinUtilAsyncHandle -Handle $handle
        $script:sync.Result | Should -Be "no-args|shared"
    }

    It "recusa trabalho quando o desligamento ganha o bloqueio do ciclo de vida antes de existir um pool" {
        $script:sync.runspace.Close()
        $script:sync.runspace.Dispose()
        $script:sync.Remove("runspace")

        $poolLock = Get-WinUtilRunspacePoolLock
        $lockRequested = [System.Threading.ManualResetEventSlim]::new($false)
        $poolInitializationEntered = [System.Threading.ManualResetEventSlim]::new($false)
        $caller = [powershell]::Create()
        [void]$caller.AddScript({
            param($SharedSync, $RepoRoot, $PoolLock, $LockRequested, $PoolInitializationEntered)

            $script:sync = $SharedSync
            function Write-WinUtilLog { }
            function Get-WinUtilRunspacePoolLock {
                $LockRequested.Set()
                return $PoolLock
            }
            function Initialize-WinUtilRunspacePool {
                $PoolInitializationEntered.Set()
            }
            . (Join-Path $RepoRoot "functions\public\Invoke-WPFRunspace.ps1")
            $workHandle = Invoke-WPFRunspace -ScriptBlock { }
            [pscustomobject]@{ Scheduled = $null -ne $workHandle }
        }).AddArgument($script:sync).AddArgument($script:repoRoot).AddArgument($poolLock).AddArgument($lockRequested).AddArgument($poolInitializationEntered)

        [System.Threading.Monitor]::Enter($poolLock)
        try {
            $callerHandle = $caller.BeginInvoke()
            $lockRequested.Wait(5000) | Should -BeTrue
            $poolInitializationEntered.Wait(100) | Should -BeFalse
            $callerHandle.IsCompleted | Should -BeFalse
            Close-WinUtilRunspacePool
        } finally {
            [System.Threading.Monitor]::Exit($poolLock)
        }

        try {
            $callerHandle.AsyncWaitHandle.WaitOne(5000) | Should -BeTrue
            $callerResult = @($caller.EndInvoke($callerHandle))
            $callerResult.Count | Should -Be 1
            $callerResult[0].Scheduled | Should -BeFalse
            $poolInitializationEntered.IsSet | Should -BeFalse
        } finally {
            $caller.Dispose()
            $lockRequested.Dispose()
            $poolInitializationEntered.Dispose()
        }
    }

    It "registra o trabalho iniciado antes que o desligamento possa fechar o pool" {
        $handle = Invoke-WPFRunspace -ScriptBlock {
            Start-Sleep -Seconds 5
        }

        $handle | Should -Not -BeNullOrEmpty
        @(Get-WinUtilActiveShell).Count | Should -Be 1

        Close-WinUtilRunspacePool -StopTimeoutSeconds 5

        $script:sync.ShuttingDown | Should -BeTrue
        $script:sync.ContainsKey("runspace") | Should -BeFalse
    }

    It "preserva a propriedade e permite que o trabalho iniciado termine quando o registro de limpeza falha" {
        $workStarted = [System.Threading.ManualResetEventSlim]::new($false)
        $script:sync.WorkStarted = $workStarted
        $script:sync.WorkFinished = $false
        Mock Register-WinUtilRunspaceCleanup {
            $script:sync.WorkStarted.Wait(5000) | Out-Null
            throw "cleanup registration failed"
        }

        $handle = $null
        try {
            $handle = Invoke-WPFRunspace -ScriptBlock {
                $sync.WorkStarted.Set()
                Start-Sleep -Milliseconds 100
                $sync.WorkFinished = $true
            }

            $workStarted.IsSet | Should -BeTrue
            $handle.AsyncWaitHandle.WaitOne(5000) | Should -BeTrue
            $script:sync.WorkFinished | Should -BeTrue
            @(Get-WinUtilActiveShell).Count | Should -Be 1
            Should -Invoke Register-WinUtilRunspaceCleanup -Times 1 -Exactly
        } finally {
            if ($null -ne $handle) {
                $shell = @(Get-WinUtilActiveShell)[0]
                try { $null = $shell.EndInvoke($handle) } catch { }
                $shell.Dispose()
                $script:sync.ActiveShells.Remove($shell)
            }
            $workStarted.Dispose()
        }
    }

    It "passa um parâmetro nomeado" {
        $script:sync.Result = $null

        $handle = Invoke-WPFRunspace -ParameterList @(,("Name", "value")) -ScriptBlock {
            param([string]$Name)

            Start-Sleep -Milliseconds 100
            $sync.Result = "Name=$Name"
        }

        Assert-WinUtilAsyncHandle -Handle $handle
        $script:sync.Result | Should -Be "Name=value"
    }

    It "passa vários parâmetros nomeados" {
        $script:sync.Result = $null

        $handle = Invoke-WPFRunspace -ParameterList @(
            ("First", "alpha"),
            ("Second", "beta")
        ) -ScriptBlock {
            param(
                [string]$First,
                [string]$Second
            )

            Start-Sleep -Milliseconds 100
            $sync.Result = "$First|$Second|$($sync.Marker)"
        }

        Assert-WinUtilAsyncHandle -Handle $handle
        $script:sync.Result | Should -Be "alpha|beta|shared"
    }

    It "mantém o pool compartilhado de runspaces utilizável após falhas de scriptblock" {
        $handle = Invoke-WPFRunspace -ScriptBlock {
            Start-Sleep -Milliseconds 100
            throw "runspace failure"
        }

        Assert-WinUtilAsyncHandle -Handle $handle

        $script:sync.Result = $null
        $secondHandle = Invoke-WPFRunspace -ScriptBlock {
            $sync.Result = "after-failure"
        }

        Assert-WinUtilAsyncHandle -Handle $secondHandle
        $script:sync.Result | Should -Be "after-failure"
    }

    It "executa várias invocações enfileiradas sem estado compartilhado do PowerShell" {
        $script:sync.FirstResult = $null
        $script:sync.SecondResult = $null

        $firstHandle = Invoke-WPFRunspace -ParameterList @(,("Value", "first")) -ScriptBlock {
            param([string]$Value)

            Start-Sleep -Milliseconds 150
            $sync.FirstResult = $Value
        }
        $secondHandle = Invoke-WPFRunspace -ParameterList @(,("Value", "second")) -ScriptBlock {
            param([string]$Value)

            $sync.SecondResult = $Value
        }

        Assert-WinUtilAsyncHandle -Handle $firstHandle
        Assert-WinUtilAsyncHandle -Handle $secondHandle
        $script:sync.FirstResult | Should -Be "first"
        $script:sync.SecondResult | Should -Be "second"
    }



    It "expõe um callback de limpeza fortemente tipado" {
        ([WinUtilRunspaceCleanupV3]::Callback -is [System.Threading.WaitOrTimerCallback]) | Should -BeTrue
    }
}

Describe "Chamadores públicos do runspace" {
    BeforeEach {
        $script:sync = [Hashtable]::Synchronized(@{
            ProcessRunning = $false
            selectedFeatures = [System.Collections.Generic.List[string]]::new()
            selectedTweaks = [System.Collections.Generic.List[string]]::new()
            selectedAppx = [System.Collections.Generic.List[string]]::new()
            configs = @{
                appxHashtable = @{}
            }
        })

        Mock Invoke-WPFRunspace { [pscustomobject]@{ MockHandle = $true } }
        Mock Start-WinUtilJob { }
    }

    AfterEach {
        Remove-Variable -Name sync -Scope Script -ErrorAction SilentlyContinue
    }

    It "enfileira a instalação de recursos selecionados como um trabalho sem executar o corpo" {
        $script:sync.selectedFeatures.Add("WPFFeaturesSandbox")

        Invoke-WPFFeatureInstall

        Should -Invoke -CommandName Start-WinUtilJob -Times 1 -Exactly -ParameterFilter {
            $Name -eq "Features" -and
                $ScriptBlock -is [scriptblock] -and
                @($Parameters.Features)[0] -eq "WPFFeaturesSandbox"
        }
    }

    It "enfileira a reversão dos ajustes selecionados como um trabalho sem executar o corpo" {
        $script:sync.selectedTweaks.Add("WPFTweaksTelemetry")
        $script:sync.selectedTweaks.Add("WPFTweaksServices")

        Invoke-WPFundoall

        Should -Invoke -CommandName Start-WinUtilJob -Times 1 -Exactly -ParameterFilter {
            $Name -eq "Undo tweaks" -and
                $ScriptBlock -is [scriptblock] -and
                @($Parameters.Tweaks).Count -eq 2 -and
                @($Parameters.Tweaks)[0] -eq "WPFTweaksTelemetry"
        }
    }

    It "enfileira a remoção de AppX como um trabalho com a seleção e os metadados do aplicativo" {
        $script:sync.selectedAppx.Add("WPFAppxExample")
        $script:sync.configs.appxHashtable["WPFAppxExample"] = [pscustomobject]@{
            Content = "Example"
            PackageId = "Example.Package"
        }

        Invoke-WPFAppxRemoval

        Should -Invoke -CommandName Start-WinUtilJob -Times 1 -Exactly -ParameterFilter {
            $Name -eq "AppX" -and
                $ScriptBlock -is [scriptblock] -and
                @($Parameters.Selected)[0] -eq "WPFAppxExample" -and
                $Parameters.Apps.ContainsKey("WPFAppxExample")
        }
    }

    It "mantém todos os pontos de entrada de fluxos longos na camada de trabalhos" {
        $publicRoot = Join-Path $script:repoRoot "functions\public"
        $privateRoot = Join-Path $script:repoRoot "functions\private"
        $entrypoints = @(
            (Join-Path $publicRoot "Invoke-WPFInstall.ps1"),
            (Join-Path $publicRoot "Invoke-WPFUnInstall.ps1"),
            (Join-Path $publicRoot "Invoke-WPFAppxInstall.ps1"),
            (Join-Path $publicRoot "Invoke-WPFAppxRemoval.ps1"),
            (Join-Path $publicRoot "Invoke-WPFFeatureInstall.ps1"),
            (Join-Path $publicRoot "Invoke-WPFGetInstalled.ps1"),
            (Join-Path $publicRoot "Invoke-WPFOOSU.ps1"),
            (Join-Path $publicRoot "Invoke-WPFtweaksbutton.ps1"),
            (Join-Path $publicRoot "Invoke-WPFundoall.ps1"),
            (Join-Path $privateRoot "Invoke-WinUtilISO.ps1"),
            (Join-Path $privateRoot "Invoke-WinUtilISOUSB.ps1")
        )

        foreach ($entrypoint in $entrypoints) {
            $source = Get-Content -Path $entrypoint -Raw
            $source | Should -Match 'Start-WinUtilJob -Name'
            # Corpos de trabalho nunca criam seu próprio runspace ou estado de ocupação
            $source | Should -Not -Match 'RunspaceFactory\]::CreateRunspace'
            $source | Should -Not -Match 'Invoke-WPFRunspace'
            $source | Should -Not -Match '\$sync\.ProcessRunning'
        }
    }
}
