param(
    [string]$SceneDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "common.ps1")

$cfg = Import-AutoDL3DGSConfig
if ([string]::IsNullOrWhiteSpace($SceneDir)) {
    $SceneDir = $cfg.AutoDL3DGSRemoteSceneDir
}

$remoteCheck = @"
set +e
SCENE_DIR=$(ConvertTo-BashSingleQuoted $SceneDir)
echo '=== 3DGS dataset check ==='
echo "scene_dir=`$SCENE_DIR"
if [ ! -d "`$SCENE_DIR" ]; then
  echo "status=missing_scene_dir"
  exit 0
fi
echo "status=scene_dir_exists"
du -sh "`$SCENE_DIR" 2>/dev/null || true
echo
echo '=== common image directories ==='
for d in images input; do
  if [ -d "`$SCENE_DIR/`$d" ]; then
    count=`$(find "`$SCENE_DIR/`$d" -maxdepth 1 -type f 2>/dev/null | wc -l)
    echo "found: `$d files=`$count"
  else
    echo "missing: `$d"
  fi
done
echo
echo '=== colmap sparse directories ==='
for d in sparse sparse/0 distorted/sparse distorted/sparse/0; do
  if [ -d "`$SCENE_DIR/`$d" ]; then
    echo "found: `$d"
    ls -1 "`$SCENE_DIR/`$d" 2>/dev/null | head -n 20
  else
    echo "missing: `$d"
  fi
done
echo
echo '=== root files ==='
ls -la "`$SCENE_DIR" 2>/dev/null | head -n 80
"@

Invoke-AutoDLSSH -Config $cfg -RemoteCommand $remoteCheck
