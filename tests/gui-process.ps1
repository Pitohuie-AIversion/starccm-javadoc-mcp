#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
Add-Type -Path (Join-Path $repo 'gui/ProcessRunner.cs')
$unicode = [string][char]0x6587 + [string][char]0x6863
$fixture = Join-Path $env:TEMP ('starccm-process-' + [guid]::NewGuid().ToString('N') + " $unicode & %NAME% ! ^")
[void][IO.Directory]::CreateDirectory($fixture)
$ps = Join-Path $env:WINDIR 'System32/WindowsPowerShell/v1.0/powershell.exe'
$helperSource = Join-Path $fixture 'Child.cs'
$helper = Join-Path $fixture 'Child.exe'
@'
using System;
using System.Diagnostics;
using System.IO;
using System.Threading;
class Child {
    static void Main(string[] args) {
        File.WriteAllText(args[1], Process.GetCurrentProcess().Id.ToString());
        if (args[0] == "spawn") {
            var info = new ProcessStartInfo(Process.GetCurrentProcess().MainModule.FileName, "idle \"" + args[1] + ".grandchild\"");
            info.UseShellExecute = false;
            info.CreateNoWindow = true;
            Process.Start(info);
        }
        Thread.Sleep(30000);
    }
}
'@ | Set-Content -LiteralPath $helperSource -Encoding UTF8
$compiler = Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
if (-not (Test-Path -LiteralPath $compiler)) { $compiler = Join-Path $env:WINDIR 'Microsoft.NET/Framework/v4.0.30319/csc.exe' }
& $compiler /nologo "/out:$helper" $helperSource
if ($LASTEXITCODE -ne 0) { throw 'Cannot build child process fixture.' }
$worker = Join-Path $fixture 'worker.ps1'
@'
param([string]$RequestFile, [string]$ResultFile)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
$request = Get-Content -LiteralPath $RequestFile -Raw -Encoding UTF8 | ConvertFrom-Json
$unicode = [string][char]0x6587 + [string][char]0x6863
if ($request.mode -eq 'spawn') {
    & (Join-Path $PSScriptRoot 'Child.exe') spawn ($ResultFile + '.child')
    exit 0
}
if ($request.mode -eq 'exit-with-child') {
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = Join-Path $PSScriptRoot 'Child.exe'
    $info.Arguments = 'idle "' + $ResultFile + '.child"'
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    [void][Diagnostics.Process]::Start($info)
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    while (-not [IO.File]::Exists($ResultFile + '.child')) {
        if ([DateTime]::UtcNow -gt $deadline) { throw 'Child did not start.' }
        Start-Sleep -Milliseconds 10
    }
} else {
    for ($i = 0; $i -lt 2500; $i++) {
        [Console]::WriteLine('stdout-' + $unicode + '-' + $i)
        [Console]::Error.WriteLine('stderr-' + $unicode + '-' + $i)
    }
}
[IO.File]::WriteAllText($ResultFile, (ConvertTo-Json @{request=$RequestFile;result=$ResultFile}), (New-Object Text.UTF8Encoding($false)))
exit 7
'@ | Set-Content -LiteralPath $worker -Encoding UTF8

function New-Runner([string]$Mode) {
    $request = Join-Path $fixture ($Mode + '.request.json')
    $result = Join-Path $fixture ($Mode + '.result.json')
    [IO.File]::WriteAllText($request, (ConvertTo-Json @{mode=$Mode}), (New-Object Text.UTF8Encoding($false)))
    return New-Object StarGuiProcess($ps, $fixture, $worker, $request, $result)
}
function Wait-Until([scriptblock]$Condition, [string]$Message) {
    $deadline = [DateTime]::UtcNow.AddSeconds(15)
    while (-not (& $Condition)) {
        if ([DateTime]::UtcNow -gt $deadline) { throw $Message }
        Start-Sleep -Milliseconds 20
    }
}
function Assert-ProcessStopped([string]$PidFile) {
    $processId = [int][IO.File]::ReadAllText($PidFile)
    Wait-Until { -not (Get-Process -Id $processId -ErrorAction SilentlyContinue) } "Process survived cancellation: $processId"
}
$outside = $null
$runner = $null
try {
    $runner = New-Runner 'normal'
    Wait-Until { $runner.HasExited } 'Normal worker did not finish.'
    if ($runner.ExitCode -ne 7) { throw 'Worker exit code was lost.' }
    $output = $runner.Drain()
    if ($output -notmatch ("stdout-" + $unicode + "-2499") -or $output -notmatch ("stderr-" + $unicode + "-2499")) { throw 'Unicode output was truncated or not drained.' }
    $paths = Get-Content -LiteralPath (Join-Path $fixture 'normal.result.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($paths.request -cne (Join-Path $fixture 'normal.request.json') -or $paths.result -cne (Join-Path $fixture 'normal.result.json')) { throw 'Special-character paths changed.' }
    $runner.Dispose(); $runner = $null
    Write-Host 'PASS: UTF-8 stdout/stderr, large simultaneous output, special paths and nonzero exit code.'

    $outsideInfo = New-Object Diagnostics.ProcessStartInfo
    $outsideInfo.FileName = $helper
    $outsideInfo.Arguments = 'idle "' + (Join-Path $fixture 'outside.pid') + '"'
    $outsideInfo.UseShellExecute = $false
    $outsideInfo.CreateNoWindow = $true
    $outside = [Diagnostics.Process]::Start($outsideInfo)
    $runner = New-Runner 'spawn'
    $child = Join-Path $fixture 'spawn.result.json.child'
    Wait-Until { [IO.File]::Exists($child) -and [IO.File]::Exists($child + '.grandchild') } 'Worker descendants did not start.'
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $runner.Stop()
    $watch.Stop()
    if ($watch.Elapsed.TotalSeconds -gt 2.5) { throw 'Cancellation blocked the GUI for more than 2.5 seconds.' }
    Assert-ProcessStopped $child
    Assert-ProcessStopped ($child + '.grandchild')
    if ($outside.HasExited) { throw 'Cancellation affected an unrelated fixture process.' }
    $runner.Dispose(); $runner = $null
    Write-Host ("PASS: cancellation stopped child and grandchild in " + [math]::Round($watch.Elapsed.TotalMilliseconds) + ' ms; unrelated process survived.')

    $runner = New-Runner 'exit-with-child'
    Wait-Until { $runner.HasExited } 'Worker with detached child did not finish.'
    $watch.Restart()
    if ($runner.ExitCode -ne 7) { throw 'Exit code changed with an inherited pipe.' }
    $watch.Stop()
    if ($watch.Elapsed.TotalSeconds -gt 2.5) { throw 'Exit code retrieval waited indefinitely for an inherited pipe.' }
    Assert-ProcessStopped (Join-Path $fixture 'exit-with-child.result.json.child')
    $runner.Dispose(); $runner = $null
    Write-Host 'PASS: normal worker exit cleans up a leftover child without an unbounded stream wait.'

    $failed = $false
    try { $bad = New-Object StarGuiProcess((Join-Path $fixture 'missing.exe'), $fixture, $worker, 'request.json', 'result.json') }
    catch { $failed = $_.Exception.Message -match 'Cannot start background worker' }
    if (-not $failed) { throw 'Missing executable did not fail clearly.' }
    Write-Host 'PASS: launch failures return a clear error.'
} finally {
    if ($runner) { $runner.Stop(); $runner.Dispose() }
    if ($outside) { if (-not $outside.HasExited) { $outside.Kill(); $outside.WaitForExit(2000) | Out-Null }; $outside.Dispose() }
}
Write-Host "Process test evidence: $fixture"
