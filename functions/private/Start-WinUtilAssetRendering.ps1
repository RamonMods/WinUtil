function Start-WinUtilAssetRendering {
    <#
        .SYNOPSIS
            Renderiza os bitmaps de sobreposição da barra de tarefas em uma thread própria

        .DESCRIPTION
            Rasterizar as sobreposições consome tempo da thread da interface que ela poderia usar
            para levantar a janela. Os bitmaps são congelados antes da publicação, então podem ser
            construídos em qualquer lugar.

            Nada espera por isto: se a renderização não tiver terminado quando uma sobreposição for
            solicitada, Set-WinUtilTaskbaritem a renderiza na hora.

            Precisa de STA para RenderTargetBitmap, o que o pool de workers compartilhado não é.
    #>

    $runspace = [runspacefactory]::CreateRunspace((New-WinUtilSessionState))
    $runspace.ApartmentState = "STA"
    $runspace.ThreadOptions = "ReuseThread"
    $runspace.Open()

    $shell = [powershell]::Create()
    $shell.Runspace = $runspace
    [void]$shell.AddScript({
        # Um novo runspace não herda os assemblies carregados pelo runspace da interface. Em um
        # processo frio esses tipos falham antes que a renderização fora da thread faça qualquer trabalho.
        Add-Type -AssemblyName WindowsBase
        Add-Type -AssemblyName PresentationCore
        Add-Type -AssemblyName PresentationFramework

        Measure-WinUtilStep -Scope "UI" -Name "renderizar sobreposições da barra de tarefas (fora da thread)" -ScriptBlock {
            Initialize-WinUtilTaskbarOverlayAssets -IncludeLogo $true -IncludeStatusAssets $true
        }
    })

    $handle = $shell.BeginInvoke()

    Register-WinUtilRunspaceCleanup -PowerShell $shell -Handle $handle -Runspace $runspace

    return $handle
}
