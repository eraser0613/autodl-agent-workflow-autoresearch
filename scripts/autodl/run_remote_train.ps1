param(
    [string]$SessionName,
    [string]$Command,
    [switch]$NoSync
)

. (Join-Path $PSScriptRoot "common.ps1")

$cfg = Import-AutoDLConfig

if ([string]::IsNullOrWhiteSpace($SessionName)) {
    $SessionName = $cfg.AutoDLDefaultTmuxSession
}
if ([string]::IsNullOrWhiteSpace($Command)) {
    $Command = $cfg.AutoDLTrainEntry
}

if (-not $NoSync) {
    & (Join-Path $PSScriptRoot "sync_to_autodl.ps1")
    if ($LASTEXITCODE -ne 0) {
        throw "Sync failed. Training launch aborted."
    }
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$remoteLauncherPath = "$($cfg.AutoDLRemoteArchiveDir)/launch-$SessionName-$timestamp.sh"
$remoteLogFile = "$($cfg.AutoDLRemoteLogDir)/$SessionName-$timestamp.log"
$localLauncherPath = Join-Path $env:TEMP "launch-$SessionName-$timestamp.sh"

$launcherContent = @"
#!/usr/bin/env bash
set -euo pipefail
mkdir -p $(ConvertTo-BashSingleQuoted $cfg.AutoDLRemoteLogDir)
cd $(ConvertTo-BashSingleQuoted $cfg.AutoDLRemoteProjectDir)
source $(ConvertTo-BashSingleQuoted $cfg.AutoDLRemoteCondaInit)
conda activate $(ConvertTo-BashSingleQuoted $cfg.AutoDLRemoteCondaEnv)
$Command 2>&1 | tee $(ConvertTo-BashSingleQuoted $remoteLogFile)
"@
[System.IO.File]::WriteAllText(
    $localLauncherPath,
    $launcherContent,
    [System.Text.UTF8Encoding]::new($false)
)

Write-Host "Uploading remote launcher..."
Invoke-AutoDLSCP -Config $cfg -LocalPath $localLauncherPath -RemotePath $remoteLauncherPath

$muxMode = [string]$cfg.AutoDLRemoteMultiplexer
$remoteStart = @"
set -e
chmod +x $(ConvertTo-BashSingleQuoted $remoteLauncherPath)
mkdir -p $(ConvertTo-BashSingleQuoted $cfg.AutoDLRemoteLogDir)
MUX_MODE=$(ConvertTo-BashSingleQuoted $muxMode)
if [ "`$MUX_MODE" = "auto" ]; then
  if command -v tmux >/dev/null 2>&1; then
    MUX_MODE=tmux
  elif command -v screen >/dev/null 2>&1; then
    MUX_MODE=screen
  else
    echo "Neither tmux nor screen is installed" >&2
    exit 1
  fi
fi
if [ "`$MUX_MODE" = "tmux" ]; then
  if tmux has-session -t $(ConvertTo-BashSingleQuoted $SessionName) 2>/dev/null; then
    tmux kill-session -t $(ConvertTo-BashSingleQuoted $SessionName)
  fi
  tmux new-session -d -s $(ConvertTo-BashSingleQuoted $SessionName) "bash $(ConvertTo-BashSingleQuoted $remoteLauncherPath)"
else
  screen -S $(ConvertTo-BashSingleQuoted $SessionName) -X quit >/dev/null 2>&1 || true
  screen -dmS $(ConvertTo-BashSingleQuoted $SessionName) bash $(ConvertTo-BashSingleQuoted $remoteLauncherPath)
fi
printf 'mux=%s\n' "`$MUX_MODE"
printf 'session=%s\n' $(ConvertTo-BashSingleQuoted $SessionName)
printf 'log=%s\n' $(ConvertTo-BashSingleQuoted $remoteLogFile)
"@
Invoke-AutoDLSSH -Config $cfg -RemoteCommand $remoteStart

Remove-Item $localLauncherPath -Force

Write-Host ""
Write-Host "Remote training started."
Write-Host "session: $SessionName"
Write-Host "log file: $remoteLogFile"
