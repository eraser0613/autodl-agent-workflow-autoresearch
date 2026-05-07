param(
    [int]$LocalPort = 0,
    [int]$RemotePort = 0,
    [switch]$StartRemote
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "common.ps1")

$cfg = Import-AutoDL3DGSConfig
if ($LocalPort -eq 0) {
    $LocalPort = $cfg.AutoDL3DGSTensorBoardPort
}
if ($RemotePort -eq 0) {
    $RemotePort = $cfg.AutoDL3DGSTensorBoardPort
}

if ($StartRemote) {
    $tbCommand = "tensorboard --logdir $(ConvertTo-BashSingleQuoted $cfg.AutoDL3DGSTensorBoardLogDir) --host 127.0.0.1 --port $RemotePort"
    Start-AutoDLRemoteLauncher `
        -Config $cfg `
        -SessionName "3dgs-tensorboard-$RemotePort" `
        -Command $tbCommand `
        -LogPrefix "3dgs-tensorboard-$RemotePort" `
        -RemoteProjectDir $cfg.AutoDL3DGSRemoteProjectDir `
        -RemoteArchiveDir $cfg.AutoDL3DGSRemoteArchiveDir `
        -RemoteLogDir $cfg.AutoDL3DGSRemoteLogDir `
        -RemoteCondaInit $cfg.AutoDL3DGSRemoteCondaInit `
        -RemoteCondaEnv $cfg.AutoDL3DGSRemoteCondaEnv `
        -RemoteMultiplexer $cfg.AutoDL3DGSRemoteMultiplexer | Out-Null
}

Write-Host "Opening 3DGS TensorBoard SSH tunnel. Keep this window open."
Write-Host "Local URL: http://127.0.0.1:$LocalPort"
Write-Host "Remote logdir: $($cfg.AutoDL3DGSTensorBoardLogDir)"
Write-Host ""

Assert-CommandExists -Name "ssh"
& ssh -N -L "${LocalPort}:127.0.0.1:${RemotePort}" $cfg.AutoDLHostAlias
