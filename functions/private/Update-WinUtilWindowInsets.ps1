function Update-WinUtilWindowInsets {
    <#
    .SYNOPSIS
        Mantém o conteúdo do cliente maximizado dentro da área de trabalho do monitor atual.
    #>
    if (-not $sync.Form -or -not $sync.WPFMainGrid) { return }
    if ($sync.Form.WindowState -ne 'Maximized') {
        $sync.WPFMainGrid.Margin = [Windows.Thickness]::new(0)
        return
    }

    if (-not ('WinUtil.WindowBounds' -as [type])) {
        Add-Type @"
using System;
using System.Runtime.InteropServices;
namespace WinUtil {
    public static class WindowBounds {
        [StructLayout(LayoutKind.Sequential)]
        public struct Rect { public int Left, Top, Right, Bottom; }
        [StructLayout(LayoutKind.Sequential)]
        public struct MonitorInfo {
            public int Size;
            public Rect Monitor, Work;
            public uint Flags;
        }
        [DllImport("user32.dll")]
        public static extern bool GetWindowRect(IntPtr window, out Rect rect);
        [DllImport("user32.dll")]
        public static extern IntPtr MonitorFromWindow(IntPtr window, uint flags);
        [DllImport("user32.dll", CharSet = CharSet.Auto)]
        public static extern bool GetMonitorInfo(IntPtr monitor, ref MonitorInfo info);
    }
}
"@
    }

    $handle = [Windows.Interop.WindowInteropHelper]::new($sync.Form).Handle
    $source = [Windows.Interop.HwndSource]::FromHwnd($handle)
    if (-not $source -or -not $source.CompositionTarget) { return }
    $bounds = [WinUtil.WindowBounds+Rect]::new()
    $monitor = [WinUtil.WindowBounds+MonitorInfo]::new()
    $monitor.Size = [Runtime.InteropServices.Marshal]::SizeOf($monitor)
    $monitorHandle = [WinUtil.WindowBounds]::MonitorFromWindow($handle, 2)
    if (-not [WinUtil.WindowBounds]::GetWindowRect($handle, [ref]$bounds) -or
        -not [WinUtil.WindowBounds]::GetMonitorInfo($monitorHandle, [ref]$monitor)) { return }

    $sync.WPFMainGrid.Margin = Get-WinUtilWindowInsets -Bounds $bounds -WorkArea $monitor.Work -FromDevice $source.CompositionTarget.TransformFromDevice
}

function Get-WinUtilWindowInsets {
    param($Bounds, $WorkArea, $FromDevice)
    # Mede a saliência real, incluindo a borda com preenchimento; o dobro da moldura de
    # redimensionamento só é correto em algumas configurações de DPI. Converte pixels físicos em DIPs do WPF.
    $topLeft = $FromDevice.Transform([Windows.Vector]::new(
        [Math]::Max(0, $WorkArea.Left - $Bounds.Left),
        [Math]::Max(0, $WorkArea.Top - $Bounds.Top)))
    $bottomRight = $FromDevice.Transform([Windows.Vector]::new(
        [Math]::Max(0, $Bounds.Right - $WorkArea.Right),
        [Math]::Max(0, $Bounds.Bottom - $WorkArea.Bottom)))
    return [Windows.Thickness]::new($topLeft.X, $topLeft.Y, $bottomRight.X, $bottomRight.Y)
}

function Request-WinUtilWindowInsets {
    # Os eventos podem chegar antes de o WPF processar a mudança nativa de tamanho/DPI.
    # Agrupe-os e leia a geometria final do HWND no dispatcher da interface.
    if ($sync.WindowInsetsPending -or -not (Test-WinUtilUIAlive)) { return }
    $sync.WindowInsetsPending = $true
    [void]$sync.Form.Dispatcher.BeginInvoke([Windows.Threading.DispatcherPriority]::Loaded, $sync.WindowInsetsUpdate)
}
