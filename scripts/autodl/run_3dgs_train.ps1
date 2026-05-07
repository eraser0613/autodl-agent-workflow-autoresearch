param(
    [string]$SessionName,
    [string]$Command,
    [switch]$NoSync
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "common.ps1")

$cfg = Import-AutoDL3DGSConfig
if ([string]::IsNullOrWhiteSpace($SessionName)) {
    $SessionName = $cfg.AutoDL3DGSTrainSessionName
}
if ([string]::IsNullOrWhiteSpace($Command)) {
    $Command = $cfg.AutoDL3DGSTrainCommand
}

if (-not $NoSync) {
    & (Join-Path $PSScriptRoot "sync_3dgs_to_autodl.ps1")
    if ($LASTEXITCODE -ne 0) {
        throw "3DGS sync failed. Training launch aborted."
    }
}

Start-AutoDLRemoteLauncher `
    -Config $cfg `
    -SessionName $SessionName `
    -Command $Command `
    -LogPrefix $SessionName `
    -RemoteProjectDir $cfg.AutoDL3DGSRemoteProjectDir `
    -RemoteArchiveDir $cfg.AutoDL3DGSRemoteArchiveDir `
    -RemoteLogDir $cfg.AutoDL3DGSRemoteLogDir `
    -RemoteCondaInit $cfg.AutoDL3DGSRemoteCondaInit `
    -RemoteCondaEnv $cfg.AutoDL3DGSRemoteCondaEnv `
    -RemoteMultiplexer $cfg.AutoDL3DGSRemoteMultiplexer | Out-Null
