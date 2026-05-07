param(
    [string]$SessionName,
    [int]$Lines = 100
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "common.ps1")

$cfg = Import-AutoDL3DGSConfig
if ([string]::IsNullOrWhiteSpace($SessionName)) {
    $SessionName = $cfg.AutoDL3DGSTrainSessionName
}

$remoteStatus = @"
set +e
echo '=== nvidia-smi ==='
nvidia-smi || true
echo
echo '=== 3DGS paths ==='
echo 'project: '$(ConvertTo-BashSingleQuoted $cfg.AutoDL3DGSRemoteProjectDir)
echo 'scene: '$(ConvertTo-BashSingleQuoted $cfg.AutoDL3DGSRemoteSceneDir)
echo 'model: '$(ConvertTo-BashSingleQuoted $cfg.AutoDL3DGSRemoteModelDir)
echo 'logs: '$(ConvertTo-BashSingleQuoted $cfg.AutoDL3DGSRemoteLogDir)
for p in $(ConvertTo-BashSingleQuoted $cfg.AutoDL3DGSRemoteProjectDir) \
         $(ConvertTo-BashSingleQuoted $cfg.AutoDL3DGSRemoteSceneDir) \
         $(ConvertTo-BashSingleQuoted $cfg.AutoDL3DGSRemoteModelDir) \
         $(ConvertTo-BashSingleQuoted $cfg.AutoDL3DGSRemoteLogDir); do
  if [ -e "`$p" ]; then du -sh "`$p" 2>/dev/null || true; else echo "missing: `$p"; fi
done
echo
MUX_MODE=$(ConvertTo-BashSingleQuoted ([string]$cfg.AutoDL3DGSRemoteMultiplexer))
if [ "`$MUX_MODE" = "auto" ]; then
  if command -v tmux >/dev/null 2>&1; then
    MUX_MODE=tmux
  elif command -v screen >/dev/null 2>&1; then
    MUX_MODE=screen
  else
    MUX_MODE=none
  fi
fi
echo '=== multiplexer ==='
echo "mode=`$MUX_MODE"
if [ "`$MUX_MODE" = "tmux" ]; then
  tmux ls 2>/dev/null || true
elif [ "`$MUX_MODE" = "screen" ]; then
  screen -list 2>/dev/null || true
else
  echo 'no tmux/screen found'
fi
echo
echo '=== session output ==='
if [ "`$MUX_MODE" = "tmux" ]; then
  tmux capture-pane -pt $(ConvertTo-BashSingleQuoted $SessionName) 2>/dev/null | tail -n $Lines || echo 'tmux session not found'
elif [ "`$MUX_MODE" = "screen" ]; then
  screen -S $(ConvertTo-BashSingleQuoted $SessionName) -X hardcopy -h /tmp/autodl-3dgs-screen-$SessionName.log 2>/dev/null
  tail -n $Lines /tmp/autodl-3dgs-screen-$SessionName.log 2>/dev/null || echo 'screen session not found'
else
  echo 'no session output available'
fi
echo
echo '=== latest 3DGS log tail ==='
latest_log=`$(ls -1t $(ConvertTo-BashSingleQuoted $cfg.AutoDL3DGSRemoteLogDir)/*.log 2>/dev/null | head -n 1)
if [ -n "`$latest_log" ]; then
  echo "latest_log=`$latest_log"
  tail -n $Lines "`$latest_log"
else
  echo 'no log files found'
fi
"@

Invoke-AutoDLSSH -Config $cfg -RemoteCommand $remoteStatus
