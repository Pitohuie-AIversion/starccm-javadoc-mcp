#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$JavadocRoot,
    [string[]]$ScanRoots,
    [switch]$FullScan,
    [int]$MaxDepth = 30,
    [int]$CandidateIndex = -1,
    [switch]$ListOnly,
    [switch]$SkipRegister,
    [string]$NodePath,
    [string]$CodexPath,
    [string]$ServerName = 'starccm-javadoc',
    [string]$ExtractTo,
    [string]$ReportDirectory
)
$ErrorActionPreference = 'Stop'
if (-not $ExtractTo) { $ExtractTo = Join-Path $PSScriptRoot 'local-docs' }
if (-not $ReportDirectory) { $ReportDirectory = $PSScriptRoot }
Import-Module (Join-Path $PSScriptRoot 'scripts/Javadoc.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'scripts/Executables.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'scripts/Registration.psm1') -Force

if ($JavadocRoot) {
    $resolved = (Resolve-Path -LiteralPath $JavadocRoot).ProviderPath
    if (-not (Test-StarJavadoc $resolved)) { throw 'Unsupported/incomplete Javadoc. Require Simulation.html with both search indexes, or legacy Region.html and index.html/overview-summary.html.' }
    $candidates = @([pscustomobject]@{ Root = $resolved; Archive = $null; Prefix = ''; Source = 'folder'; Format = (Get-StarJavadocFormat $resolved) })
} else {
    Write-Host 'Scanning for STAR-CCM+ Javadoc (use -ScanRoots or -FullScan for other locations)...'
    $candidates = @(Find-StarJavadoc -ScanRoots $ScanRoots -FullScan:$FullScan -MaxDepth $MaxDepth |
        Sort-Object -Property Root, Archive, Prefix -Unique)
}
$ReportDirectory = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ReportDirectory)
[void][IO.Directory]::CreateDirectory($ReportDirectory)
$report = Join-Path $ReportDirectory 'discovery-report.json'
ConvertTo-Json -InputObject @($candidates) -Depth 5 | Set-Content -LiteralPath $report -Encoding UTF8
for ($i = 0; $i -lt $candidates.Count; $i++) {
    $c = $candidates[$i]
    Write-Host "[$i] $($c.Source) [$($c.Format)]: $($c.Root)$($c.Archive) $($c.Prefix)"
}
Write-Host "Discovery report: $report"
if ($ListOnly) { return }
if ($candidates.Count -eq 0) { throw 'No supported Javadoc found. Use -ScanRoots <install-folder-or-zip>, -FullScan, or install the STAR-CCM+ Java API documentation. Nothing was registered.' }
if ($CandidateIndex -lt 0) {
    if ($candidates.Count -gt 1) { throw 'Multiple Javadoc versions found. Rerun with -CandidateIndex <number> or -JavadocRoot <html-folder> to choose the simulation version.' }
    $CandidateIndex = 0
}
if ($CandidateIndex -ge $candidates.Count) { throw 'CandidateIndex is outside the discovery results.' }
$selected = $candidates[$CandidateIndex]
if ($selected.Archive) { $docRoot = Expand-StarJavadoc -Candidate $selected -Destination $ExtractTo }
else { $docRoot = $selected.Root }

$runtime = Join-Path $env:USERPROFILE '.cache/codex-runtimes/codex-primary-runtime/dependencies/node'
$node = Find-Executable $NodePath 'node.exe' @((Join-Path $runtime 'bin/node.exe'), (Join-Path $env:ProgramFiles 'nodejs/node.exe'))
$nodeVersion = Invoke-Executable -Path $node -Arguments @('--version') -TimeoutSeconds 15
if ($LASTEXITCODE -ne 0 -or [int]($nodeVersion.TrimStart('v').Split('.')[0]) -lt 20) { throw 'Node.js 20 or newer is required by the locked dependencies.' }
$codex = $null
if (-not $SkipRegister) {
    $appBins = @(Get-ChildItem -Path (Join-Path $env:LOCALAPPDATA 'OpenAI/Codex/bin/*/codex.exe') -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | ForEach-Object FullName)
    $codex = Find-Executable $CodexPath @('codex.exe', 'codex.cmd', 'codex.ps1') $appBins
}
Push-Location $PSScriptRoot
$originalPath = $env:PATH
try {
    $env:PATH = [IO.Path]::GetDirectoryName($node) + [IO.Path]::PathSeparator + $env:PATH
    if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'node_modules/@modelcontextprotocol/sdk/package.json')) -or
        -not (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'node_modules/zod/package.json'))) {
        Write-Host 'Installing locked production dependencies...'
        $npm = Get-Command npm.cmd -ErrorAction SilentlyContinue
        if ($npm) { & $npm.Source ci --omit=dev --ignore-scripts --no-audit --no-fund }
        else {
            $pnpm = Join-Path $runtime 'node_modules/pnpm/bin/pnpm.cjs'
            if (-not (Test-Path -LiteralPath $pnpm)) { throw 'npm.cmd not found. Install the official Node.js LTS distribution, which includes npm.' }
            & $node $pnpm install --prod --frozen-lockfile --ignore-scripts
        }
        if ($LASTEXITCODE -ne 0) { throw 'Dependency installation failed.' }
    }
    # Actual MCP initialize, tools/list, search_api, and get_doc before registration.
    & $node (Join-Path $PSScriptRoot 'scripts/smoke-test.mjs') $docRoot
    if ($LASTEXITCODE -ne 0) { throw 'MCP verification failed. Codex configuration was not changed.' }
    $server = Join-Path $PSScriptRoot 'server.mjs'
    # JSON-quoted TOML strings also handle apostrophes and spaces in Windows paths.
    $commandToml = ConvertTo-Json -InputObject $node -Compress
    $argsToml = ConvertTo-Json -InputObject @($server, $docRoot) -Compress
    $snippet = '[mcp_servers.' + (ConvertTo-Json -InputObject $ServerName -Compress) + "]`ncommand = $commandToml`nargs = $argsToml`n"
    Set-Content -LiteralPath (Join-Path $ReportDirectory 'codex-mcp.generated.toml') -Value $snippet -Encoding UTF8
    if (-not $SkipRegister) {
        $configHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }
        Register-StarMcp -Codex $codex -Node $node -Server $server -DocRoot $docRoot -Name $ServerName -ConfigHome $configHome
        Write-Host 'Registered configuration matches the tested MCP command. Restart Codex, then ask it to call search_api and get_doc for final session acceptance.'
    } else { Write-Host 'Verified successfully; registration skipped. See codex-mcp.generated.toml.' }
} finally { $env:PATH = $originalPath; Pop-Location }
