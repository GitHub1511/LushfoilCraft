# Starts Lushfoil directly in Lake Braies (windowed) with the mod loaded.
param([int]$Width = 1600, [int]$Height = 900, [string]$Map = "/Game/Lagodibraies", [string]$Game = (Split-Path $PSScriptRoot -Parent))
$bin = Join-Path $Game "LushfoilSim\Binaries\Win64"
Start-Process -FilePath (Join-Path $bin "LushfoilSim-Win64-Shipping.exe") -ArgumentList $Map, "-windowed", "-ResX=$Width", "-ResY=$Height", "-nosplash" -WorkingDirectory $bin
# window title: LushfoilCraft instead of the original game's name
Start-Process -FilePath "powershell" -ArgumentList "-NoProfile", "-WindowStyle", "Hidden", "-File", (Join-Path $PSScriptRoot "set_title.ps1")
