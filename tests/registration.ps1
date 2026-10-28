#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts/Registration.psm1') -Force
$sandbox = Join-Path $env:TEMP ('starccm-registration-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($sandbox)
$fake = Join-Path $sandbox 'fake-codex.ps1'
@'
$config = Join-Path $env:STARCCM_TEST_CONFIG_HOME 'config.toml'
if ($args[1] -eq 'add') {
    [IO.File]::WriteAllText($config, '# changed-by-add')
    $global:LASTEXITCODE = if ($env:STARCCM_TEST_FAIL -eq 'add') { 1 } else { 0 }
    return
}
$global:LASTEXITCODE = 0
switch ($env:STARCCM_TEST_FAIL) {
    'get' { $global:LASTEXITCODE = 1 }
    'json' { 'not JSON' }
    'mismatch' { '{"enabled":false,"transport":{"type":"stdio","command":"wrong","args":[]}}' }
    'concurrent' { [IO.File]::WriteAllText($config, '# later-user-change'); $global:LASTEXITCODE = 1 }
}
'@ | Set-Content -LiteralPath $fake -Encoding UTF8
$oldHome = $env:STARCCM_TEST_CONFIG_HOME
$oldMode = $env:STARCCM_TEST_FAIL
try {
    foreach ($original in @($true, $false)) {
        foreach ($mode in @('add', 'get', 'json', 'mismatch')) {
            $case = Join-Path $sandbox "$original-$mode"
            [void][IO.Directory]::CreateDirectory($case)
            $config = Join-Path $case 'config.toml'
            if ($original) { [IO.File]::WriteAllText($config, '# original') }
            $env:STARCCM_TEST_CONFIG_HOME = $case
            $env:STARCCM_TEST_FAIL = $mode
            $failed = $false
            try { Register-StarMcp -Codex $fake -Node 'node.exe' -Server 'server.mjs' -DocRoot 'docs' -Name 'test' -ConfigHome $case }
            catch { $failed = $true }
            if (-not $failed) { throw "Expected failure: $mode" }
            if ($original) {
                if ([IO.File]::ReadAllText($config) -ne '# original') { throw "Original config not restored: $mode" }
            } elseif (Test-Path -LiteralPath $config) { throw "Unexpected config remains: $mode" }
        }
    }
    $case = Join-Path $sandbox 'concurrent'
    [void][IO.Directory]::CreateDirectory($case)
    $env:STARCCM_TEST_CONFIG_HOME = $case
    $env:STARCCM_TEST_FAIL = 'concurrent'
    try { Register-StarMcp -Codex $fake -Node 'node.exe' -Server 'server.mjs' -DocRoot 'docs' -Name 'test' -ConfigHome $case } catch {}
    if ([IO.File]::ReadAllText((Join-Path $case 'config.toml')) -ne '# later-user-change') { throw 'Rollback overwrote a later change.' }
} finally { $env:STARCCM_TEST_CONFIG_HOME = $oldHome; $env:STARCCM_TEST_FAIL = $oldMode }
Write-Host 'PASS: add/get/JSON/mismatch failures restore existing or absent config; later changes are preserved.'
