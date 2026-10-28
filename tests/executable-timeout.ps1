#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $repo 'scripts/Executables.psm1') -Force
$sandbox = Join-Path ([IO.Path]::GetTempPath()) ('starccm-executable-test-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($sandbox)
$node = Find-Executable '' @('node.exe') @((Join-Path $env:USERPROFILE '.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node.exe'))
$echo = Join-Path $sandbox 'echo.mjs'
[IO.File]::WriteAllText($echo, 'console.error("diagnostic-only"); console.log(JSON.stringify(process.argv.slice(2))); process.exitCode=7;')
$echoPs = Join-Path $sandbox 'echo.ps1'
[IO.File]::WriteAllText($echoPs, '[Console]::Error.WriteLine("diagnostic-only"); ConvertTo-Json -InputObject @($args) -Compress; $global:LASTEXITCODE=7')
$unicode = [string][char]0x6587 + [string][char]0x6863
$arguments = @('plain', 'amp&docs', '%NAME%', '!NAME!', '^caret', '(parens)', $unicode, 'with space', "with'quote", 'with"quote', 'C:\tail\', '', "two`nlines")
foreach ($launcher in @('native','powershell')) {
    $output = if ($launcher -eq 'native') { Invoke-Executable $node (@($echo) + $arguments) } else { Invoke-Executable $echoPs $arguments }
    if ($LASTEXITCODE -ne 7) { throw "Exit code lost for $launcher" }
    $actual = ConvertFrom-Json -InputObject $output
    if ($actual.Count -ne $arguments.Count -or $output -match 'diagnostic-only') { throw "Argument count or stream separation failed for $launcher" }
    for ($i=0; $i -lt $arguments.Count; $i++) { if ($actual[$i] -cne $arguments[$i]) { throw "Argument $i changed for $launcher" } }
}
Write-Host 'PASS: native and PS1 arguments, Unicode, quotes, newlines, empty values, stderr separation and exit code.'

$hang = Join-Path $sandbox 'hang.mjs'
$hangSource = @'
import {spawn} from 'node:child_process';
import {writeFileSync} from 'node:fs';
const child = spawn(process.execPath, ['-e', 'setInterval(()=>{},1000)'], {stdio:'inherit'});
writeFileSync(process.argv[2], JSON.stringify([process.pid, child.pid]));
setInterval(()=>{},1000);
'@
[IO.File]::WriteAllText($hang, $hangSource)
$hangPs = Join-Path $sandbox 'hang.ps1'
[IO.File]::WriteAllText($hangPs, '& $env:STARCCM_TEST_NODE $env:STARCCM_TEST_HANG $env:STARCCM_TEST_PIDS')
$hangCmd = Join-Path $sandbox 'hang.cmd'
[IO.File]::WriteAllText($hangCmd, '@echo off' + "`r`n" + '"%STARCCM_TEST_NODE%" "%STARCCM_TEST_HANG%" "%STARCCM_TEST_PIDS%"' + "`r`n")
$saved = @{}
foreach ($name in @('STARCCM_TEST_NODE','STARCCM_TEST_HANG','STARCCM_TEST_PIDS','STARCCM_TEST_CONFIG')) { $saved[$name] = [Environment]::GetEnvironmentVariable($name,'Process') }
$env:STARCCM_TEST_NODE = $node
$env:STARCCM_TEST_HANG = $hang
$sentinel = New-Object Diagnostics.Process
$sentinel.StartInfo.FileName = $node
$sentinel.StartInfo.Arguments = '-e "setInterval(()=>{},1000)"'
$sentinel.StartInfo.UseShellExecute = $false
$sentinel.StartInfo.CreateNoWindow = $true
[void]$sentinel.Start()
try {
    foreach ($launcher in @('native','powershell','batch')) {
        $env:STARCCM_TEST_PIDS = Join-Path $sandbox ($launcher + '-pids.json')
        $clock = [Diagnostics.Stopwatch]::StartNew()
        $timedOut = $false
        try {
            if ($launcher -eq 'native') { Invoke-Executable $node @($hang,$env:STARCCM_TEST_PIDS) -TimeoutSeconds 2 | Out-Null }
            elseif ($launcher -eq 'powershell') { Invoke-Executable $hangPs @() -TimeoutSeconds 2 | Out-Null }
            else { Invoke-Executable $hangCmd @() -TimeoutSeconds 2 | Out-Null }
        } catch { if ($_.Exception.Message -notmatch 'timed out') { throw }; $timedOut=$true }
        $clock.Stop()
        if (-not $timedOut -or $LASTEXITCODE -ne 124 -or $clock.Elapsed.TotalSeconds -gt 7) { throw "Timeout was not bounded for $launcher" }
        if (-not [IO.File]::Exists($env:STARCCM_TEST_PIDS)) { throw "The $launcher fixture did not start before timeout." }
        foreach ($id in (ConvertFrom-Json ([IO.File]::ReadAllText($env:STARCCM_TEST_PIDS)))) {
            $remaining = Get-Process -Id $id -ErrorAction SilentlyContinue
            if ($remaining) {
                try { if (-not $remaining.HasExited) { throw "Timed-out $launcher left process $id alive." } }
                finally { $remaining.Dispose() }
            }
        }
        if ($sentinel.HasExited) { throw 'Timeout killed an unrelated process.' }
        Write-Host "PASS: $launcher timeout kills its child tree in $([Math]::Round($clock.Elapsed.TotalSeconds,2)) seconds."
    }
    $registration = Import-Module (Join-Path $repo 'scripts/Registration.psm1') -Force -PassThru
    # Keep the public registration API unchanged: route only this isolated test's
    # invocations to the real runner with a shorter timeout.
    & $registration {
        function script:Invoke-Executable {
            param([string]$Path, [string[]]$Arguments)
            Executables\Invoke-Executable -Path $Path -Arguments $Arguments -TimeoutSeconds 2
        }
    }
    $fakeCodex = Join-Path $sandbox 'hanging-codex.ps1'
    [IO.File]::WriteAllText($fakeCodex, '[IO.File]::WriteAllText($env:STARCCM_TEST_CONFIG,"changed-by-add"); Start-Sleep -Seconds 60')
    $configHome = Join-Path $sandbox 'isolated-codex'
    [void][IO.Directory]::CreateDirectory($configHome)
    $env:STARCCM_TEST_CONFIG = Join-Path $configHome 'config.toml'
    [IO.File]::WriteAllText($env:STARCCM_TEST_CONFIG, 'original-config')
    $failed = $false
    try { Register-StarMcp -Codex $fakeCodex -Node $node -Server 'server.mjs' -DocRoot 'docs' -Name 'test' -ConfigHome $configHome }
    catch { if ($_.Exception.Message -notmatch 'timed out') { throw }; $failed=$true }
    if (-not $failed -or [IO.File]::ReadAllText($env:STARCCM_TEST_CONFIG) -ne 'original-config') { throw 'A timed-out Codex command did not roll back registration.' }
    Write-Host 'PASS: registration still rolls back after a timed-out command.'
} finally {
    if (-not $sentinel.HasExited) { $sentinel.Kill(); [void]$sentinel.WaitForExit(2000) }; $sentinel.Dispose()
    foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name,$saved[$name],'Process') }
}
Write-Host "Executable test evidence: $sandbox"
