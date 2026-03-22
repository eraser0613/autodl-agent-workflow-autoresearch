param(
    [string]$SessionName,
    [int]$Lines = 80
)

. (Join-Path $PSScriptRoot "common.ps1")

$cfg = Import-AutoDLConfig
if ([string]::IsNullOrWhiteSpace($SessionName)) {
    $SessionName = $cfg.AutoDLDefaultTmuxSession
}

$remoteStatus = @"
set +e
echo '=== nvidia-smi ==='
nvidia-smi
echo
MUX_MODE=$(ConvertTo-BashSingleQuoted ([string]$cfg.AutoDLRemoteMultiplexer))
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
  tmux ls
elif [ "`$MUX_MODE" = "screen" ]; then
  screen -list
else
  echo 'no tmux/screen found'
fi
echo
echo '=== session pane ==='
if [ "`$MUX_MODE" = "tmux" ]; then
  tmux capture-pane -pt $(ConvertTo-BashSingleQuoted $SessionName) | tail -n $Lines
elif [ "`$MUX_MODE" = "screen" ]; then
  screen -S $(ConvertTo-BashSingleQuoted $SessionName) -X hardcopy -h /tmp/codex-screen-$SessionName.log 2>/dev/null
  tail -n $Lines /tmp/codex-screen-$SessionName.log 2>/dev/null || echo 'screen session not found'
else
  echo 'no session output available'
fi
echo
echo '=== latest log tail ==='
latest_log=`$(ls -1t $(ConvertTo-BashSingleQuoted $cfg.AutoDLRemoteLogDir)/*.log 2>/dev/null | head -n 1)
if [ -n "`$latest_log" ]; then
  tail -n $Lines "`$latest_log"
else
  echo 'no log files found'
fi
"@

Invoke-AutoDLSSH -Config $cfg -RemoteCommand $remoteStatus
