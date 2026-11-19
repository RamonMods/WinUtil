BeforeAll {
    Add-Type -AssemblyName WindowsBase, PresentationFramework
    . (Join-Path $PSScriptRoot '../functions/private/Update-WinUtilWindowInsets.ps1')
}

Describe 'Margens da janela maximizada' {
    It 'usa a moldura real mais borda com preenchimento em <Dpi> DPI' -TestCases @(
        @{ Dpi = 96; Pixels = 8 }, @{ Dpi = 120; Pixels = 9 },
        @{ Dpi = 144; Pixels = 11 }, @{ Dpi = 192; Pixels = 13 },
        @{ Dpi = 288; Pixels = 18 }
    ) {
        param($Dpi, $Pixels)
        $work = [pscustomobject]@{ Left=0; Top=0; Right=2560; Bottom=1392 }
        $bounds = [pscustomobject]@{ Left=-$Pixels; Top=-$Pixels; Right=2560+$Pixels; Bottom=1392+$Pixels }
        $scale = 96.0 / $Dpi
        $transform = [Windows.Media.Matrix]::new($scale,0,0,$scale,0,0)
        $margin = Get-WinUtilWindowInsets -Bounds $bounds -WorkArea $work -FromDevice $transform
        $margin.Left | Should -Be ($Pixels * $scale)
        $margin.Top | Should -Be ($Pixels * $scale)
        $margin.Right | Should -Be ($Pixels * $scale)
        $margin.Bottom | Should -Be ($Pixels * $scale)
    }

    It 'lida com um monitor em coordenadas negativas e uma barra de tarefas à esquerda' {
        $work = [pscustomobject]@{ Left=-1872; Top=-1080; Right=0; Bottom=0 }
        $bounds = [pscustomobject]@{ Left=-1880; Top=-1088; Right=8; Bottom=8 }
        $margin = Get-WinUtilWindowInsets -Bounds $bounds -WorkArea $work -FromDevice ([Windows.Media.Matrix]::Identity)
        $margin | Should -Be ([Windows.Thickness]::new(8))
    }

    It 'lida com saliência assimétrica sem transformar espaço não usado em margens negativas' {
        $work = [pscustomobject]@{ Left=40; Top=0; Right=1920; Bottom=1040 }
        $bounds = [pscustomobject]@{ Left=32; Top=-12; Right=1924; Bottom=1030 }
        $margin = Get-WinUtilWindowInsets -Bounds $bounds -WorkArea $work -FromDevice ([Windows.Media.Matrix]::Identity)
        $margin | Should -Be ([Windows.Thickness]::new(8,12,4,0))
    }

    It 'limpa a margem quando a janela é restaurada' {
        $script:sync = @{ Form = [pscustomobject]@{ WindowState='Normal' }; WPFMainGrid = [pscustomobject]@{ Margin = [Windows.Thickness]::new(8) } }
        try {
            Update-WinUtilWindowInsets
            $sync.WPFMainGrid.Margin | Should -Be ([Windows.Thickness]::new(0))
        } finally {
            Remove-Variable sync -Scope Script
        }
    }
}
