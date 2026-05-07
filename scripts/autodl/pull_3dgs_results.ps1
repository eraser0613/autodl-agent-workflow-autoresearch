param(
    [string]$LocalDir,
    [switch]$IncludeCheckpoints
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "common.ps1")

$cfg = Import-AutoDL3DGSConfig
if ([string]::IsNullOrWhiteSpace($LocalDir)) {
    $LocalDir = $cfg.AutoDL3DGSLocalResultDir
}
if (-not [System.IO.Path]::IsPathRooted($LocalDir)) {
    $LocalDir = Join-Path (Get-AutoDLRepoRoot) $LocalDir
}
New-Item -ItemType Directory -Force -Path $LocalDir | Out-Null

$includes = New-Object System.Collections.Generic.List[string]
foreach ($item in @($cfg.AutoDL3DGSResultIncludes)) {
    if (-not [string]::IsNullOrWhiteSpace([string]$item)) {
        $includes.Add([string]$item)
    }
}
if ($IncludeCheckpoints) {
    $includes.Add("outputs/$($cfg.AutoDL3DGSSceneName)/point_cloud")
}
if ($includes.Count -eq 0) {
    $includes.Add("logs")
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$manifestName = "pull-3dgs-$stamp.txt"
$localManifestPath = Join-Path $env:TEMP $manifestName
$remoteManifestPath = "$($cfg.AutoDL3DGSRemoteArchiveDir)/$manifestName"
[System.IO.File]::WriteAllLines($localManifestPath, $includes, [System.Text.UTF8Encoding]::new($false))

Write-Host "Uploading pull manifest..."
Invoke-AutoDLSSH -Config $cfg -RemoteCommand "mkdir -p $(ConvertTo-BashSingleQuoted $cfg.AutoDL3DGSRemoteArchiveDir)"
Invoke-AutoDLSCP -Config $cfg -LocalPath $localManifestPath -RemotePath $remoteManifestPath

$remoteArchiveName = "3dgs-results-$stamp.tar.gz"
$remoteArchivePath = "$($cfg.AutoDL3DGSRemoteArchiveDir)/$remoteArchiveName"
$localArchivePath = Join-Path $env:TEMP $remoteArchiveName
$workspace = $cfg.AutoDL3DGSRemoteWorkspaceDir

$remotePack = @"
set -e
cd $(ConvertTo-BashSingleQuoted $workspace)
rm -f $(ConvertTo-BashSingleQuoted $remoteArchivePath)
TMP_INCLUDE=`$(mktemp)
while IFS= read -r item; do
  [ -z "`$item" ] && continue
  if [ -e "`$item" ]; then
    printf '%s\n' "`$item" >> "`$TMP_INCLUDE"
  else
    printf 'missing: %s\n' "`$item" >&2
  fi
done < $(ConvertTo-BashSingleQuoted $remoteManifestPath)
if [ ! -s "`$TMP_INCLUDE" ]; then
  echo 'No configured result artifacts exist on remote.' >&2
  rm -f "`$TMP_INCLUDE"
  exit 2
fi
tar -czf $(ConvertTo-BashSingleQuoted $remoteArchivePath) -T "`$TMP_INCLUDE"
rm -f "`$TMP_INCLUDE"
printf 'remote_archive=%s\n' $(ConvertTo-BashSingleQuoted $remoteArchivePath)
"@
Invoke-AutoDLSSH -Config $cfg -RemoteCommand $remotePack

Write-Host "Downloading result archive..."
Invoke-AutoDLSCPFromRemote -Config $cfg -RemotePath $remoteArchivePath -LocalPath $localArchivePath

Write-Host "Extracting results..."
& tar -xzf $localArchivePath -C $LocalDir
if ($LASTEXITCODE -ne 0) {
    throw "Local result extraction failed with exit code $LASTEXITCODE"
}

Remove-Item $localManifestPath -Force
Remove-Item $localArchivePath -Force
Invoke-AutoDLSSH -Config $cfg -RemoteCommand "rm -f $(ConvertTo-BashSingleQuoted $remoteManifestPath) $(ConvertTo-BashSingleQuoted $remoteArchivePath)"

Write-Host ""
Write-Host "3DGS results pulled."
Write-Host "Local result dir: $LocalDir"
Write-Host "Included paths:"
foreach ($item in $includes) {
    Write-Host "- $item"
}
