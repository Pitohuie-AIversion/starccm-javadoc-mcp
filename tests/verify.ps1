#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $repo 'scripts/Javadoc.psm1') -Force
Import-Module (Join-Path $repo 'scripts/Executables.psm1') -Force
$sandbox = Join-Path ([IO.Path]::GetTempPath()) ('starccm-mcp-test-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($sandbox)
# Include Chinese characters, a space, and an apostrophe without depending on PS5 source encoding.
$unicodeName = ([string][char]0x6587 + [string][char]0x6863) + " with space's"
$root = Join-Path $sandbox $unicodeName
$common = Join-Path $root 'star/common'
[void][IO.Directory]::CreateDirectory($common)
[IO.File]::WriteAllText((Join-Path $root 'type-search-index.js'), 'typeSearchIndex = [{"p":"star.common","l":"Simulation"},{"p":"star.common","l":"RegionManager"}];')
[IO.File]::WriteAllText((Join-Path $root 'member-search-index.js'), 'memberSearchIndex = [{"p":"star.common","c":"Simulation","l":"getRegionManager()","u":"getRegionManager()"}];')
[IO.File]::WriteAllText((Join-Path $common 'Simulation.html'), '<html><body>Simulation <code>public RegionManager getRegionManager()</code></body></html>')
[IO.File]::WriteAllText((Join-Path $sandbox 'outside.html'), 'PRIVATE OUTSIDE CONTENT')
$found = @(Find-StarJavadoc -ScanRoots @($sandbox))
if ($found.Count -ne 1 -or $found[0].Root -ne $root) { throw 'Directory discovery failed.' }
Write-Host 'PASS: folder discovery with Unicode, spaces and apostrophe.'
$archive = Join-Path $sandbox 'java-doc.zip'
[IO.Compression.ZipFile]::CreateFromDirectory($root, $archive, [IO.Compression.CompressionLevel]::Optimal, $true)
$zipped = @(Find-StarJavadoc -ScanRoots @($archive))
if ($zipped.Count -ne 1) { throw 'Archive discovery failed.' }
if (-not $zipped[0].Prefix) { throw 'Nested archive prefix was not discovered.' }
$extracted = Expand-StarJavadoc -Candidate $zipped[0] -Destination (Join-Path $sandbox 'extracted')
if (-not (Test-StarJavadoc $extracted)) { throw 'Extraction failed.' }
Write-Host 'PASS: ZIP/JAR-format discovery and extraction.'
Push-Location $sandbox
try {
    $relativeFound = @(Find-StarJavadoc -ScanRoots @($unicodeName))
    if ($relativeFound.Count -ne 1 -or $relativeFound[0].Root -ne $root) { throw 'Relative scan root resolved against process cwd.' }
    $relativeArchive = @(Find-StarJavadoc -ScanRoots @('java-doc.zip'))
    if ($relativeArchive.Count -ne 1 -or $relativeArchive[0].Archive -ne $archive) { throw 'Relative ZIP path failed.' }
    $relativeExtract = Expand-StarJavadoc -Candidate $relativeArchive[0] -Destination 'relative-extracted'
    if (-not $relativeExtract.StartsWith((Join-Path $sandbox 'relative-extracted'))) { throw 'Relative extraction destination resolved incorrectly.' }
    [IO.File]::WriteAllText((Join-Path $sandbox 'test-launcher.cmd'), '@echo off')
    if ((Find-Executable 'test-launcher.cmd' @() @()) -ne (Join-Path $sandbox 'test-launcher.cmd')) { throw 'Relative executable resolved incorrectly.' }
    & (Join-Path $repo 'deploy-codex.ps1') -ScanRoots @($unicodeName) -ListOnly -ReportDirectory 'relative-reports'
    if (-not (Test-Path -LiteralPath (Join-Path $sandbox 'relative-reports/discovery-report.json'))) { throw 'Relative report path resolved incorrectly.' }
} finally { Pop-Location }
Write-Host 'PASS: relative scan/archive/executable/extraction/report paths follow PowerShell location.'
$empty = Join-Path $sandbox 'empty'
[void][IO.Directory]::CreateDirectory($empty)
if (@(Find-StarJavadoc -ScanRoots @($empty)).Count -ne 0) { throw 'Empty directory incorrectly detected.' }
$limited = $false
try { Expand-StarJavadoc -Candidate $zipped[0] -Destination (Join-Path $sandbox 'size-limit') -MaxBytes 1 | Out-Null }
catch { if ($_.Exception.Message -match 'extraction limit') { $limited = $true } else { throw } }
if (-not $limited) { throw 'Extraction size limit not enforced.' }
Write-Host 'PASS: no false match for empty directory; extraction size limit enforced.'

$evil = Join-Path $sandbox 'unsafe-doc.zip'
$zip = [IO.Compression.ZipFile]::Open($evil, [IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($name in @('type-search-index.js', 'member-search-index.js', 'star/common/Simulation.html', '../escape.html')) {
        $entry = $zip.CreateEntry($name)
        $writer = New-Object IO.StreamWriter($entry.Open())
        try { $writer.Write('test') } finally { $writer.Dispose() }
    }
} finally { $zip.Dispose() }
$bad = @(Find-StarJavadoc -ScanRoots @($evil))
$rejected = $false
try { Expand-StarJavadoc -Candidate $bad[0] -Destination (Join-Path $sandbox 'unsafe-output') | Out-Null }
catch { if ($_.Exception.Message -match 'Unsafe archive path|escapes destination') { $rejected = $true } else { throw } }
if (-not $rejected) { throw 'ZIP traversal was not rejected.' }
Write-Host 'PASS: ZIP path traversal rejected.'

$legacy = Join-Path $sandbox 'legacy-docs'
[void][IO.Directory]::CreateDirectory((Join-Path $legacy 'star/common'))
Copy-Item -LiteralPath (Join-Path $common 'Simulation.html') -Destination (Join-Path $legacy 'star/common/Simulation.html')
[IO.File]::WriteAllText((Join-Path $legacy 'star/common/Region.html'), '<html>Region</html>')
[IO.File]::WriteAllText((Join-Path $legacy 'overview-summary.html'), '<html>Legacy Javadoc</html>')
$legacyFound = @(Find-StarJavadoc -ScanRoots @($legacy))
if ($legacyFound.Count -ne 1 -or $legacyFound[0].Format -ne 'html-fallback') { throw 'Legacy folder not detected.' }
$legacyJar = Join-Path $sandbox 'legacy-doc.jar'
[IO.Compression.ZipFile]::CreateFromDirectory($legacy, $legacyJar, [IO.Compression.CompressionLevel]::Optimal, $true)
$legacyZipped = @(Find-StarJavadoc -ScanRoots @($legacyJar))
if ($legacyZipped.Count -ne 1 -or $legacyZipped[0].Format -ne 'html-fallback') { throw 'Legacy archive not detected.' }
$legacyExtracted = Expand-StarJavadoc -Candidate $legacyZipped[0] -Destination (Join-Path $sandbox 'legacy-extracted')
& (Join-Path $repo 'deploy-codex.ps1') -JavadocRoot $legacyExtracted -SkipRegister -ReportDirectory (Join-Path $sandbox 'reports-legacy')
Write-Host 'PASS: legacy HTML folder and nested JAR discovery, extraction and MCP verification.'

$binaryDir = Join-Path $sandbox 'binary-only'
[void][IO.Directory]::CreateDirectory((Join-Path $binaryDir 'star/common'))
[IO.File]::WriteAllText((Join-Path $binaryDir 'star/common/Simulation.class'), 'not documentation')
$binaryJar = Join-Path $sandbox 'star-program.jar'
[IO.Compression.ZipFile]::CreateFromDirectory($binaryDir, $binaryJar)
if (@(Find-StarJavadoc -ScanRoots @($binaryJar)).Count -ne 0) { throw 'Program JAR was mistaken for Javadoc.' }
Write-Host 'PASS: program JAR is not treated as documentation.'

$oldCodexHome = $env:CODEX_HOME
$oldPath = $env:PATH
$actualCodex = Find-Executable '' @('codex.exe', 'codex.cmd') @()
$actualNode = (Get-Command node.exe -ErrorAction Stop).Source
try {
    $env:CODEX_HOME = Join-Path $sandbox 'isolated-codex'
    [void][IO.Directory]::CreateDirectory($env:CODEX_HOME)
    [IO.File]::WriteAllText((Join-Path $env:CODEX_HOME 'config.toml'), "# preserve-existing-config`n")
    # Hide every real Codex executable from PATH and supply an npm-style .cmd launcher.
    $shimDir = Join-Path $sandbox 'launchers'
    [void][IO.Directory]::CreateDirectory($shimDir)
    $shim = Join-Path $shimDir 'codex.cmd'
    [IO.File]::WriteAllText($shim, "@echo off`r`n`"$actualCodex`" %*`r`nexit /b %errorlevel%`r`n")
    $env:PATH = $shimDir
    $detected = Find-Executable '' @('codex.exe', 'codex.cmd', 'codex.ps1') @()
    if ($detected -ne $shim) { throw 'codex.cmd discovery failed.' }
    $specialDocs = Join-Path $sandbox 'docs&percent%NAME%!bang^caret'
    Copy-Item -LiteralPath $root -Destination $specialDocs -Recurse
    & (Join-Path $repo 'deploy-codex.ps1') -JavadocRoot $specialDocs -NodePath $actualNode -ReportDirectory (Join-Path $sandbox 'reports-modern')
    $config = Get-Content -LiteralPath (Join-Path $env:CODEX_HOME 'config.toml') -Raw
    if (-not $config.Contains('preserve-existing-config') -or -not $config.Contains('starccm-javadoc')) { throw 'Config registration/preservation failed.' }
    if (@(Get-ChildItem -LiteralPath $env:CODEX_HOME -Filter '*.bak').Count -ne 1) { throw 'Missing config backup.' }
    Write-Host 'PASS: codex.cmd detection, registration and effective configuration verification in isolated CODEX_HOME.'
    # Existing configuration must survive a failed documentation validation.
    [IO.File]::WriteAllText((Join-Path $root 'member-search-index.js'), 'corrupt index')
    $failed = $false
    try { & (Join-Path $repo 'deploy-codex.ps1') -JavadocRoot $root -NodePath $actualNode -ReportDirectory (Join-Path $sandbox 'reports-corrupt') }
    catch { if ($_.Exception.Message -match 'MCP verification failed') { $failed = $true } else { throw } }
    if (-not $failed) { throw 'Corrupt documentation was accepted.' }
    if ((Get-Content -LiteralPath (Join-Path $env:CODEX_HOME 'config.toml') -Raw) -ne $config) { throw 'Failed verification changed Codex configuration.' }
    Write-Host 'PASS: failed validation leaves existing Codex configuration intact.'
} finally { $env:CODEX_HOME = $oldCodexHome; $env:PATH = $oldPath }
Write-Host "Test evidence (synthetic Javadoc, not Siemens documentation): $sandbox"
