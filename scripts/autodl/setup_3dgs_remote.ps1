param(
    [switch]$NoSync,
    [string]$SessionName
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "common.ps1")

$cfg = Import-AutoDL3DGSConfig
if ([string]::IsNullOrWhiteSpace($SessionName)) {
    $SessionName = $cfg.AutoDL3DGSSetupSessionName
}

if (-not $NoSync) {
    & (Join-Path $PSScriptRoot "sync_3dgs_to_autodl.ps1")
    if ($LASTEXITCODE -ne 0) {
        throw "3DGS sync failed. Setup launch aborted."
    }
}

$commands = @($cfg.AutoDL3DGSSetupCommands) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
if ($commands.Count -eq 0) {
    throw "AutoDL3DGSSetupCommands is empty. Edit $(Get-AutoDL3DGSConfigPath)."
}

$setupCommand = ($commands -join "`n")
Start-AutoDLRemoteLauncher `
    -Config $cfg `
    -SessionName $SessionName `
    -Command $setupCommand `
    -LogPrefix $SessionName `
    -RemoteProjectDir $cfg.AutoDL3DGSRemoteProjectDir `
    -RemoteArchiveDir $cfg.AutoDL3DGSRemoteArchiveDir `
    -RemoteLogDir $cfg.AutoDL3DGSRemoteLogDir `
    -RemoteCondaInit $cfg.AutoDL3DGSRemoteCondaInit `
    -RemoteCondaEnv $cfg.AutoDL3DGSRemoteCondaEnv `
    -RemoteMultiplexer $cfg.AutoDL3DGSRemoteMultiplexer | Out-Null
