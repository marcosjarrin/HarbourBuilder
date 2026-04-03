Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32 {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
}
"@

$procs = Get-Process -Name "hbbuilder_win" -ErrorAction SilentlyContinue
if ($procs) {
    $hwnd = $procs[0].MainWindowHandle
    if ($hwnd -ne [IntPtr]::Zero) {
        [Win32]::SetForegroundWindow($hwnd) | Out-Null
        Start-Sleep -Milliseconds 500
    }
}

# Capture just the code editor area (right portion of screen)
$screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$bitmap = New-Object System.Drawing.Bitmap($screen.Width, $screen.Height)
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.CopyFromScreen($screen.Location, [System.Drawing.Point]::Empty, $screen.Size)

# Save full resolution PNG (no compression)
$bitmap.Save("c:\HarbourBuilder\screenshot_full.png", [System.Drawing.Imaging.ImageFormat]::Png)
$graphics.Dispose()
$bitmap.Dispose()
