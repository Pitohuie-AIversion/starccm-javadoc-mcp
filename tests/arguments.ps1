#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts/Executables.psm1') -Force
$runtime = Join-Path $env:USERPROFILE '.cache/codex-runtimes/codex-primary-runtime/dependencies/node'
$node = Find-Executable $null 'node.exe' @((Join-Path $runtime 'bin/node.exe'), (Join-Path $env:ProgramFiles 'nodejs/node.exe'))
$sandbox = Join-Path $env:TEMP ('starccm-args-' + [guid]::NewGuid().ToString('N'))
$unicode = [string][char]0x6587 + [string][char]0x6863
$cases = @('plain', 'amp&docs', 'percent%NAME%', 'bang!NAME!', 'caret^docs', '(docs)', $unicode, 'with spaces', 'A&B%NAME%!^()')
$values = @($cases) + @('C:\tail\', 'C:\with space\', '')
foreach ($case in $cases) {
    $dir = Join-Path $sandbox $case
    [void][IO.Directory]::CreateDirectory($dir)
    $script = Join-Path $dir 'echo.mjs'
    [IO.File]::WriteAllText($script, 'console.log(JSON.stringify(process.argv.slice(2)))')
    $shim = Join-Path $dir 'echo.cmd'
    [IO.File]::WriteAllText($shim, "@echo off`r`n`"$node`" `"%~dp0echo.mjs`" %*`r`nexit /b %errorlevel%`r`n")
    $result = Invoke-Executable -Path $shim -Arguments $values
    if ($LASTEXITCODE -ne 0) { throw "Launcher failed: $case" }
    $actual = ConvertFrom-Json -InputObject $result
    if ($actual.Count -ne $values.Count) { throw "Argument count differs: $case" }
    for ($i = 0; $i -lt $values.Count; $i++) {
        if ($actual[$i] -cne $values[$i]) { throw "Argument changed in $case at position $i" }
    }
}
Write-Host 'PASS: npm-style .cmd preserves special characters, Unicode, spaces, empty args and trailing backslashes.'
