<#
.SYNOPSIS
Repo-specific Scaffold-GS deploy/train workflow for AutoDL, driven through scripts/autodl/agent.ps1.

.DESCRIPTION
This script is a compact version of the commands validated during the Scaffold-GS Barn run:
- verify the AutoDL base environment
- install Python deps and compile CUDA extensions
- validate a COLMAP scene
- run 1-iteration smoke tests
- start a detachable training run
- summarize a finished training output

It intentionally does not pass --checkpoint_iterations because this Scaffold-GS checkout fails in
GaussianModel.capture() with AttributeError: missing _local. Use normal --save_iterations instead.

.EXAMPLE
powershell -ExecutionPolicy Bypass -File .\profiles\Scaffold-GS.deploy-train.ps1 -Action env-check

.EXAMPLE
powershell -ExecutionPolicy Bypass -File .\profiles\Scaffold-GS.deploy-train.ps1 -Action data-check -SourcePath data/custom/Barn

.EXAMPLE
powershell -ExecutionPolicy Bypass -File .\profiles\Scaffold-GS.deploy-train.ps1 -Action barn-smoke

.EXAMPLE
powershell -ExecutionPolicy Bypass -File .\profiles\Scaffold-GS.deploy-train.ps1 -Action train -Iterations 10000
#>
param(
    [ValidateSet("help", "init", "clone", "env-check", "setup", "data-check", "mini-smoke", "barn-smoke", "train", "status", "summarize")]
    [string]$Action = "help",

    [string]$ConfigPath = ".\scripts\autodl\autodl.agent.config.ps1",
    [string]$RunId = "20260504-184448-Scaffold-GS",
    [string]$RepoUrl = "https://github.com/city-super/Scaffold-GS",
    [string]$RepoName = "Scaffold-GS",
    [string]$RepoRef = "59c833b56bbbf510f3f64d40f81721995caced66",
    [string]$RemoteProjectPath = "/root/autodl-tmp/agent-workspace/repos/Scaffold-GS",
    [string]$CondaInitPath = "/root/miniconda3/etc/profile.d/conda.sh",
    [string]$CondaEnv = "base",

    [string]$SourcePath = "data/custom/Barn",
    [int]$Resolution = 8,
    [int]$Iterations = 10000,
    [string]$SessionName,
    [string]$OutputPath,
    [int]$Lines = 160
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$AgentPath = Join-Path $ProjectRoot "scripts\autodl\agent.ps1"
if (-not [System.IO.Path]::IsPathRooted($ConfigPath)) {
    $ConfigPath = Join-Path $ProjectRoot $ConfigPath
}

function Show-Usage {
    @"
Scaffold-GS deploy/train workflow

Actions:
  init        Initialize a harness run record.
  clone       Clone Scaffold-GS to the AutoDL workspace.
  env-check   Verify CUDA, Python, PyTorch and required imports.
  setup       Install Python deps and compile diff-gaussian-rasterization/simple-knn.
  data-check  Validate SourcePath as a COLMAP scene and recommend resolution.
  mini-smoke  Run known-good 1-iteration mini_colmap_scene smoke (--resolution 1).
  barn-smoke  Run 1-iteration smoke for SourcePath, default data/custom/Barn.
  train       Start detached training; default 10000 iterations, no checkpoint flag.
  status      Show harness/session status. Use -SessionName to focus one session.
  summarize   Summarize a completed output directory. Requires -OutputPath.

Typical sequence:
  .\profiles\Scaffold-GS.deploy-train.ps1 -Action clone
  .\profiles\Scaffold-GS.deploy-train.ps1 -Action setup
  .\profiles\Scaffold-GS.deploy-train.ps1 -Action data-check -SourcePath data/custom/Barn
  .\profiles\Scaffold-GS.deploy-train.ps1 -Action barn-smoke
  .\profiles\Scaffold-GS.deploy-train.ps1 -Action train -Iterations 10000
  .\profiles\Scaffold-GS.deploy-train.ps1 -Action status -SessionName <session>
  .\profiles\Scaffold-GS.deploy-train.ps1 -Action summarize -OutputPath outputs/custom/Barn/train_10000_nockpt_<stamp>

Notes:
  - Long training is launched with agent.ps1 -Action start, so it is detachable.
  - Do not add --checkpoint_iterations unless Scaffold-GS GaussianModel.capture() is fixed.
  - For the 64x48 mini scene use --resolution 1; --resolution 8 is safe for Barn.
"@ | Write-Host
}

function ConvertTo-CommandBase64 {
    param([Parameter(Mandatory = $true)][string]$Script)
    return [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Script))
}

function Quote-Bash {
    param([Parameter(Mandatory = $true)][string]$Value)
    return "'" + $Value.Replace("'", "'\''") + "'"
}

function New-RemoteScript {
    param([Parameter(Mandatory = $true)][string]$Body)
    $remoteProject = Quote-Bash $RemoteProjectPath
    $condaInit = Quote-Bash $CondaInitPath
    $condaEnvName = Quote-Bash $CondaEnv
@"
set -euo pipefail
project=$remoteProject
conda_init=$condaInit
source "`$conda_init"
conda activate $condaEnvName
cd "`$project"

$Body
"@
}

function Invoke-AgentRun {
    param(
        [Parameter(Mandatory = $true)][string]$RemoteScript,
        [int]$TailLines = $Lines
    )
    $b64 = ConvertTo-CommandBase64 $RemoteScript
    & powershell.exe -ExecutionPolicy Bypass -File $AgentPath `
        -ConfigPath $ConfigPath `
        -Action run `
        -RunId $RunId `
        -RepoName $RepoName `
        -CommandBase64 $b64 `
        -Lines $TailLines
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

function Start-AgentJob {
    param(
        [Parameter(Mandatory = $true)][string]$RemoteScript,
        [Parameter(Mandatory = $true)][string]$Name
    )
    $b64 = ConvertTo-CommandBase64 $RemoteScript
    & powershell.exe -ExecutionPolicy Bypass -File $AgentPath `
        -ConfigPath $ConfigPath `
        -Action start `
        -RunId $RunId `
        -RepoName $RepoName `
        -SessionName $Name `
        -CommandBase64 $b64
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

switch ($Action) {
    "help" {
        Show-Usage
    }

    "init" {
        & powershell.exe -ExecutionPolicy Bypass -File $AgentPath `
            -ConfigPath $ConfigPath `
            -Action init `
            -RunId $RunId `
            -RepoName $RepoName `
            -RepoUrl $RepoUrl `
            -Ref $RepoRef
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    }

    "clone" {
        & powershell.exe -ExecutionPolicy Bypass -File $AgentPath `
            -ConfigPath $ConfigPath `
            -Action clone `
            -RunId $RunId `
            -RepoName $RepoName `
            -RepoUrl $RepoUrl `
            -Ref $RepoRef
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    }

    "env-check" {
        $body = @'
echo '=== identity ==='
whoami
hostname
pwd

echo '=== cuda ==='
nvidia-smi || true
readlink -f /usr/local/cuda || true
/usr/local/cuda/bin/nvcc --version || true

echo '=== python/imports ==='
python - <<'PY'
import importlib.util
import sys
print('python', sys.version.replace('\n', ' '))
mods = [
    'torch', 'torchvision', 'torch_scatter', 'wandb', 'lpips', 'plyfile',
    'einops', 'colorama', 'jaxtyping', 'cv2',
    'diff_gaussian_rasterization', 'simple_knn._C'
]
for name in mods:
    try:
        mod = __import__(name)
        print('IMPORT_OK', name, getattr(mod, '__version__', ''))
    except Exception as exc:
        print('IMPORT_FAIL', name, type(exc).__name__, exc)
import torch
print('torch', torch.__version__, 'cuda', torch.version.cuda, 'available', torch.cuda.is_available())
if torch.cuda.is_available():
    print('gpu', torch.cuda.get_device_name(0))
PY

echo '=== train.py help ==='
python train.py --help >/tmp/scaffold_train_help.txt 2>&1
code=$?
echo train_help_exit=$code
python - <<'PY'
from pathlib import Path
p=Path('/tmp/scaffold_train_help.txt')
if p.exists():
    print('\n'.join(p.read_text(errors='replace').splitlines()[:50]))
PY
exit $code
'@
        Invoke-AgentRun -RemoteScript (New-RemoteScript $body)
    }

    "setup" {
        $body = @'
if [ -f /etc/network_turbo ]; then source /etc/network_turbo; fi

echo '=== repo ==='
git rev-parse HEAD || true
git submodule update --init --recursive

echo '=== python/torch ==='
python -V
python - <<'PY'
import torch
print('torch', torch.__version__, 'cuda', torch.version.cuda, 'available', torch.cuda.is_available())
PY

echo '=== install python deps ==='
python -m pip install --no-cache-dir wandb lpips plyfile laspy einops colorama jaxtyping opencv-python-headless

echo '=== install torch-scatter ==='
python -m pip install --no-cache-dir torch-scatter -f https://data.pyg.org/whl/torch-2.5.1+cu124.html

echo '=== compile cuda extensions ==='
export CUDA_HOME=/usr/local/cuda
export PATH=/usr/local/cuda/bin:$PATH
export TORCH_CUDA_ARCH_LIST="8.9"
python -m pip install --no-cache-dir --no-build-isolation ./submodules/diff-gaussian-rasterization
python -m pip install --no-cache-dir --no-build-isolation ./submodules/simple-knn

echo '=== verify imports ==='
python - <<'PY'
import importlib.util
import sys
mods = ['torch','torch_scatter','wandb','lpips','plyfile','laspy','cv2','diff_gaussian_rasterization','simple_knn._C']
print('python', sys.version.replace('\n',' '))
for name in mods:
    spec = importlib.util.find_spec(name)
    print(name, 'ok' if spec else 'missing')
from torch_scatter import scatter_max
from diff_gaussian_rasterization import GaussianRasterizationSettings, GaussianRasterizer
from simple_knn._C import distCUDA2
print('extension_imports_ok')
PY
'@
        Invoke-AgentRun -RemoteScript (New-RemoteScript $body)
    }

    "data-check" {
        $source = Quote-Bash $SourcePath
        $body = @"
source_path=$source
python - "`$source_path" <<'PY'
from pathlib import Path
from PIL import Image
import os
import sys

root = Path(sys.argv[1])
sparse0 = root / 'sparse' / '0'
print('SOURCE', root.resolve())
print('source_exists', root.exists())
print('images_dir_exists', (root / 'images').is_dir())
print('sparse0_exists', sparse0.is_dir())
print('image_files', len([p for p in (root / 'images').iterdir() if p.is_file()]) if (root / 'images').is_dir() else 'missing')
for name in ['cameras.txt','images.txt','points3D.txt','cameras.bin','images.bin','points3D.bin','database.db']:
    p = (sparse0 / name) if name != 'database.db' else (root / name)
    print('COLMAP_FILE', name, 'exists' if p.exists() else 'missing', p.stat().st_size if p.exists() else '')

registered = []
images_txt = sparse0 / 'images.txt'
if images_txt.exists():
    lines = [line.rstrip('\n') for line in images_txt.read_text(errors='replace').splitlines() if line.strip() and not line.startswith('#')]
    for idx in range(0, len(lines), 2):
        tokens = lines[idx].split()
        if len(tokens) >= 10:
            registered.append(tokens[9])
print('registered_images_txt_count', len(registered))
missing = [name for name in registered if not (root / 'images' / name).exists()]
print('registered_missing_in_images', len(missing))
if missing:
    print('missing_sample', missing[:10])

sizes = []
for name in registered:
    p = root / 'images' / name
    if p.exists():
        with Image.open(p) as im:
            sizes.append((name, im.size[0], im.size[1]))
print('registered_size_count', len(sizes))
if sizes:
    min_w = min(w for _, w, _ in sizes)
    min_h = min(h for _, _, h in sizes)
    print('size_min', min_w, min_h)
    print('size_max', max(w for _, w, _ in sizes), max(h for _, _, h in sizes))
    print('size_samples', sizes[:5])
    recommended = 1
    for div in [8, 4, 2, 1]:
        scaled_min = min(min_w // div, min_h // div)
        safe = scaled_min >= 32
        print('resolution_divisor_candidate', div, 'scaled_min_side_floor', scaled_min, 'lpips_safe', safe)
        if safe and recommended == 1:
            recommended = div
    print('RECOMMENDED_RESOLUTION', recommended)
PY
"@
        Invoke-AgentRun -RemoteScript (New-RemoteScript $body)
    }

    "mini-smoke" {
        $body = @'
export CUDA_VISIBLE_DEVICES=0
export WANDB_MODE=disabled
export WANDB_DISABLED=true
export PYTHONUNBUFFERED=1
stamp=$(date +%Y%m%d_%H%M%S)
out="outputs/mini_colmap_scene/smoke_1iter_fullres_${stamp}"
log="/tmp/scaffold_mini_smoke_fullres_${stamp}.log"
echo "SMOKE_OUT=$out"
echo "SMOKE_LOG=$log"
python train.py --eval \
  -s mini_colmap_scene \
  --voxel_size 0.001 \
  --update_init_factor 16 \
  --appearance_dim 0 \
  --ratio 20 \
  --resolution 1 \
  --iterations 1 \
  --test_iterations 1 \
  --save_iterations 1 \
  -m "$out" 2>&1 | tee "$log"
code=${PIPESTATUS[0]}
echo "TRAIN_EXIT=$code"
exit $code
'@
        Invoke-AgentRun -RemoteScript (New-RemoteScript $body) -TailLines 220
    }

    "barn-smoke" {
        $source = Quote-Bash $SourcePath
        $body = @"
export CUDA_VISIBLE_DEVICES=0
export WANDB_MODE=disabled
export WANDB_DISABLED=true
export PYTHONUNBUFFERED=1
export PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True
source_path=$source
stamp=`$(date +%Y%m%d_%H%M%S)
rel="`${source_path#data/}"
out="outputs/`$rel/smoke_1iter_`$stamp"
log="/tmp/scaffold_`$(basename "`$source_path")_smoke_`$stamp.log"
echo "SMOKE_OUT=`$out"
echo "SMOKE_LOG=`$log"
echo "SOURCE=`$source_path"
echo "RESOLUTION=$Resolution"
python train.py --eval \
  -s "`$source_path" \
  --voxel_size 0.001 \
  --update_init_factor 16 \
  --appearance_dim 0 \
  --ratio 20 \
  --resolution $Resolution \
  --iterations 1 \
  --test_iterations 1 \
  --save_iterations 1 \
  -m "`$out" 2>&1 | tee "`$log"
code=`${PIPESTATUS[0]}
echo "TRAIN_EXIT=`$code"
exit "`$code"
"@
        Invoke-AgentRun -RemoteScript (New-RemoteScript $body) -TailLines 240
    }

    "train" {
        if ([string]::IsNullOrWhiteSpace($SessionName)) {
            $safeSource = ($SourcePath -replace '[^A-Za-z0-9]+', '-').Trim('-').ToLowerInvariant()
            $SessionName = "scaffold-gs-$safeSource-$Iterations-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        }
        $source = Quote-Bash $SourcePath
        $body = @"
export CUDA_VISIBLE_DEVICES=0
export WANDB_MODE=disabled
export WANDB_DISABLED=true
export PYTHONUNBUFFERED=1
export PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True

source_path=$source
iterations=$Iterations
resolution=$Resolution
stamp=`$(date +%Y%m%d_%H%M%S)
rel="`${source_path#data/}"
out="outputs/`$rel/train_`${iterations}_nockpt_`$stamp"
train_log="`$out/train_`${iterations}.log"
mkdir -p "`$out"

schedule=""
append_iter() {
  case " `$schedule " in
    *" `$1 "*) ;;
    *) schedule="`$schedule `$1" ;;
  esac
}
for iter in 1000 5000 "`$iterations"; do
  if [ "`$iter" -le "`$iterations" ]; then append_iter "`$iter"; fi
done

cat > "`$out/launch_manifest.txt" <<EOF
launched_at=`$(date -Is)
harness_run_id=$RunId
source_path=`$source_path
iterations=`$iterations
resolution=`$resolution
checkpoint_iterations=disabled_due_to_GaussianModel_missing_local
save_iterations=`$schedule
test_iterations=`$schedule
conda_env=$CondaEnv
python=`$(python -V 2>&1)
torch=`$(python - <<'PY'
import torch
print(torch.__version__)
PY
)
cuda_visible_devices=`${CUDA_VISIBLE_DEVICES}
EOF

echo "TRAIN_OUT=`$out"
echo "TRAIN_LOG=`$train_log"
echo "SOURCE=`$source_path"
echo "ITERATIONS=`$iterations"
echo "RESOLUTION=`$resolution"
echo "SAVE_AND_TEST_ITERATIONS=`$schedule"
echo "CHECKPOINT_ITERATIONS=disabled"

python train.py --eval \
  -s "`$source_path" \
  --voxel_size 0.001 \
  --update_init_factor 16 \
  --appearance_dim 0 \
  --ratio 20 \
  --resolution "`$resolution" \
  --iterations "`$iterations" \
  --test_iterations `$schedule \
  --save_iterations `$schedule \
  -m "`$out" 2>&1 | tee "`$train_log"
code=`${PIPESTATUS[0]}
echo "TRAIN_EXIT=`$code" | tee -a "`$train_log"
exit "`$code"
"@
        Start-AgentJob -RemoteScript (New-RemoteScript $body) -Name $SessionName
    }

    "status" {
        $argsList = @(
            "-ExecutionPolicy", "Bypass", "-File", $AgentPath,
            "-ConfigPath", $ConfigPath,
            "-Action", "status",
            "-RunId", $RunId,
            "-Lines", [string]$Lines
        )
        if (-not [string]::IsNullOrWhiteSpace($SessionName)) {
            $argsList += @("-SessionName", $SessionName)
        }
        & powershell.exe @argsList
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    }

    "summarize" {
        if ([string]::IsNullOrWhiteSpace($OutputPath)) {
            throw "-OutputPath is required for -Action summarize, e.g. outputs/custom/Barn/train_10000_nockpt_20260507_182100"
        }
        $outPath = Quote-Bash $OutputPath
        $body = @"
out_path=$outPath
python - "`$out_path" <<'PY'
from pathlib import Path
import os
import re
import sys

out = Path(sys.argv[1])
log_candidates = sorted(out.glob('train_*.log')) + [out / 'train_10000.log']
log = next((p for p in log_candidates if p.exists()), None)
print('OUT', out.resolve(), 'exists', out.exists())
print('LOG', log.resolve() if log else 'missing', 'size', log.stat().st_size if log else '')
if log:
    text = log.read_text(errors='replace').replace('\r', '\n')
    for key in ['Training complete.', 'Rendering complete.', 'Evaluating complete.', 'TRAIN_EXIT=0']:
        print('LOG_HAS', key, key in text)
    m = re.findall(r'Training progress:\s*(\d+)%.*?\|\s*(\d+)/(\d+).*?Loss=([0-9.]+)', text)
    print('LAST_PROGRESS', m[-1] if m else 'missing')
    for metric in ['SSIM', 'PSNR', 'LPIPS']:
        vals = re.findall(rf'{metric}\s*:\s*\x1b\[[^m]*m\s*([0-9.]+)', text)
        print('METRIC', metric, vals[-1] if vals else 'missing')

print('ARTIFACTS')
for p in sorted((out / 'point_cloud').glob('iteration_*/*')) if (out / 'point_cloud').exists() else []:
    if p.is_file():
        print(p.relative_to(out), p.stat().st_size)
for rel in ['test/ours_10000/renders', 'test/ours_10000/gt', 'test/ours_10000/errors']:
    p = out / rel
    files = sorted([x for x in p.iterdir() if x.is_file()]) if p.exists() else []
    print(rel, len(files))
PY
"@
        Invoke-AgentRun -RemoteScript (New-RemoteScript $body) -TailLines 260
    }
}
