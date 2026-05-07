param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "common.ps1")

$cfg = Import-AutoDL3DGSConfig

$remoteCheck = @"
set +e
echo '=== identity ==='
echo 'whoami:' `$(whoami)
echo 'hostname:' `$(hostname)
echo 'pwd:' `$(pwd)
echo
echo '=== gpu ==='
nvidia-smi || true
echo
echo '=== commands ==='
echo 'python:' `$(command -v python || true)
echo 'conda:' `$(command -v conda || true)
echo 'nvcc:' `$(command -v nvcc || true)
echo 'tmux:' `$(command -v tmux || true)
echo 'screen:' `$(command -v screen || true)
echo
echo '=== configured runtime ==='
echo 'conda init:' $(ConvertTo-BashSingleQuoted $cfg.AutoDL3DGSRemoteCondaInit)
echo 'conda env:' $(ConvertTo-BashSingleQuoted $cfg.AutoDL3DGSRemoteCondaEnv)
echo 'workspace:' $(ConvertTo-BashSingleQuoted $cfg.AutoDL3DGSRemoteWorkspaceDir)
echo 'project:' $(ConvertTo-BashSingleQuoted $cfg.AutoDL3DGSRemoteProjectDir)
echo 'scene:' $(ConvertTo-BashSingleQuoted $cfg.AutoDL3DGSRemoteSceneDir)
echo 'model:' $(ConvertTo-BashSingleQuoted $cfg.AutoDL3DGSRemoteModelDir)
echo
echo '=== python cuda ==='
if [ -f $(ConvertTo-BashSingleQuoted $cfg.AutoDL3DGSRemoteCondaInit) ]; then
  source $(ConvertTo-BashSingleQuoted $cfg.AutoDL3DGSRemoteCondaInit)
  conda activate $(ConvertTo-BashSingleQuoted $cfg.AutoDL3DGSRemoteCondaEnv) >/dev/null 2>&1
fi
python - <<'PY' 2>/dev/null || true
import sys
print('python_version:', sys.version.replace('\n', ' '))
try:
    import torch
    print('torch_version:', torch.__version__)
    print('torch_cuda:', torch.version.cuda)
    print('cuda_available:', torch.cuda.is_available())
    if torch.cuda.is_available():
        print('cuda_device:', torch.cuda.get_device_name(0))
except Exception as exc:
    print('torch_check_error:', repr(exc))
PY
"@

Invoke-AutoDLSSH -Config $cfg -RemoteCommand $remoteCheck
