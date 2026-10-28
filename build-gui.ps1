#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$compiler = Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
if (-not (Test-Path -LiteralPath $compiler)) { $compiler = Join-Path $env:WINDIR 'Microsoft.NET/Framework/v4.0.30319/csc.exe' }
if (-not (Test-Path -LiteralPath $compiler)) { throw '.NET Framework C# compiler was not found.' }
$output = Join-Path $PSScriptRoot 'STAR-CCM-Codex.exe'
& $compiler /nologo /target:winexe "/out:$output" /reference:System.Windows.Forms.dll (Join-Path $PSScriptRoot 'gui/Launcher.cs')
if ($LASTEXITCODE -ne 0) { throw 'GUI launcher build failed.' }
Write-Host "Built: $output"
