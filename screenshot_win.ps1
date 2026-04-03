Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class CaptureWin {
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdcBlt, uint nFlags);
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }
}
"@
$proc = Get-Process -Name "hbbuilder_win" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($proc -and $proc.MainWindowHandle -ne [IntPtr]::Zero) {
    $hwnd = $proc.MainWindowHandle
    $rect = New-Object CaptureWin+RECT
    [CaptureWin]::GetWindowRect($hwnd, [ref]$rect)
    $w = $rect.Right - $rect.Left
    $h = $rect.Bottom - $rect.Top
    if ($w -gt 0 -and $h -gt 0) {
        $b = New-Object System.Drawing.Bitmap($w, $h)
        $g = [System.Drawing.Graphics]::FromImage($b)
        $hdc = $g.GetHdc()
        [CaptureWin]::PrintWindow($hwnd, $hdc, 0)
        $g.ReleaseHdc($hdc)
        $b.Save("c:\HarbourBuilder\screenshot.png")
        $g.Dispose()
        $b.Dispose()
        Write-Host "Captured IDE window: ${w}x${h}"
    }
} else {
    Write-Host "IDE not found"
}
