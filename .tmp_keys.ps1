Add-Type -AssemblyName System.Windows.Forms
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class Fg2 {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
}
'@
$p = Get-Process xenia_canary -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $p) { Write-Output 'SEM PROCESSO'; exit }
[void][Fg2]::ShowWindow($p.MainWindowHandle, 9)
[void][Fg2]::SetForegroundWindow($p.MainWindowHandle)
Start-Sleep -Milliseconds 900
[System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
Start-Sleep -Milliseconds 700
[System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
Write-Output 'teclas enviadas'
