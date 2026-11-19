#===========================================================================
# Testes - Ciclo de vida do runspace

BeforeAll {
    $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
    . (Join-Path $script:repoRoot "functions\private\Get-WinUtilRunspacePoolLock.ps1")
    . (Join-Path $script:repoRoot "functions\private\Close-WinUtilRunspacePool.ps1")
    . (Join-Path $script:repoRoot "functions\private\Stop-WinUtilActiveWork.ps1")
    . (Join-Path $script:repoRoot "functions\private\New-WinUtilSessionState.ps1")
    . (Join-Path $script:repoRoot "functions\private\Initialize-WinUtilRunspacePool.ps1")
}

Describe "Initialize-WinUtilRunspacePool" {
    BeforeEach {
        $script:sync = [Hashtable]::Synchronized(@{})
        $script:PARAM_OFFLINE = $false
    }

    AfterEach {
        Close-WinUtilRunspacePool
        Remove-Variable -Name sync -Scope Script -ErrorAction SilentlyContinue
        Remove-Variable -Name PARAM_OFFLINE -Scope Script -ErrorAction SilentlyContinue
    }

    It "cria e reutiliza um único pool de runspaces aberto" {
        $firstPool = Initialize-WinUtilRunspacePool
        $secondPool = Initialize-WinUtilRunspacePool

        $firstPool.RunspacePoolStateInfo.State | Should -Be ([System.Management.Automation.Runspaces.RunspacePoolState]::Opened)
        [object]::ReferenceEquals($firstPool, $secondPool) | Should -BeTrue
    }

    It "usa um único bloqueio de ciclo de vida para a sessão" {
        $firstLock = Get-WinUtilRunspacePoolLock
        $secondLock = Get-WinUtilRunspacePoolLock

        [object]::ReferenceEquals($firstLock, $secondLock) | Should -BeTrue
    }

    It "fecha e remove o pool de runspaces ativo" {
        $pool = Initialize-WinUtilRunspacePool

        Close-WinUtilRunspacePool

        $pool.RunspacePoolStateInfo.State | Should -Be ([System.Management.Automation.Runspaces.RunspacePoolState]::Closed)
        $script:sync.ContainsKey("runspace") | Should -BeFalse
    }

    It "adia a limpeza do pool quando um worker ignora o tempo limite de parada" {
        $pool = [runspacefactory]::CreateRunspacePool(1, 1)
        $pool.Open()
        $script:sync.runspace = $pool

        Mock Stop-WinUtilActiveWork { $false }
        Mock Register-WinUtilRunspacePoolCleanup { }

        try {
            Close-WinUtilRunspacePool

            $pool.RunspacePoolStateInfo.State | Should -Be ([System.Management.Automation.Runspaces.RunspacePoolState]::Opened)
            $script:sync.ContainsKey("runspace") | Should -BeFalse
            Should -Invoke Register-WinUtilRunspacePoolCleanup -Times 1 -Exactly -ParameterFilter {
                [object]::ReferenceEquals($RunspacePool, $pool)
            }
        } finally {
            $pool.Close()
            $pool.Dispose()
        }
    }
}

Describe "Configuração de inicialização do runspace" {








    It "carrega todas as funções do WinUtil em um novo runspace" {
        $sync = [Hashtable]::Synchronized(@{})
        $null = $sync
        function Test-WinUtilSessionStateMarker { "marker" }
        function Get-SomethingUnprefixed { "unprefixed" }

        $runspace = [runspacefactory]::CreateRunspace((New-WinUtilSessionState))
        $runspace.Open()
        try {
            $shell = [powershell]::Create()
            $shell.Runspace = $runspace
            [void]$shell.AddScript('Test-WinUtilSessionStateMarker; Get-SomethingUnprefixed; (Get-Command mkdir).CommandType')
            $result = $shell.Invoke()
            $shell.Dispose()

            $result | Should -Contain "marker"
            $result | Should -Contain "unprefixed"
        } finally {
            $runspace.Close()
            $runspace.Dispose()
            Remove-Item Function:\Test-WinUtilSessionStateMarker -ErrorAction SilentlyContinue
            Remove-Item Function:\Get-SomethingUnprefixed -ErrorAction SilentlyContinue
        }
    }

    It "carrega assemblies WPF dentro do runspace de ativos de inicialização a frio" {
        $source = Get-Content -Path (Join-Path $script:repoRoot "functions\private\Start-WinUtilAssetRendering.ps1") -Raw

        $source | Should -Match 'Add-Type -AssemblyName WindowsBase'
        $source | Should -Match 'Add-Type -AssemblyName PresentationCore'
        $source | Should -Match 'Add-Type -AssemblyName PresentationFramework'
    }


}
