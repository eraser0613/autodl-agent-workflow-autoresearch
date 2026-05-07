param(
    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "common.ps1")

$cfg = Import-AutoDL3DGSConfig
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $OutputPath = Join-Path (Join-Path (Get-AutoDLRepoRoot) "result") "3dgs-remote-discovery-$stamp.txt"
}
$outputDir = Split-Path -Parent $OutputPath
if (-not [string]::IsNullOrWhiteSpace($outputDir)) {
    New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
}

$remoteDiscover = @"
set +e
cd $(ConvertTo-BashSingleQuoted $cfg.AutoDL3DGSRemoteProjectDir) || exit 2
echo '=== remote 3DGS project discovery ==='
echo 'project='$(ConvertTo-BashSingleQuoted $cfg.AutoDL3DGSRemoteProjectDir)
echo
echo '=== top-level files ==='
ls -la | head -n 120
echo
echo '=== dependency files ==='
find . -maxdepth 3 -type f \( -iname 'environment.yml' -o -iname 'environment.yaml' -o -iname 'requirements.txt' -o -iname 'setup.py' -o -iname 'pyproject.toml' -o -iname 'setup.cfg' \) | sort
echo
echo '=== likely python entrypoints ==='
find . -maxdepth 4 -type f \( -iname 'train*.py' -o -iname '*_train.py' -o -iname 'render*.py' -o -iname '*_render.py' -o -iname 'metrics*.py' -o -iname 'eval*.py' -o -iname 'evaluate*.py' -o -iname 'main.py' \) | sort
echo
echo '=== submodules and 3DGS extensions ==='
for d in submodules/diff-gaussian-rasterization submodules/simple-knn diff-gaussian-rasterization simple-knn; do
  if [ -d "`$d" ]; then echo "found: `$d"; fi
done
if [ -f .gitmodules ]; then
  echo '--- .gitmodules ---'
  cat .gitmodules
fi
echo
echo '=== README command candidates ==='
for f in `$(find . -maxdepth 3 -type f \( -iname 'README*' -o -iname 'readme*' \) | sort | head -n 8); do
  echo "--- `$f ---"
  grep -E '(^|[[:space:]])(python|python3|CUDA_VISIBLE_DEVICES=|conda|pip|bash|sh)[[:space:]]' "`$f" | head -n 80
 done
echo
echo '=== suggested generic commands ==='
TRAIN=`$(find . -maxdepth 4 -type f \( -iname 'train.py' -o -iname 'train*.py' -o -iname '*_train.py' \) | sort | head -n 1 | sed 's#^./##')
RENDER=`$(find . -maxdepth 4 -type f \( -iname 'render.py' -o -iname 'render*.py' -o -iname '*_render.py' \) | sort | head -n 1 | sed 's#^./##')
EVAL=`$(find . -maxdepth 4 -type f \( -iname 'metrics.py' -o -iname 'metrics*.py' -o -iname 'eval*.py' -o -iname 'evaluate*.py' \) | sort | head -n 1 | sed 's#^./##')
[ -z "`$TRAIN" ] && TRAIN=train.py
[ -z "`$RENDER" ] && RENDER=render.py
[ -z "`$EVAL" ] && EVAL=metrics.py
echo "train: python `$TRAIN -s `$AutoDL3DGSRemoteSceneDir -m `$AutoDL3DGSRemoteModelDir --iterations 30000"
echo "render: python `$RENDER -m `$AutoDL3DGSRemoteModelDir"
echo "eval: python `$EVAL -m `$AutoDL3DGSRemoteModelDir"
"@

$raw = Invoke-AutoDLSSH -Config $cfg -RemoteCommand $remoteDiscover
[System.IO.File]::WriteAllText($OutputPath, ($raw -join "`n"), [System.Text.UTF8Encoding]::new($false))
Write-Host ($raw -join "`n")
Write-Host ""
Write-Host "Remote 3DGS discovery saved to: $OutputPath"
