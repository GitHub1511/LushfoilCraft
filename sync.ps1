# Copies the mod (Scripts + textures) into the game's UE4SS mod folder. Safe to run while the game is running:
# craft.lua is hot-reloaded by the framework within a second.
param([string]$Game = (Split-Path $PSScriptRoot -Parent))
$mod = Join-Path $Game "LushfoilSim\Binaries\Win64\ue4ss\Mods\LushfoilCraft"
New-Item -ItemType Directory -Force (Join-Path $mod "Scripts") | Out-Null
Copy-Item (Join-Path $PSScriptRoot "Scripts\*.lua") (Join-Path $mod "Scripts") -Force
if (Test-Path (Join-Path $PSScriptRoot "textures")) {
    New-Item -ItemType Directory -Force (Join-Path $mod "textures") | Out-Null
    Copy-Item (Join-Path $PSScriptRoot "textures\*.png") (Join-Path $mod "textures") -Force
}
New-Item -ItemType Directory -Force (Join-Path $mod "saves") | Out-Null     # world saves live here and are never overwritten by a sync
New-Item -ItemType File -Force (Join-Path $mod "enabled.txt") | Out-Null
Write-Host "synced to $mod"
