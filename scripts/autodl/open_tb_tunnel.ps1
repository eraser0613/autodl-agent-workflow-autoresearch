param(
    [int]$LocalPort = 6006,
    [int]$RemotePort = 6006,
    [switch]$StartRemote
)

. (Join-Path $PSScriptRoot "common.ps1")

$cfg = Import-AutoDLConfig
if ($LocalPort -eq 6006) {
    $LocalPort = $cfg.AutoDLTensorBoardPort
}
if ($RemotePort -eq 6006) {
    $RemotePort = $cfg.AutoDLTensorBoardPort
}

if ($StartRemote) {
    $tbCommand = "source $(ConvertTo-BashSingleQuoted $cfg.AutoDLRemoteCondaInit) && conda activate $(ConvertTo-BashSingleQuoted $cfg.AutoDLRemoteCondaEnv) && tensorboard --logdir $(ConvertTo-BashSingleQuoted $cfg.AutoDLTensorBoardLogDir) --host 127.0.0.1 --port $RemotePort"
    $muxMode = [string]$cfg.AutoDLRemoteMultiplexer
    $remoteTB = @"
set -e
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
  if tmux has-session -t tensorboard-$RemotePort 2>/dev/null; then
    tmux kill-session -t tensorboard-$RemotePort
  fi
  tmux new-session -d -s tensorboard-$RemotePort "bash -lc $(ConvertTo-BashSingleQuoted $tbCommand)"
else
  screen -S tensorboard-$RemotePort -X quit >/dev/null 2>&1 || true
  screen -dmS tensorboard-$RemotePort bash -lc $(ConvertTo-BashSingleQuoted $tbCommand)
fi
"@
    Invoke-AutoDLSSH -Config $cfg -RemoteCommand $remoteTB
}

Write-Host "Opening SSH tunnel. Keep this window open."
Write-Host "Local URL: http://127.0.0.1:$LocalPort"
Write-Host ""

Assert-CommandExists -Name "ssh"
& ssh -N -L "${LocalPort}:127.0.0.1:${RemotePort}" $cfg.AutoDLHostAlias
