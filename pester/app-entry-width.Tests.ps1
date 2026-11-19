#===========================================================================
# Testes - Largura do cartão de aplicativo e renderização antes da exibição

BeforeAll {
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
    foreach ($file in @(
        "functions/private/Update-WinUtilAppEntryWidth.ps1",
        "functions/private/Start-WinUtilInstallAppRendering.ps1",
        "functions/private/Start-WinUtilBackgroundQueue.ps1"
    )) {
        . (Join-Path $repoRoot $file)
    }
}

Describe "Update-WinUtilAppEntryWidth" {
    BeforeEach {
        $script:sync = [Hashtable]::Synchronized(@{
            Form = [Windows.Window]::new()
            ItemsControl = [pscustomobject]@{ Parent = [pscustomobject]@{ ViewportWidth = 0.0 } }
        })
        $script:sync.Form.Resources["AppEntryWidth"] = 242.0
        $script:sync.Form.Resources["AppEntryMargin"] = [Windows.Thickness]::new(3)
        $script:sync.Form.Resources["AppEntryCardWidth"] = 242.0
    }

    AfterEach {
        $script:sync.Form.Close()
    }

    It "divide uma linha de <Viewport> px entre <Columns> cartões sem sobrar nada" -TestCases @(
        @{ Viewport = 1130.0; Columns = 4 }
        @{ Viewport = 1500.0; Columns = 6 }
        @{ Viewport = 800.0; Columns = 3 }
    ) {
        $script:sync.ItemsControl.Parent.ViewportWidth = $Viewport
        Update-WinUtilAppEntryWidth

        $width = $script:sync.Form.Resources["AppEntryCardWidth"]
        $width | Should -BeGreaterOrEqual 242
        [Math]::Floor($Viewport / ($width + 6)) | Should -Be $Columns
        $Viewport - $Columns * ($width + 6) | Should -BeLessThan $Columns
    }

    It "mantém o cartão na largura mínima quando a viewport é mais estreita que isso" {
        $script:sync.ItemsControl.Parent.ViewportWidth = 200.0
        Update-WinUtilAppEntryWidth

        $script:sync.Form.Resources["AppEntryCardWidth"] | Should -Be 242
    }

    It "não altera a largura até que a lista tenha sido disposta" {
        Update-WinUtilAppEntryWidth

        $script:sync.Form.Resources["AppEntryCardWidth"] | Should -Be 242
    }

    It "respeita uma largura mínima maior, definida pela escala da fonte" {
        $script:sync.ItemsControl.Parent.ViewportWidth = 1130.0
        $script:sync.Form.Resources["AppEntryWidth"] = 400.0
        Update-WinUtilAppEntryWidth

        $script:sync.Form.Resources["AppEntryCardWidth"] | Should -BeGreaterOrEqual 400
    }
}

Describe "Renderização da lista de instalação antes da exibição da janela" {
    BeforeEach {
        $script:sync = [Hashtable]::Synchronized(@{
            InstallAppRenderQueue = [System.Collections.Queue]::new()
            BuildingBeforeShow = $true
        })
        1..3 | ForEach-Object { $script:sync.InstallAppRenderQueue.Enqueue([pscustomobject]@{ Category = "C$_" }) }
        $script:budgets = [System.Collections.Generic.List[int]]::new()
        Mock Invoke-WinUtilInstallAppRenderBatch { $script:budgets.Add($ChunkSize) }
        Mock Start-WinUtilBackgroundQueue { throw "Nothing may be queued for the dispatcher before the window exists" }
    }

    It "renderiza todos os lotes em uma única passada sem limite de tamanho" {
        Start-WinUtilInstallAppRendering

        $script:budgets.Count | Should -Be 3
        $script:budgets | ForEach-Object { $_ | Should -Be ([int]::MaxValue) }
        $script:sync.InstallAppRenderQueue.Count | Should -Be 0
        $script:sync.InstallAppEntriesRendered | Should -BeTrue
    }

    It "usa a fila do dispatcher quando a janela está aberta" {
        $script:sync.BuildingBeforeShow = $false
        Mock Start-WinUtilBackgroundQueue { }
        Start-WinUtilInstallAppRendering

        Should -Invoke Start-WinUtilBackgroundQueue -Times 1
        $script:budgets.Count | Should -Be 0
    }
}