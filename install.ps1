# Installs UE4SS and the LushfoilCraft mod into the game folder. Run uninstall.ps1 to undo.
# Usage: powershell -ExecutionPolicy Bypass -File install.ps1 -Ue4ssZip <path to UE4SS_*.zip>
param(
    [Parameter(Mandatory = $true)][string]$Ue4ssZip,
    [string]$Game = (Split-Path $PSScriptRoot -Parent)
)
$win64 = Join-Path $Game "LushfoilSim\Binaries\Win64"
if (-not (Test-Path (Join-Path $win64 "LushfoilSim-Win64-Shipping.exe"))) { throw "Game not found at $Game" }
if (Get-Process -Name "LushfoilSim*" -ErrorAction SilentlyContinue) { throw "Close the game first" }

$tmp = Join-Path $env:TEMP ("ue4ss_" + [guid]::NewGuid())
Expand-Archive -Path $Ue4ssZip -DestinationPath $tmp
Copy-Item (Join-Path $tmp "dwmapi.dll") $win64 -Force
Copy-Item (Join-Path $tmp "ue4ss") $win64 -Recurse -Force
Remove-Item $tmp -Recurse -Force

# quiet by default: no debug window, keep the log (ue4ss\UE4SS.log)
$ini = Join-Path $win64 "ue4ss\UE4SS-settings.ini"
(Get-Content $ini) -replace '^GuiConsoleEnabled = 1', 'GuiConsoleEnabled = 0' -replace '^GuiConsoleVisible = 1', 'GuiConsoleVisible = 0' | Set-Content $ini

# the mod
$mod = Join-Path $win64 "ue4ss\Mods\LushfoilCraft"
New-Item -ItemType Directory -Force (Join-Path $mod "Scripts") | Out-Null
& (Join-Path $PSScriptRoot "sync.ps1") -Game $Game     # Scripts, textures, enabled.txt. Worlds and settings stay per device in %LOCALAPPDATA%, never in this folder
Write-Host "Installed. Launch the game; the log is $win64\ue4ss\UE4SS.log"
