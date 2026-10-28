Set-StrictMode -Version Latest
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Test-StarJavadoc {
    param([string]$Path)
    return $null -ne (Get-StarJavadocFormat $Path)
}

function Get-StarJavadocFormat {
    param([string]$Path)
    if (Test-Path -LiteralPath (Join-Path $Path '.starccm-test-fixture') -PathType Leaf -ErrorAction SilentlyContinue) { return $null }
    if (-not (Test-Path -LiteralPath (Join-Path $Path 'star/common/Simulation.html') -PathType Leaf -ErrorAction SilentlyContinue)) { return $null }
    if ((Test-Path -LiteralPath (Join-Path $Path 'type-search-index.js') -PathType Leaf -ErrorAction SilentlyContinue) -and
        (Test-Path -LiteralPath (Join-Path $Path 'member-search-index.js') -PathType Leaf -ErrorAction SilentlyContinue)) { return 'indexed' }
    if ((Test-Path -LiteralPath (Join-Path $Path 'star/common/Region.html') -PathType Leaf -ErrorAction SilentlyContinue) -and
        ((Test-Path -LiteralPath (Join-Path $Path 'index.html') -PathType Leaf -ErrorAction SilentlyContinue) -or
         (Test-Path -LiteralPath (Join-Path $Path 'overview-summary.html') -PathType Leaf -ErrorAction SilentlyContinue))) { return 'html-fallback' }
    return $null
}

function Get-StarScanRoots {
    $roots = New-Object 'System.Collections.Generic.List[string]'
    if ($env:STARCCM_DOC) { $roots.Add($env:STARCCM_DOC) }
    foreach ($key in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall')) {
        Get-ChildItem $key -ErrorAction SilentlyContinue | ForEach-Object {
            $item = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
            if ($item -and $item.PSObject.Properties['DisplayName'] -and $item.DisplayName -match 'STAR.?CCM|Simcenter') {
                if ($item.PSObject.Properties['InstallLocation'] -and $item.InstallLocation) { $roots.Add($item.InstallLocation) }
            }
        }
    }
    foreach ($drive in [System.IO.DriveInfo]::GetDrives()) {
        if ($drive.IsReady -and $drive.DriveType -eq 'Fixed') {
            foreach ($name in @('Program Files', 'Program Files (x86)', 'Siemens', 'CD-adapco', 'Simcenter', 'STAR-CCM+', 'Applications', 'Apps')) {
                $p = Join-Path $drive.RootDirectory.FullName $name
                if (Test-Path -LiteralPath $p -PathType Container -ErrorAction SilentlyContinue) { $roots.Add($p) }
            }
            Get-ChildItem -LiteralPath $drive.RootDirectory.FullName -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match 'star.?ccm|siemens|simcenter|cd.adapco' } |
                ForEach-Object { $roots.Add($_.FullName) }
        }
    }
    foreach ($p in @([Environment]::GetFolderPath('Desktop'), (Join-Path $env:USERPROFILE 'Downloads'), (Join-Path $env:USERPROFILE 'Documents'))) {
        if (Test-Path -LiteralPath $p -PathType Container -ErrorAction SilentlyContinue) { $roots.Add($p) }
    }
    $roots | Sort-Object -Unique
}

function Get-StarArchiveCandidates {
    param([string]$Path)
    $zip = $null
    try {
        $Path = (Resolve-Path -LiteralPath $Path).ProviderPath
        $zip = [IO.Compression.ZipFile]::OpenRead($Path)
        $names = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
        foreach ($entry in $zip.Entries) { [void]$names.Add($entry.FullName.Replace('\', '/')) }
        foreach ($name in $names) {
            if ($name -match '(^|/)star/common/Simulation\.html$') {
                $prefix = $name.Substring(0, $name.Length - 'star/common/Simulation.html'.Length)
                if ($names.Contains($prefix + '.starccm-test-fixture')) { continue }
                $format = $null
                if ($names.Contains($prefix + 'type-search-index.js') -and $names.Contains($prefix + 'member-search-index.js')) { $format = 'indexed' }
                elseif ($names.Contains($prefix + 'star/common/Region.html') -and ($names.Contains($prefix + 'index.html') -or $names.Contains($prefix + 'overview-summary.html'))) { $format = 'html-fallback' }
                if ($format) { [pscustomobject]@{ Root = $null; Archive = $Path; Prefix = $prefix; Source = 'archive'; Format = $format } }
            }
        }
    } catch { Write-Verbose "Cannot inspect archive '$Path': $_" }
    finally { if ($zip) { $zip.Dispose() } }
}

function Find-StarJavadoc {
    [CmdletBinding()]
    param([string[]]$ScanRoots, [switch]$FullScan, [int]$MaxDepth = 30)
    if (-not $ScanRoots) { $ScanRoots = @(Get-StarScanRoots) }
    if ($FullScan) {
        $ScanRoots += @([IO.DriveInfo]::GetDrives() | Where-Object { $_.IsReady -and $_.DriveType -eq 'Fixed' } | ForEach-Object { $_.RootDirectory.FullName })
    }
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $queue = New-Object 'System.Collections.Generic.Queue[object]'
    foreach ($root in $ScanRoots) {
        if (Test-Path -LiteralPath $root -PathType Leaf -ErrorAction SilentlyContinue) {
            if ([IO.Path]::GetExtension($root) -match '^\.(zip|jar)$') { Get-StarArchiveCandidates $root }
        } elseif (Test-Path -LiteralPath $root -PathType Container -ErrorAction SilentlyContinue) {
            $queue.Enqueue(@((Resolve-Path -LiteralPath $root).ProviderPath, 0))
        } else { Write-Warning "Scan root does not exist: $root" }
    }
    $count = 0
    while ($queue.Count -gt 0) {
        $next = $queue.Dequeue(); $dir = [string]$next[0]; $depth = [int]$next[1]
        if (-not $seen.Add($dir)) { continue }
        if (Test-Path -LiteralPath (Join-Path $dir '.starccm-test-fixture') -PathType Leaf -ErrorAction SilentlyContinue) { continue }
        $count++
        if ($count % 500 -eq 0) { Write-Progress -Activity 'Scanning for STAR-CCM+ Javadoc' -Status "$count folders: $dir" }
        if (Test-StarJavadoc $dir) {
            [pscustomobject]@{ Root = $dir; Archive = $null; Prefix = ''; Source = 'folder'; Format = (Get-StarJavadocFormat $dir) }
            continue
        }
        if ($depth -ge $MaxDepth) { continue }
        foreach ($entry in (Get-ChildItem -LiteralPath $dir -Force -ErrorAction SilentlyContinue)) {
            if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
            if ($entry.PSIsContainer) {
                if ($entry.Name -match '^(node_modules|\.git|\.svn|Windows|WinSxS|\$Recycle\.Bin|System Volume Information|\.codex|\.cache|\.venv|venv)$') { continue }
                $queue.Enqueue(@($entry.FullName, $depth + 1))
            } elseif ($entry.Extension -match '^\.(zip|jar)$' -and ($entry.Name -match 'doc|help|star|ccmp|client' -or $dir -match 'star.?ccm|siemens|simcenter|cd.adapco')) {
                Get-StarArchiveCandidates $entry.FullName
            }
        }
    }
    Write-Progress -Activity 'Scanning for STAR-CCM+ Javadoc' -Completed
}

function Expand-StarJavadoc {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Candidate, [Parameter(Mandatory)][string]$Destination, [long]$MaxBytes = 8GB)
    $base = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Destination)
    [void][IO.Directory]::CreateDirectory($base)
    # A new, unique directory avoids overwriting files or following existing links.
    $target = Join-Path $base ('javadoc-' + [guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($target)
    $zip = [IO.Compression.ZipFile]::OpenRead($Candidate.Archive)
    try {
        $entries = @($zip.Entries | Where-Object { $_.FullName.Replace('\', '/').StartsWith($Candidate.Prefix, [StringComparison]::Ordinal) })
        [long]$total = 0
        foreach ($entry in $entries) {
            $total += $entry.Length
            if ($total -gt $MaxBytes) { throw "Archive exceeds extraction limit ($MaxBytes bytes)." }
            $rel = $entry.FullName.Replace('\', '/').Substring($Candidate.Prefix.Length)
            if (-not $rel) { continue }
            if ([IO.Path]::IsPathRooted($rel) -or $rel.Contains(':') -or ($rel.Split('/') -contains '..')) { throw "Unsafe archive path: $rel" }
            $dest = [IO.Path]::GetFullPath((Join-Path $target $rel))
            if (-not $dest.StartsWith($target + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw "Archive path escapes destination: $rel" }
            if ($rel.EndsWith('/')) { [void][IO.Directory]::CreateDirectory($dest); continue }
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($dest))
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $dest, $false)
        }
    } finally { $zip.Dispose() }
    if (-not (Test-StarJavadoc $target)) { throw "Extracted documentation is incomplete: $target" }
    return $target
}

Export-ModuleMember -Function Test-StarJavadoc, Get-StarJavadocFormat, Get-StarScanRoots, Find-StarJavadoc, Expand-StarJavadoc
