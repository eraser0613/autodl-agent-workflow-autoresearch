param(
    [switch]$NoSync,
    [string]$SessionName,
    [switch]$UseEnvironmentFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "common.ps1")

$cfg = Import-AutoDL3DGSConfig
if ([string]::IsNullOrWhiteSpace($SessionName)) {
    $SessionName = $cfg.AutoDL3DGSSetupSessionName
}

if (-not $NoSync) {
    & (Join-Path $PSScriptRoot "sync_3dgs_to_autodl.ps1")
    if ($LASTEXITCODE -ne 0) {
        throw "3DGS sync failed. Bootstrap launch aborted."
    }
}

$pythonVersion = $cfg.AutoDL3DGSPythonVersion
$envName = $cfg.AutoDL3DGSRemoteCondaEnv

$bootstrapCommand = @"
set -euo pipefail
if ! conda env list | awk '{print `$1}' | grep -Fxq $(ConvertTo-BashSingleQuoted $envName); then
  if [ "$(if ($UseEnvironmentFile) { "1" } else { "0" })" = "1" ] && [ -f environment.yml ]; then
    conda env create -n $(ConvertTo-BashSingleQuoted $envName) -f environment.yml || conda create -n $(ConvertTo-BashSingleQuoted $envName) python=$(ConvertTo-BashSingleQuoted $pythonVersion) -y
  elif [ "$(if ($UseEnvironmentFile) { "1" } else { "0" })" = "1" ] && [ -f environment.yaml ]; then
    conda env create -n $(ConvertTo-BashSingleQuoted $envName) -f environment.yaml || conda create -n $(ConvertTo-BashSingleQuoted $envName) python=$(ConvertTo-BashSingleQuoted $pythonVersion) -y
  else
    conda create -n $(ConvertTo-BashSingleQuoted $envName) python=$(ConvertTo-BashSingleQuoted $pythonVersion) -y
  fi
fi
conda activate $(ConvertTo-BashSingleQuoted $envName)
python -m pip install --upgrade pip setuptools wheel
"@

$setupCommands = @($cfg.AutoDL3DGSSetupCommands) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
if ($setupCommands.Count -gt 0) {
    $bootstrapCommand += "`n" + ($setupCommands -join "`n")
}

Start-AutoDLRemoteLauncher `
    -Config $cfg `
    -SessionName $SessionName `
    -Command $bootstrapCommand `
    -LogPrefix $SessionName `
    -RemoteProjectDir $cfg.AutoDL3DGSRemoteProjectDir `
    -RemoteArchiveDir $cfg.AutoDL3DGSRemoteArchiveDir `
    -RemoteLogDir $cfg.AutoDL3DGSRemoteLogDir `
    -RemoteCondaInit $cfg.AutoDL3DGSRemoteCondaInit `
    -RemoteCondaEnv "base" `
    -RemoteMultiplexer $cfg.AutoDL3DGSRemoteMultiplexer | Out-Null
