Import-Module (Join-Path $PSScriptRoot 'Executables.psm1')

function Get-ConfigDigest([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return 'missing' }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Register-StarMcp {
    [CmdletBinding()]
    param([string]$Codex, [string]$Node, [string]$Server, [string]$DocRoot, [string]$Name, [string]$ConfigHome)
    $ConfigHome = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ConfigHome)
    $config = Join-Path $ConfigHome 'config.toml'
    $beforeHash = Get-ConfigDigest $config
    $backup = $null
    if ($beforeHash -ne 'missing') {
        $backup = $config + '.before-starccm-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '-' + [guid]::NewGuid().ToString('N') + '.bak'
        Copy-Item -LiteralPath $config -Destination $backup -ErrorAction Stop
        if ((Get-ConfigDigest $backup) -ne $beforeHash) { throw 'Configuration changed while creating the backup. Retry deployment.' }
        Write-Host "Configuration backup: $backup"
    }
    $writeAttempted = $false
    $writtenHash = $null
    try {
        if ((Get-ConfigDigest $config) -ne $beforeHash) { throw 'Configuration changed before registration. Retry deployment.' }
        $writeAttempted = $true
        try {
            Invoke-Executable -Path $Codex -Arguments @('mcp', 'add', $Name, '--', $Node, $Server, $DocRoot)
            if ($LASTEXITCODE -ne 0) { throw 'Codex registration failed.' }
        } finally { $writtenHash = Get-ConfigDigest $config }
        $registeredJson = Invoke-Executable -Path $Codex -Arguments @('mcp', 'get', $Name, '--json')
        if ($LASTEXITCODE -ne 0) { throw 'Codex configuration verification failed.' }
        $registered = ($registeredJson -join "`n") | ConvertFrom-Json -ErrorAction Stop
        if (-not $registered.enabled -or $registered.transport.type -ne 'stdio' -or
            $registered.transport.command -ne $Node -or $registered.transport.args.Count -ne 2 -or
            $registered.transport.args[0] -ne $Server -or $registered.transport.args[1] -ne $DocRoot) {
            throw 'Codex effective configuration does not match this deployment. Check project/profile overrides.'
        }
    } catch {
        $failure = $_
        if ($writeAttempted -and $null -ne $writtenHash) {
            if ((Get-ConfigDigest $config) -eq $writtenHash) {
                if ($backup) { Copy-Item -LiteralPath $backup -Destination $config -Force -ErrorAction Stop }
                elseif (Test-Path -LiteralPath $config -PathType Leaf) { Remove-Item -LiteralPath $config -ErrorAction Stop }
                Write-Warning 'Registration did not pass verification; the previous config.toml state was restored.'
            } else {
                Write-Warning "Configuration changed again after registration; automatic rollback was skipped to preserve those changes. Backup: $backup"
            }
        }
        throw $failure
    }
}
Export-ModuleMember -Function Register-StarMcp
