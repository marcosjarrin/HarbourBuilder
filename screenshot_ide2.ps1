Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinAPI {
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
}
"@
$proc = Get-Process -Name "hbbuilder_win" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($proc -and $proc.MainWindowHandle -ne [IntPtr]::Zero) {
    # Simulate Alt key press to allow SetForegroundWindow
    [WinAPI]::keybd_event(0x12, 0, 0, [UIntPtr]::Zero)  # Alt down
    [WinAPI]::SetForegroundWindow($proc.MainWindowHandle)
    [WinAPI]::keybd_event(0x12, 0, 2, [UIntPtr]::Zero)  # Alt up
    Start-Sleep -Milliseconds 800
}
$s = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$b = New-Object System.Drawing.Bitmap($s.Width, $s.Height)
$g = [System.Drawing.Graphics]::FromImage($b)
$g.CopyFromScreen($s.Location, [System.Drawing.Point]::Empty, $s.Size)
$b.Save("c:\HarbourBuilder\screenshot.png", [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose()
$b.Dispose()
