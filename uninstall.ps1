# Removes UE4SS and the LushfoilCraft mod from the game folder, restoring it to the original contents.
param([string]$Game = (Split-Path $PSScriptRoot -Parent))
$win64 = Join-Path $Game "LushfoilSim\Binaries\Win64"
if (Get-Process -Name "LushfoilSim*" -ErrorAction SilentlyContinue) { throw "Close the game first" }
Remove-Item (Join-Path $win64 "dwmapi.dll") -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $win64 "ue4ss") -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "Removed. Remaining: $((Get-ChildItem $win64 -Name) -join ', ')"
