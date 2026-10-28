#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$worker = Join-Path $repo 'scripts/gui-worker.ps1'
$sandbox = Join-Path $env:TEMP ('starccm-gui-worker-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($sandbox)
Add-Type -AssemblyName System.IO.Compression.FileSystem
$counter = 0
$configHome = Join-Path $sandbox 'isolated-codex'
[void][IO.Directory]::CreateDirectory($configHome)
[IO.File]::WriteAllText((Join-Path $configHome 'config.toml'), '# untouched by verify')
$oldConfigHome = $env:CODEX_HOME

function Invoke-TestWorker($Request, [bool]$ShouldSucceed = $true, [string]$Raw = '') {
    $script:counter++
    $runDir = Join-Path $sandbox "run-$script:counter"
    [void][IO.Directory]::CreateDirectory($runDir)
    $requestPath = Join-Path $runDir 'request.json'
    $resultPath = Join-Path $runDir 'result.json'
    if ($Raw) { [IO.File]::WriteAllText($requestPath, $Raw) }
    else {
        $Request.reportDirectory = $runDir
        $Request.extractTo = Join-Path $sandbox 'extracted-docs'
        [IO.File]::WriteAllText($requestPath, (ConvertTo-Json -InputObject $Request -Depth 8), (New-Object Text.UTF8Encoding($false)))
    }
    $workerLog = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $worker -RequestFile $requestPath -ResultFile $resultPath
    $code = $LASTEXITCODE
    $workerLog | Set-Content -LiteralPath (Join-Path $runDir 'stdout.log') -Encoding UTF8
    if (-not (Test-Path -LiteralPath $resultPath)) { throw 'Worker did not produce structured result.' }
    $result = Get-Content -LiteralPath $resultPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($ShouldSucceed -and ($code -ne 0 -or -not $result.ok)) { throw "Expected success: $($result.error)" }
    if (-not $ShouldSucceed -and ($code -eq 0 -or $result.ok)) { throw 'Expected a failed operation.' }
    if (@(Get-ChildItem -LiteralPath $runDir -Filter '.gui-result-*.tmp').Count -ne 0) { throw 'Atomic result left a temporary file.' }
    return $result
}

try {
    $env:CODEX_HOME = $configHome
    $docs = Join-Path $sandbox "docs & space's"
    [void][IO.Directory]::CreateDirectory((Join-Path $docs 'star/common'))
    [IO.File]::WriteAllText((Join-Path $docs 'type-search-index.js'), 'typeSearchIndex=[{"p":"star.common","l":"Simulation"}];')
    [IO.File]::WriteAllText((Join-Path $docs 'member-search-index.js'), 'memberSearchIndex=[{"p":"star.common","c":"Simulation","l":"getRegionManager()","u":"getRegionManager()"}];')
    [IO.File]::WriteAllText((Join-Path $docs 'star/common/Simulation.html'), '<html><body>Simulation getRegionManager()</body></html>')
    $scan = Invoke-TestWorker @{ action = 'scan'; scanRoot = $docs; fullScan = $false }
    if (@($scan.candidates).Count -ne 1 -or $scan.candidates[0].Root -ne $docs) { throw 'Folder scan identity mismatch.' }
    $verified = Invoke-TestWorker @{ action = 'verify'; selected = $scan.candidates[0] }
    if (-not $verified.verified -or $verified.registered -or $verified.docRoot -ne $docs) { throw 'Verify result is incorrect.' }
    if ([IO.File]::ReadAllText((Join-Path $configHome 'config.toml')) -ne '# untouched by verify') { throw 'Verify modified Codex config.' }
    Write-Host 'PASS: folder scan and MCP verification preserve existing Codex configuration.'

    $zip = Join-Path $sandbox 'nested-api.zip'
    [IO.Compression.ZipFile]::CreateFromDirectory($docs, $zip, [IO.Compression.CompressionLevel]::Optimal, $true)
    $archiveScan = Invoke-TestWorker @{ action = 'scan'; scanRoot = $zip; fullScan = $false }
    if (@($archiveScan.candidates).Count -ne 1 -or $archiveScan.candidates[0].Archive -ne $zip -or -not $archiveScan.candidates[0].Prefix) { throw 'Archive identity mismatch.' }
    $archiveVerified = Invoke-TestWorker @{ action = 'verify'; selected = $archiveScan.candidates[0] }
    if ($archiveVerified.selected.Source -ne 'folder' -or -not (Test-Path -LiteralPath $archiveVerified.docRoot)) { throw 'Archive verify did not return extracted root.' }
    if (-not [IO.Path]::GetFullPath($archiveVerified.docRoot).StartsWith(([IO.Path]::GetFullPath((Join-Path $sandbox 'extracted-docs')) + [IO.Path]::DirectorySeparatorChar), [StringComparison]::OrdinalIgnoreCase)) { throw 'Test extraction escaped its isolated directory.' }
    $stale = $archiveScan.candidates[0]
    $stale.Prefix = 'missing-prefix/'
    $failure = Invoke-TestWorker @{ action = 'verify'; selected = $stale } $false
    if ($failure.error -notmatch 'prefix') { throw 'Stale selection did not explain archive identity mismatch.' }
    Write-Host 'PASS: nested archive extraction, selected-prefix validation, and reusable extracted selection.'

    $environment = Invoke-TestWorker @{ action = 'environment' }
    if (-not $environment.nodeReady -or -not $environment.nodePath) { throw 'Available Node runtime was not detected.' }
    $missing = Invoke-TestWorker @{ action = 'environment'; nodePath = (Join-Path $sandbox 'missing-node.exe'); codexPath = (Join-Path $sandbox 'missing-codex.exe') }
    if ($missing.nodeReady -or $missing.codexReady -or @($missing.errors).Count -ne 2) { throw 'Environment failures not returned as diagnostic results.' }
    $repeatRequest = Join-Path $sandbox "run-$script:counter/request.json"
    $repeatResult = Join-Path $sandbox "run-$script:counter/result.json"
    [IO.File]::WriteAllText($repeatResult, '{"ok":false,"stale":true}')
    $repeatLog = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $worker -RequestFile $repeatRequest -ResultFile $repeatResult
    if ($LASTEXITCODE -ne 0) { throw 'Replacing an existing result failed.' }
    $replacement = Get-Content -LiteralPath $repeatResult -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $replacement.ok -or $replacement.PSObject.Properties['stale']) { throw 'Existing result was not atomically replaced.' }
    [IO.File]::WriteAllText((Join-Path $docs '.starccm-test-fixture'), 'Synthetic test data. Not Siemens documentation.')
    $excluded = Invoke-TestWorker @{ action = 'scan'; scanRoot = $docs; fullScan = $false }
    if (@($excluded.candidates).Count -ne 0) { throw 'Marked synthetic documentation was offered for deployment.' }
    $markedZip = Join-Path $sandbox 'marked-test-docs.zip'
    [IO.Compression.ZipFile]::CreateFromDirectory($docs, $markedZip)
    $excludedArchive = Invoke-TestWorker @{ action = 'scan'; scanRoot = $markedZip; fullScan = $false }
    if (@($excludedArchive.candidates).Count -ne 0) { throw 'Marked synthetic archive was offered for deployment.' }
    Write-Host 'PASS: marked synthetic folders and archives are excluded from deployment candidates.'
    Invoke-TestWorker @{} $false '{ not JSON' | Out-Null
    Invoke-TestWorker @{ action = 'invalid' } $false | Out-Null
    Invoke-TestWorker @{ action = 'scan'; fullScan = 'true' } $false | Out-Null
    Invoke-TestWorker @{ action = 'deploy' } $false | Out-Null
    Write-Host 'PASS: environment diagnostics and invalid requests return structured errors.'
} finally {
    $env:CODEX_HOME = $oldConfigHome
    [IO.File]::WriteAllText((Join-Path $sandbox '.starccm-test-fixture'), 'Synthetic worker self-test data. Not Siemens documentation.')
}
Write-Host "GUI worker test evidence: $sandbox"
