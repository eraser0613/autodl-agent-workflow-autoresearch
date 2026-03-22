param(
    [switch]$KeepArchive
)

. (Join-Path $PSScriptRoot "common.ps1")

$cfg = Import-AutoDLConfig
$repoRoot = Get-AutoDLRepoRoot
$ignorePath = Get-AutoDLIgnorePath

Assert-CommandExists -Name "tar"

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$archiveName = "autodl-sync-$stamp.tar.gz"
$localArchivePath = Join-Path $env:TEMP $archiveName
$remoteArchivePath = "$($cfg.AutoDLRemoteArchiveDir)/$archiveName"

Write-Host "Preparing remote directories..."
$remotePrep = @"
mkdir -p $(ConvertTo-BashSingleQuoted $cfg.AutoDLRemoteArchiveDir) \
         $(ConvertTo-BashSingleQuoted $cfg.AutoDLRemoteProjectDir) \
         $(ConvertTo-BashSingleQuoted $cfg.AutoDLRemoteLogDir)
"@
Invoke-AutoDLSSH -Config $cfg -RemoteCommand $remotePrep

Write-Host "Packing local code..."
if (Test-Path $localArchivePath) {
    Remove-Item $localArchivePath -Force
}
& tar -czf $localArchivePath -X $ignorePath -C $repoRoot .
if ($LASTEXITCODE -ne 0) {
    throw "Local archive creation failed with exit code $LASTEXITCODE"
}

Write-Host "Uploading archive..."
Invoke-AutoDLSCP -Config $cfg -LocalPath $localArchivePath -RemotePath $remoteArchivePath

Write-Host "Extracting archive on remote host..."
$remoteExtract = @"
set -e
mkdir -p $(ConvertTo-BashSingleQuoted $cfg.AutoDLRemoteProjectDir)
tar -xzf $(ConvertTo-BashSingleQuoted $remoteArchivePath) -C $(ConvertTo-BashSingleQuoted $cfg.AutoDLRemoteProjectDir)
"@
Invoke-AutoDLSSH -Config $cfg -RemoteCommand $remoteExtract

if (-not $KeepArchive) {
    if (Test-Path $localArchivePath) {
        Remove-Item $localArchivePath -Force
    }

    $remoteCleanup = "rm -f $(ConvertTo-BashSingleQuoted $remoteArchivePath)"
    Invoke-AutoDLSSH -Config $cfg -RemoteCommand $remoteCleanup
}

Write-Host ""
Write-Host "Sync complete."
Write-Host "Remote project dir: $($cfg.AutoDLRemoteProjectDir)"
