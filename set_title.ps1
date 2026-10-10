# Renames the game window to "LushfoilCraft" (the engine's own title comes from the Lushfoil project and cannot be changed from the mod).
param([string]$Title = "LushfoilCraft - built from Lushfoil Photography Sim and Minecraft - by Shivin Singh")
Add-Type @"
using System; using System.Runtime.InteropServices;
public class LCWin { [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern bool SetWindowTextW(IntPtr h, string t); }
"@
$deadline = (Get-Date).AddSeconds(90)
$until = $null
while ((Get-Date) -lt $deadline) {
    $p = Get-Process -Name "LushfoilSim-Win64-Shipping" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($p -and $p.MainWindowHandle -ne 0) {
        [LCWin]::SetWindowTextW($p.MainWindowHandle, $Title) | Out-Null
        if (-not $until) { $until = (Get-Date).AddSeconds(20) }
        if ((Get-Date) -gt $until) { break }
    }
    Start-Sleep -Milliseconds 1000
}
