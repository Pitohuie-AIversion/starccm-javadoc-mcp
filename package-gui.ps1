#Requires -Version 5.1
[CmdletBinding()]
param([string]$OutputPath)
$ErrorActionPreference = 'Stop'
if (-not $OutputPath) { $OutputPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'starccm-javadoc-codex-gui.zip' }
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$repoRoot = [IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\', '/')
$target = [IO.Path]::GetFullPath($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath))
if ($target.Equals($repoRoot, [StringComparison]::OrdinalIgnoreCase) -or $target.StartsWith($repoRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'The ZIP output must be outside the source directory to avoid overwriting source files.'
}
if ([IO.Path]::GetExtension($target) -ine '.zip') { throw 'OutputPath must have a .zip extension.' }
$targetDirectory = [IO.Path]::GetDirectoryName($target)
if (-not [IO.Directory]::Exists($targetDirectory)) { throw 'The output directory does not exist.' }
$files = @('LICENSE','README.md','README-Codex.zh-CN.md','README-GUI.en.md','CHECKS.md','package.json','package-lock.json','pnpm-lock.yaml','server.mjs','deploy-codex.ps1','gui.ps1','build-gui.ps1','package-gui.ps1','STAR-CCM-Codex.exe')
foreach ($folder in @('lib','scripts','tests')) {
    $files += Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot $folder) -File | ForEach-Object { $folder + '/' + $_.Name }
}
$files += @('gui/Launcher.cs','gui/ProcessRunner.cs','gui/MainWindow.xaml','gui/strings.json')
foreach ($relative in $files | Where-Object { $_ -ne 'STAR-CCM-Codex.exe' }) {
    if (-not [IO.File]::Exists((Join-Path $PSScriptRoot $relative))) { throw "Required package source is missing: $relative" }
}
& (Join-Path $PSScriptRoot 'build-gui.ps1')
if (-not [IO.File]::Exists((Join-Path $PSScriptRoot 'STAR-CCM-Codex.exe'))) { throw 'The GUI launcher was not built.' }
$token = [guid]::NewGuid().ToString('N')
$stage = Join-Path $targetDirectory ('.starccm-package-' + $token + '.zip')
$hashStage = Join-Path $targetDirectory ('.starccm-package-' + $token + '.sha256')
$backup = Join-Path $targetDirectory ('.starccm-package-' + $token + '.previous.zip')
$hashBackup = Join-Path $targetDirectory ('.starccm-package-' + $token + '.previous.sha256')
$hashTarget = $target + '.sha256'
$hadZip = [IO.File]::Exists($target)
$hadHash = [IO.File]::Exists($hashTarget)
$zipPublished = $false
$hashPublished = $false
$preserveBackups = $false

function Publish-PackageFile([string]$Source, [string]$Destination, [string]$BackupPath, [bool]$Existed) {
    if ($Existed) { [IO.File]::Replace($Source, $Destination, $BackupPath) }
    else { [IO.File]::Move($Source, $Destination) }
}

try {
    $stream = [IO.File]::Open($stage, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write)
    $zip = $null
    try {
        $zip = New-Object IO.Compression.ZipArchive($stream, [IO.Compression.ZipArchiveMode]::Create)
        foreach ($relative in $files) {
            $source = Join-Path $PSScriptRoot $relative
            [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $source, $relative, [IO.Compression.CompressionLevel]::Optimal)
        }
    } finally { if ($zip) { $zip.Dispose() }; $stream.Dispose() }
    $archive = [IO.Compression.ZipFile]::OpenRead($stage)
    try {
        if ($archive.Entries.Count -ne $files.Count) { throw 'Archive entry count mismatch.' }
        foreach ($entry in $archive.Entries) {
            $entryStream = $entry.Open()
            $sha = [Security.Cryptography.SHA256]::Create()
            try { $packedHash = [BitConverter]::ToString($sha.ComputeHash($entryStream)).Replace('-', '') }
            finally { $entryStream.Dispose(); $sha.Dispose() }
            $sourceHash = (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $entry.FullName) -Algorithm SHA256).Hash
            if ($packedHash -ne $sourceHash) { throw "Archive content mismatch: $($entry.FullName)" }
        }
    } finally { $archive.Dispose() }
    $hash = (Get-FileHash -LiteralPath $stage -Algorithm SHA256).Hash
    [IO.File]::WriteAllText($hashStage, $hash + '  ' + [IO.Path]::GetFileName($target) + [Environment]::NewLine)
    Publish-PackageFile $stage $target $backup $hadZip
    $zipPublished = $true
    Publish-PackageFile $hashStage $hashTarget $hashBackup $hadHash
    $hashPublished = $true
    Write-Host "Verified $($files.Count) files: $target"
    Write-Host "SHA256: $hash"
} catch {
    $failure = $_
    # Two files cannot be committed as a single filesystem operation. If the checksum
    # publication fails, restore the previous ZIP so it still matches its old hash.
    try {
        if ($zipPublished -and -not $hashPublished) {
            if ($hadZip) { [IO.File]::Replace($backup, $target, [System.Management.Automation.Language.NullString]::Value) }
            elseif ([IO.File]::Exists($target)) { [IO.File]::Delete($target) }
        }
    } catch {
        $preserveBackups = $true
        Write-Warning "Could not restore the previous package. Preserved backup: $backup. Details: $($_.Exception.Message)"
    }
    throw $failure
} finally {
    $cleanupPaths = @($stage, $hashStage)
    if (-not $preserveBackups) { $cleanupPaths += @($backup, $hashBackup) }
    foreach ($cleanupPath in $cleanupPaths) {
        # Only delete the known, non-recursive staging files in the verified output directory.
        if ([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($cleanupPath)) -ne $targetDirectory) { throw 'Staging cleanup escaped the output directory.' }
        if ([IO.File]::Exists($cleanupPath)) { [IO.File]::Delete($cleanupPath) }
    }
}
