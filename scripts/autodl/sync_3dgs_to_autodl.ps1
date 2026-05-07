param(
    [switch]$KeepArchive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "common.ps1")

$cfg = Import-AutoDL3DGSConfig
$repoRoot = (Resolve-Path $cfg.AutoDL3DGSLocalProjectDir).Path
$ignorePath = Get-AutoDL3DGSIgnorePath

if (-not (Test-Path $ignorePath)) {
    throw "Missing 3DGS ignore file: $ignorePath"
}

Assert-CommandExists -Name "tar"

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$archiveName = "autodl-3dgs-sync-$stamp.tar.gz"
$localArchivePath = Join-Path $env:TEMP $archiveName
$remoteArchivePath = "$($cfg.AutoDL3DGSRemoteArchiveDir)/$archiveName"

Write-Host "Preparing remote 3DGS directories..."
$remotePrep = @"
mkdir -p $(ConvertTo-BashSingleQuoted $cfg.AutoDL3DGSRemoteArchiveDir) \
         $(ConvertTo-BashSingleQuoted $cfg.AutoDL3DGSRemoteProjectDir) \
         $(ConvertTo-BashSingleQuoted $cfg.AutoDL3DGSRemoteLogDir) \
         $(ConvertTo-BashSingleQuoted $cfg.AutoDL3DGSRemoteDataRoot) \
         $(ConvertTo-BashSingleQuoted $cfg.AutoDL3DGSRemoteOutputRoot)
"@
Invoke-AutoDLSSH -Config $cfg -RemoteCommand $remotePrep

Write-Host "Packing local 3DGS source..."
Write-Host "repo root: $repoRoot"
Write-Host "ignore: $ignorePath"
Write-Host "local archive: $localArchivePath"
if (Test-Path $localArchivePath) {
    Remove-Item $localArchivePath -Force
}
& tar -czf $localArchivePath -X $ignorePath -C $repoRoot .
if ($LASTEXITCODE -ne 0) {
    throw "Local 3DGS archive creation failed with exit code $LASTEXITCODE"
}

Write-Host "Uploading archive..."
Write-Host "remote archive: $remoteArchivePath"
Invoke-AutoDLSCP -Config $cfg -LocalPath $localArchivePath -RemotePath $remoteArchivePath

Write-Host "Extracting archive on remote host..."
$remoteExtract = @"
set -e
mkdir -p $(ConvertTo-BashSingleQuoted $cfg.AutoDL3DGSRemoteProjectDir)
tar -xzf $(ConvertTo-BashSingleQuoted $remoteArchivePath) -C $(ConvertTo-BashSingleQuoted $cfg.AutoDL3DGSRemoteProjectDir)
"@
Invoke-AutoDLSSH -Config $cfg -RemoteCommand $remoteExtract

$remoteArchiveCleaned = $false
$localArchiveCleaned = $false
if (-not $KeepArchive) {
    if (Test-Path $localArchivePath) {
        Remove-Item $localArchivePath -Force
        $localArchiveCleaned = $true
    }

    $remoteCleanup = "rm -f $(ConvertTo-BashSingleQuoted $remoteArchivePath)"
    Invoke-AutoDLSSH -Config $cfg -RemoteCommand $remoteCleanup
    $remoteArchiveCleaned = $true
}

Write-Host ""
Write-Host "3DGS sync complete."
Write-Host "Remote project dir: $($cfg.AutoDL3DGSRemoteProjectDir)"
Write-Host "Remote archive: $remoteArchivePath"
Write-Host "Local archive cleaned: $localArchiveCleaned"
Write-Host "Remote archive cleaned: $remoteArchiveCleaned"
