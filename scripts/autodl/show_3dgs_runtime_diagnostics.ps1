param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "common.ps1")

$cfg = Import-AutoDL3DGSConfig

$remoteDiagnostics = @"
set +e
echo '=== 3DGS paths ==='
echo 'workspace='$(ConvertTo-BashSingleQuoted $cfg.AutoDL3DGSRemoteWorkspaceDir)
echo 'project='$(ConvertTo-BashSingleQuoted $cfg.AutoDL3DGSRemoteProjectDir)
echo 'data_root='$(ConvertTo-BashSingleQuoted $cfg.AutoDL3DGSRemoteDataRoot)
echo 'scene='$(ConvertTo-BashSingleQuoted $cfg.AutoDL3DGSRemoteSceneDir)
echo 'output_root='$(ConvertTo-BashSingleQuoted $cfg.AutoDL3DGSRemoteOutputRoot)
echo 'model='$(ConvertTo-BashSingleQuoted $cfg.AutoDL3DGSRemoteModelDir)
echo 'log_dir='$(ConvertTo-BashSingleQuoted $cfg.AutoDL3DGSRemoteLogDir)
echo
echo '=== directory status ==='
for p in $(ConvertTo-BashSingleQuoted $cfg.AutoDL3DGSRemoteWorkspaceDir) \
         $(ConvertTo-BashSingleQuoted $cfg.AutoDL3DGSRemoteProjectDir) \
         $(ConvertTo-BashSingleQuoted $cfg.AutoDL3DGSRemoteSceneDir) \
         $(ConvertTo-BashSingleQuoted $cfg.AutoDL3DGSRemoteModelDir) \
         $(ConvertTo-BashSingleQuoted $cfg.AutoDL3DGSRemoteLogDir); do
  if [ -e "`$p" ]; then
    printf 'exists: %s\n' "`$p"
    du -sh "`$p" 2>/dev/null || true
  else
    printf 'missing: %s\n' "`$p"
  fi
done
echo
echo '=== runtime ==='
echo 'nvcc:' `$(command -v nvcc || true)
nvcc --version 2>/dev/null | tail -n 1 || true
echo 'python:' `$(command -v python || true)
echo 'conda:' `$(command -v conda || true)
if [ -f $(ConvertTo-BashSingleQuoted $cfg.AutoDL3DGSRemoteCondaInit) ]; then
  source $(ConvertTo-BashSingleQuoted $cfg.AutoDL3DGSRemoteCondaInit)
  conda activate $(ConvertTo-BashSingleQuoted $cfg.AutoDL3DGSRemoteCondaEnv) >/dev/null 2>&1
fi
python - <<'PY'
import importlib.util
import sys
print('python_version:', sys.version.replace('\n', ' '))
for name in ['torch', 'numpy', 'plyfile', 'tqdm', 'diff_gaussian_rasterization', 'simple_knn']:
    spec = importlib.util.find_spec(name)
    print(f'import_{name}:', 'ok' if spec else 'missing')
try:
    import torch
    print('torch_version:', torch.__version__)
    print('torch_cuda:', torch.version.cuda)
    print('cuda_available:', torch.cuda.is_available())
except Exception as exc:
    print('torch_error:', repr(exc))
PY
echo
echo '=== project markers ==='
cd $(ConvertTo-BashSingleQuoted $cfg.AutoDL3DGSRemoteProjectDir) 2>/dev/null || exit 0
for f in train.py render.py metrics.py requirements.txt environment.yml; do
  if [ -e "`$f" ]; then echo "found: `$f"; else echo "missing: `$f"; fi
done
for d in submodules/diff-gaussian-rasterization submodules/simple-knn; do
  if [ -d "`$d" ]; then echo "found: `$d"; else echo "missing: `$d"; fi
done
"@

Invoke-AutoDLSSH -Config $cfg -RemoteCommand $remoteDiagnostics
