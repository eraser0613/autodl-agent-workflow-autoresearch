param()

. (Join-Path $PSScriptRoot "common.ps1")

$cfg = Import-AutoDLConfig

$remoteCheck = @"
set -e
echo 'whoami:' `$(whoami)
echo 'hostname:' `$(hostname)
echo 'pwd:' `$(pwd)
echo 'python:' `$(command -v python || true)
echo 'tmux:' `$(command -v tmux || true)
echo 'screen:' `$(command -v screen || true)
echo 'conda init:' $(ConvertTo-BashSingleQuoted $cfg.AutoDLRemoteCondaInit)
echo 'conda env:' $(ConvertTo-BashSingleQuoted $cfg.AutoDLRemoteCondaEnv)
"@

Invoke-AutoDLSSH -Config $cfg -RemoteCommand $remoteCheck
