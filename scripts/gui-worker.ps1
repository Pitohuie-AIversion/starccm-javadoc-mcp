#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RequestFile,
    [Parameter(Mandatory)][string]$ResultFile
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
$OutputEncoding = [Console]::OutputEncoding
$repo = Split-Path $PSScriptRoot -Parent
$action = 'unknown'
$resultPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ResultFile)

function Get-Field($Object, [string]$Name, $Default = $null) {
    if ($null -ne $Object -and $Object.PSObject.Properties[$Name]) { return $Object.$Name }
    return $Default
}

function Get-StringField($Object, [string]$Name, [string]$Default = '') {
    $value = Get-Field $Object $Name $Default
    if ($null -eq $value) { return $Default }
    if ($value -isnot [string]) { throw "Request field '$Name' must be a string." }
    return $value
}

function Write-Result($Value) {
    $parent = [IO.Path]::GetDirectoryName($resultPath)
    [void][IO.Directory]::CreateDirectory($parent)
    $temp = Join-Path $parent ('.gui-result-' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [IO.File]::WriteAllText($temp, (ConvertTo-Json -InputObject $Value -Depth 10), (New-Object Text.UTF8Encoding($false)))
        try {
            if ([IO.File]::Exists($resultPath)) {
                [IO.File]::Replace($temp, $resultPath, [System.Management.Automation.Language.NullString]::Value)
            } else { [IO.File]::Move($temp, $resultPath) }
        } catch {
            throw "Could not atomically publish result to '$resultPath'. The operation directory must support file rename and replacement. Use a writable local directory such as TEMP. Details: $($_.Exception.Message)"
        }
    } finally {
        if ([IO.File]::Exists($temp)) { [IO.File]::Delete($temp) }
    }
}

try {
    $requestPath = (Resolve-Path -LiteralPath $RequestFile -ErrorAction Stop).ProviderPath
    if ($requestPath -eq $resultPath) { throw 'Request and result paths must be different.' }
    $request = Get-Content -LiteralPath $requestPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    if ($null -eq $request -or $request -isnot [pscustomobject]) { throw 'Request must be a JSON object.' }
    $action = Get-StringField $request 'action'
    if ($action -notin @('scan', 'verify', 'deploy', 'environment')) { throw "Unknown action: $action" }
    Import-Module (Join-Path $repo 'scripts/Javadoc.psm1') -Force
    Import-Module (Join-Path $repo 'scripts/Executables.psm1') -Force
    $nodeOverride = Get-StringField $request 'nodePath'
    $codexOverride = Get-StringField $request 'codexPath'

    if ($action -eq 'environment') {
        Write-Host 'Checking Node.js and Codex...'
        $issues = New-Object 'System.Collections.Generic.List[string]'
        $runtime = Join-Path $env:USERPROFILE '.cache/codex-runtimes/codex-primary-runtime/dependencies/node'
        $node = $null; $nodeVersion = $null; $nodeReady = $false; $codex = $null
        try {
            $node = Find-Executable $nodeOverride @('node.exe') @((Join-Path $runtime 'bin/node.exe'), (Join-Path $env:ProgramFiles 'nodejs/node.exe'))
            $nodeVersion = (Invoke-Executable -Path $node -Arguments @('--version') -TimeoutSeconds 15 | Out-String).Trim()
            if ($LASTEXITCODE -ne 0 -or $nodeVersion -notmatch '^v(\d+)\.') { throw 'Node.js version could not be read.' }
            if ([int]$Matches[1] -lt 20) { throw 'Node.js 20 or newer is required.' }
            $nodeReady = $true
        } catch { $issues.Add($_.Exception.Message) }
        try {
            $appBins = @(Get-ChildItem -Path (Join-Path $env:LOCALAPPDATA 'OpenAI/Codex/bin/*/codex.exe') -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | ForEach-Object FullName)
            $codex = Find-Executable $codexOverride @('codex.exe', 'codex.cmd', 'codex.ps1') $appBins
        } catch { $issues.Add($_.Exception.Message) }
        Write-Result ([ordered]@{ ok = $true; action = $action; nodePath = $node; nodeVersion = $nodeVersion; nodeReady = $nodeReady; codexPath = $codex; codexReady = [bool]$codex; errors = @($issues.ToArray()) })
        exit 0
    }

    if ($action -eq 'scan') {
        $scanRoot = Get-StringField $request 'scanRoot'
        $fullScan = Get-Field $request 'fullScan' $false
        if ($fullScan -isnot [bool]) { throw "Request field 'fullScan' must be a boolean." }
        $scanArgs = @{ FullScan = $fullScan }
        if (-not [string]::IsNullOrWhiteSpace($scanRoot)) { $scanArgs.ScanRoots = @($scanRoot) }
        Write-Host 'Scanning for supported STAR-CCM+ Javadoc folders and archives...'
        $candidates = @(Find-StarJavadoc @scanArgs | Sort-Object -Property Root, Archive, Prefix -Unique)
        Write-Host "Scan complete: $($candidates.Count) candidate(s)."
        Write-Result ([ordered]@{ ok = $true; action = $action; candidates = @($candidates) })
        exit 0
    }

    $selected = Get-Field $request 'selected'
    if ($null -eq $selected -or $selected -isnot [pscustomobject]) { throw 'Select a documentation candidate before verifying or deploying.' }
    $source = Get-StringField $selected 'Source'
    $reportDir = Get-StringField $request 'reportDirectory' ([IO.Path]::GetDirectoryName($resultPath))
    if (-not [IO.Path]::IsPathRooted($reportDir)) { throw 'reportDirectory must be an absolute path.' }
    $reportDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($reportDir)
    $serverName = Get-StringField $request 'serverName' 'starccm-javadoc'
    if ([string]::IsNullOrWhiteSpace($serverName)) { $serverName = 'starccm-javadoc' }
    if ($serverName -notmatch '^[A-Za-z0-9_-]+$') { throw 'Server name may contain only letters, digits, underscores and hyphens.' }

    if ($source -eq 'folder') {
        $selectedRoot = Get-StringField $selected 'Root'
        if ([string]::IsNullOrWhiteSpace($selectedRoot)) { throw 'The selected documentation folder is missing.' }
        $docRoot = (Resolve-Path -LiteralPath $selectedRoot -ErrorAction Stop).ProviderPath
        if (-not (Test-StarJavadoc $docRoot)) { throw 'Selected documentation is no longer available or its structure changed. Scan again.' }
    } elseif ($source -eq 'archive') {
        $selectedArchive = Get-StringField $selected 'Archive'
        $prefix = Get-StringField $selected 'Prefix'
        if ([string]::IsNullOrWhiteSpace($selectedArchive)) { throw 'The selected archive path is missing.' }
        $archive = (Resolve-Path -LiteralPath $selectedArchive -ErrorAction Stop).ProviderPath
        Write-Host 'Rechecking the selected archive and its Javadoc prefix...'
        $matches = @(Find-StarJavadoc -ScanRoots @($archive) | Where-Object { $_.Source -eq 'archive' -and $_.Archive -eq $archive -and $_.Prefix -ceq $prefix })
        if ($matches.Count -ne 1) { throw 'Selected documentation prefix is no longer present in the archive. Scan again.' }
        Write-Host 'Extracting the selected Javadoc folder...'
        $extractTo = Get-StringField $request 'extractTo' (Join-Path $repo 'local-docs')
        if (-not [IO.Path]::IsPathRooted($extractTo)) { throw 'extractTo must be an absolute path.' }
        $docRoot = Expand-StarJavadoc -Candidate $matches[0] -Destination $extractTo
    } else { throw "Unsupported selected candidate source: $source" }

    $deployArgs = @{ JavadocRoot = $docRoot; ReportDirectory = $reportDir; ServerName = $serverName }
    if ($nodeOverride) { $deployArgs.NodePath = $nodeOverride }
    if ($codexOverride) { $deployArgs.CodexPath = $codexOverride }
    if ($action -eq 'verify') { $deployArgs.SkipRegister = $true }
    Write-Host "Starting $action for: $docRoot"
    & (Join-Path $repo 'deploy-codex.ps1') @deployArgs
    $configHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }
    Write-Result ([ordered]@{
        ok = $true; action = $action; verified = $true; registered = ($action -eq 'deploy')
        docRoot = $docRoot; format = (Get-StarJavadocFormat $docRoot); reportDirectory = $reportDir
        generatedConfigPath = (Join-Path $reportDir 'codex-mcp.generated.toml')
        configurationPath = if ($action -eq 'deploy') { Join-Path $configHome 'config.toml' } else { $null }
        selected = [ordered]@{ Root = $docRoot; Archive = $null; Prefix = ''; Source = 'folder'; Format = (Get-StarJavadocFormat $docRoot) }
    })
    exit 0
} catch {
    $message = $_.Exception.Message
    [Console]::Error.WriteLine("GUI operation failed: $message")
    try { Write-Result ([ordered]@{ ok = $false; action = $action; error = $message }) }
    catch { [Console]::Error.WriteLine("Could not write result JSON: $($_.Exception.Message)") }
    exit 1
}
