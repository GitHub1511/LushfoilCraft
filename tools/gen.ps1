# Compiles tools/Gen.cs with the framework's csc.exe and renders the title images (lc_logo, lc_credits) into textures/.
param([string]$Out = $env:TEMP)
$src = Split-Path $PSScriptRoot -Parent
$exe = Join-Path $Out "LushfoilGen.exe"
& "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe" /nologo /out:$exe /r:System.Drawing.dll (Join-Path $PSScriptRoot "Gen.cs") | Out-Null
foreach ($m in "logo", "credits") { & $exe $m $src }
