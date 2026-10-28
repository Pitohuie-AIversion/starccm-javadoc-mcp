#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$repository = Split-Path $PSScriptRoot -Parent
$sandbox = Join-Path ([IO.Path]::GetTempPath()) ('starccm-package-test-' + [guid]::NewGuid().ToString('N'))
$fixture = Join-Path $sandbox 'source'
[void][IO.Directory]::CreateDirectory($fixture)
foreach ($directory in @('gui','lib','scripts','tests')) { [void][IO.Directory]::CreateDirectory((Join-Path $fixture $directory)) }
$sources = @('LICENSE','README.md','README-Codex.zh-CN.md','README-GUI.en.md','CHECKS.md','package.json','package-lock.json','pnpm-lock.yaml','server.mjs','deploy-codex.ps1','gui.ps1','gui/Launcher.cs','gui/ProcessRunner.cs','gui/MainWindow.xaml','gui/strings.json')
foreach ($source in $sources) { [IO.File]::WriteAllText((Join-Path $fixture $source), 'synthetic packaging fixture') }
[IO.File]::WriteAllText((Join-Path $fixture 'build-gui.ps1'), '[IO.File]::WriteAllText((Join-Path $PSScriptRoot ''STAR-CCM-Codex.exe''), ''synthetic launcher'')')
Copy-Item -LiteralPath (Join-Path $repository 'package-gui.ps1') -Destination (Join-Path $fixture 'package-gui.ps1')
$output = Join-Path $sandbox 'release.zip'
[IO.File]::WriteAllText($output, 'previous package bytes')
[IO.File]::WriteAllText(($output + '.sha256'), 'previous checksum bytes')
$originalZip = (Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash
$originalHash = (Get-FileHash -LiteralPath ($output + '.sha256') -Algorithm SHA256).Hash
$powershell = Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'

function Invoke-Package([string]$Destination, [bool]$ExpectSuccess) {
    $savedPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $result = & $powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $fixture 'package-gui.ps1') -OutputPath $Destination 2>&1
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $savedPreference }
    if (($code -eq 0) -ne $ExpectSuccess) { throw "Unexpected packaging exit code ${code}: $($result | Out-String)" }
}

function Assert-Preserved {
    if ((Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash -ne $originalZip) { throw 'Failed build changed the previous ZIP.' }
    if ((Get-FileHash -LiteralPath ($output + '.sha256') -Algorithm SHA256).Hash -ne $originalHash) { throw 'Failed build changed the previous checksum.' }
    if (@(Get-ChildItem -LiteralPath $sandbox -Filter '.starccm-package-*' -File).Count -ne 0) { throw 'Failed build left staging files behind.' }
}

# A source that disappears or cannot be opened after preflight must leave the
# published pair intact, even if earlier ZIP entries have already been written.
$lockedSource = [IO.File]::Open((Join-Path $fixture 'README.md'), [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None)
try { Invoke-Package $output $false } finally { $lockedSource.Dispose() }
Assert-Preserved
Write-Host 'PASS: an entry-read failure preserves the previous ZIP and checksum.'

# The ZIP and checksum cannot be committed in one filesystem operation. A failure
# publishing the second file must restore the original ZIP.
$lockedChecksum = [IO.File]::Open(($output + '.sha256'), [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
try { Invoke-Package $output $false } finally { $lockedChecksum.Dispose() }
Assert-Preserved
Write-Host 'PASS: checksum publication failure rolls back the ZIP.'

$freshOutput = Join-Path $sandbox 'fresh.zip'
[void][IO.Directory]::CreateDirectory($freshOutput + '.sha256')
Invoke-Package $freshOutput $false
if ([IO.File]::Exists($freshOutput)) { throw 'Failed first publication left a ZIP without its checksum.' }
if (-not [IO.Directory]::Exists($freshOutput + '.sha256')) { throw 'Failure changed a pre-existing checksum-path directory.' }
Assert-Preserved
Write-Host 'PASS: failed first publication removes only its new ZIP and preserves existing output data.'

Invoke-Package (Join-Path $fixture 'release.zip') $false
if ([IO.File]::Exists((Join-Path $fixture 'release.zip'))) { throw 'Output was created in the source directory.' }
$sourceDigest = (Get-FileHash -LiteralPath (Join-Path $fixture 'gui.ps1') -Algorithm SHA256).Hash
Invoke-Package (Join-Path $fixture 'gui.ps1') $false
if ((Get-FileHash -LiteralPath (Join-Path $fixture 'gui.ps1') -Algorithm SHA256).Hash -ne $sourceDigest) { throw 'Output overwrote a source file.' }
Write-Host 'PASS: source-directory output and source-file overwrites are rejected.'

Invoke-Package $output $true
$publishedHash = ([IO.File]::ReadAllText($output + '.sha256') -split '\s+')[0]
if ($publishedHash -ne (Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash) { throw 'Published checksum does not match ZIP.' }
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead($output)
try {
    foreach ($required in @('gui/strings.json','README-GUI.en.md','STAR-CCM-Codex.exe')) {
        if (-not $archive.GetEntry($required)) { throw "Missing deliverable: $required" }
    }
} finally { $archive.Dispose() }
if (@(Get-ChildItem -LiteralPath $sandbox -Filter '.starccm-package-*' -File).Count -ne 0) { throw 'Successful build left staging files behind.' }
Write-Host 'PASS: successful replacement includes language assets and a matching SHA-256.'
$newOutput = Join-Path $sandbox 'new.zip'
Invoke-Package $newOutput $true
if (([IO.File]::ReadAllText($newOutput + '.sha256') -split '\s+')[0] -ne (Get-FileHash -LiteralPath $newOutput -Algorithm SHA256).Hash) { throw 'First-publication checksum mismatch.' }
Write-Host 'PASS: publishing a new ZIP/checksum pair succeeds.'
Write-Host "Packaging evidence: $sandbox"
