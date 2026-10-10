# Builds LushfoilCraft from your own copies of the two games. Nothing copyrighted is downloaded.
#
#   powershell -ExecutionPolicy Bypass -File Build-LushfoilCraft.ps1 `
#     -LushfoilPath "C:\Program Files (x86)\Steam\steamapps\common\Lushfoil Photography Sim" `
#     -MinecraftPath "$env:APPDATA\.minecraft\versions\1.21.1\1.21.1.jar"
#
#   -LushfoilPath   Folder that contains LushfoilSim\ (+ Engine\). Your Steam install, or a copy of it.
#   -MinecraftPath  Either the 1.21.1 client jar itself, OR a folder that contains it:
#                   the jar file, versions\1.21.1\, or your whole .minecraft folder.
#   -Output         Where to build LushfoilCraft. Default: <parent>\LushfoilCraft (a copy, your
#                   Steam install is left untouched). Pass the same folder as -LushfoilPath
#                   together with -NoCopy to install in place instead of copying (~9 GB copy skipped).
#   -NoCopy         Install directly into -LushfoilPath instead of copying the game first.
#   -SkipAssets     Skip regenerating Minecraft-derived assets (reuse textures\ + Scripts\blocks.lua etc).
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$LushfoilPath,
    [Parameter(Mandatory = $true)][string]$MinecraftPath,
    [string]$Output = "",
    [switch]$NoCopy,
    [switch]$SkipAssets
)

$ErrorActionPreference = "Stop"
$Repo = $PSScriptRoot

function Resolve-LushfoilRoot([string]$p) {
    if (-not (Test-Path $p)) { throw "LushfoilPath not found: $p" }
    $p = (Resolve-Path $p).Path
    # allow passing ...\LushfoilSim itself
    if ((Split-Path $p -Leaf) -eq "LushfoilSim") { $p = Split-Path $p -Parent }
    $exe = Join-Path $p "LushfoilSim\Binaries\Win64\LushfoilSim-Win64-Shipping.exe"
    if (-not (Test-Path $exe)) {
        throw "Not a Lushfoil Photography Sim folder: $p`nExpected $exe`nPass your Steam folder, e.g. ...\steamapps\common\Lushfoil Photography Sim"
    }
    return $p
}

function Resolve-MinecraftJar([string]$p) {
    if (-not (Test-Path $p)) {
        $auto = Join-Path $env:APPDATA ".minecraft\versions\1.21.1\1.21.1.jar"
        throw "MinecraftPath not found: $p`nPass the 1.21.1 client jar, or a folder containing it (tried $auto)."
    }
    $p = (Resolve-Path $p).Path
    if (Test-Path $p -PathType Leaf) { $jar = $p }
    else {
        $cands = @(
            (Join-Path $p "1.21.1.jar"),
            (Join-Path $p "versions\1.21.1\1.21.1.jar"),
            (Join-Path $p ".minecraft\versions\1.21.1\1.21.1.jar")
        )
        $found = Get-ChildItem -Path $p -Filter "1.21.1.jar" -Recurse -Depth 3 -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) { $cands = @($found.FullName) + $cands }
        $jar = $cands | Where-Object { Test-Path $_ } | Select-Object -First 1
        if (-not $jar) { throw "No 1.21.1 client jar found under $p`nExpected ...\versions\1.21.1\1.21.1.jar (launch Minecraft 1.21.1 once to download it)." }
    }
    # validate: must be a jar containing Minecraft 1.21.1 blockstates
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    try {
        $z = [System.IO.Compression.ZipFile]::OpenRead($jar)
        try {
            $has = $z.Entries | Where-Object { $_.FullName -eq "assets/minecraft/blockstates/grass_block.json" } | Select-Object -First 1
            if (-not $has) { throw "Not a Minecraft client jar (no assets/minecraft/blockstates/): $jar" }
        } finally { $z.Dispose() }
    } catch { throw $_ }
    return (Resolve-Path $jar).Path
}

function Invoke-Step([string]$label, [scriptblock]$b) {
    Write-Host "`n=== $label ===" -ForegroundColor Cyan
    & $b
    if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne $null) { throw "$label failed (exit $LASTEXITCODE)" }
}

$LushfoilRoot = Resolve-LushfoilRoot $LushfoilPath
$Jar = Resolve-MinecraftJar $MinecraftPath
Write-Host "Lushfoil: $LushfoilRoot"
Write-Host "Minecraft jar: $Jar"

if ($NoCopy) {
    if ($Output -and ((Resolve-Path $Output -ErrorAction SilentlyContinue).Path -ne (Resolve-Path $LushfoilRoot).Path)) {
        throw "-NoCopy was given but -Output points elsewhere. Omit -Output to install in place."
    }
    $Game = $LushfoilRoot
} else {
    if (-not $Output) { $Output = Join-Path (Split-Path $LushfoilRoot -Parent) "LushfoilCraft" }
    $Game = $Output
    if ((Test-Path $Game) -and ((Resolve-Path $Game).Path -eq (Resolve-Path $LushfoilRoot).Path)) {
        Write-Host "Output == LushfoilPath, installing in place."
    } else {
        Write-Host "Game copy: $Game"
        New-Item -ItemType Directory -Force $Game | Out-Null
        foreach ($d in @("LushfoilSim", "Engine")) {
            $src = Join-Path $LushfoilRoot $d
            if (Test-Path $src) {
                Write-Host "Copying $d\ (~minutes for ~9 GB, only new/changed files are recopied on reruns)..."
                robocopy $src (Join-Path $Game $d) /E /MT:8 /R:2 /W:2 /NFL /NDL /NJH /NC /NS | Out-Null
                if ($LASTEXITCODE -ge 8) { throw "robocopy $d failed (exit $LASTEXITCODE)" }
            }
        }
        foreach ($f in @("Manifest_NonUFSFiles_Win64.txt", "Manifest_UFSFiles_Win64.txt")) {
            $src = Join-Path $LushfoilRoot $f
            if (Test-Path $src) { Copy-Item $src $Game -Force }
        }
    }
}

$exe = Join-Path $Game "LushfoilSim\Binaries\Win64\LushfoilSim-Win64-Shipping.exe"
if (-not (Test-Path $exe)) { throw "Build output is missing the game exe: $exe" }

# python ------------------------------------------------------------------
$py = Get-Command python -ErrorAction SilentlyContinue
if (-not $py) { $py = Get-Command python3 -ErrorAction SilentlyContinue }
if (-not $py) { $py = Get-Command py -ErrorAction SilentlyContinue }
if (-not $py) { throw "Python 3 not found on PATH. Install Python 3.10+ from python.org (tick 'Add to PATH')." }
Write-Host "Python: $($py.Source)"
Invoke-Step "Python version" { & $py.Source --version }

if (-not $SkipAssets) {
    New-Item -ItemType Directory -Force (Join-Path $Repo "textures"), (Join-Path $Repo "Scripts") | Out-Null
    $tools = Join-Path $Repo "tools"
    # order matters: cubes -> element models (+ plain-cube fallbacks, rewrites blocks.lua) -> HUD/items/inventory -> icons -> logo
    Invoke-Step "Minecraft block textures + blocks.lua (make_assets)" { & $py.Source "$tools\make_assets.py" $Jar $Repo }
    Invoke-Step "Non-cube block models + models.lua (make_models)" { & $py.Source "$tools\make_models.py" $Jar $Repo }
    Invoke-Step "HUD sprites (make_gui)" { & $py.Source -I "$tools\make_gui.py" $Jar $Repo }
    Invoke-Step "Item sprites + items.lua (make_items)" { & $py.Source -I "$tools\make_items.py" $Jar $Repo }
    Invoke-Step "Inventory screens + Steve (make_inventory)" { & $py.Source -I "$tools\make_inventory.py" $Jar $Repo }
    Invoke-Step "Isometric block icons (make_icons)" { & $py.Source -I "$tools\make_icons.py" $Repo }
    Invoke-Step "Title logo (make_logo)" { & $py.Source -I "$tools\make_logo.py" $Repo }
    $csc = "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
    if (Test-Path $csc) {
        Invoke-Step "Credits / logo art (Gen.cs)" { powershell -NoProfile -ExecutionPolicy Bypass -File "$tools\gen.ps1" }
    } else {
        Write-Warning "csc.exe not found, skipping tools/gen.ps1 (logo/credits art). The mod still runs; rerun gen.ps1 on Windows with .NET Framework to add them."
    }
} else {
    Write-Host "Skipping asset generation (-SkipAssets)."
}

$ue4ss = Get-ChildItem (Join-Path $Repo "vendor\UE4SS_*.zip") | Sort-Object Length -Descending | Select-Object -First 1
if (-not $ue4ss) { throw "No UE4SS zip found in vendor\. Download one UE4SS release zip into vendor\ (e.g. UE4SS_v3.0.1-*.zip)." }

if (Get-Process -Name "LushfoilSim*" -ErrorAction SilentlyContinue) { throw "Close the game first, then rerun." }
Invoke-Step "Install UE4SS + LushfoilCraft mod into $Game" {
    powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Repo "install.ps1") -Ue4ssZip $ue4ss.FullName -Game $Game
}

Write-Host "`nDone. To play:" -ForegroundColor Green
Write-Host "  powershell -ExecutionPolicy Bypass -File `"$Repo\play.ps1`" -Game `"$Game`""
Write-Host "Or run LushfoilSim-Win64-Shipping.exe in $Game\LushfoilSim\Binaries\Win64\ directly."
Write-Host "Worlds/settings live per device in %LOCALAPPDATA%\LushfoilSim\Saved\LushfoilCraft-*, not in this folder."
