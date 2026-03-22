Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-AutoDLRepoRoot {
    return Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}

function Get-AutoDLConfigPath {
    return Join-Path $PSScriptRoot "autodl.config.ps1"
}

function Get-AutoDLIgnorePath {
    return Join-Path $PSScriptRoot ".autodlignore"
}

function Assert-CommandExists {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Missing command '$Name'. Add it to PATH first."
    }
}

function ConvertTo-BashSingleQuoted {
    param(
        [AllowNull()]
        [string]$Value
    )

    if ($null -eq $Value) {
        return "''"
    }

    $replacement = @("'", '"', "'", '"', "'") -join ""
    return "'" + $Value.Replace("'", $replacement) + "'"
}

function Import-AutoDLConfig {
    $configPath = Get-AutoDLConfigPath
    if (-not (Test-Path $configPath)) {
        $examplePath = Join-Path $PSScriptRoot "autodl.config.ps1.example"
        throw "Missing config: $configPath`nCreate it first:`nCopy-Item '$examplePath' '$configPath'"
    }

    . $configPath

    $cfg = [ordered]@{
        AutoDLHostAlias          = $AutoDLHostAlias
        AutoDLRemoteProjectDir   = $AutoDLRemoteProjectDir
        AutoDLRemoteArchiveDir   = if ($AutoDLRemoteArchiveDir) { $AutoDLRemoteArchiveDir } else { "$AutoDLRemoteProjectDir/.codex-sync" }
        AutoDLRemoteCondaInit    = if ($AutoDLRemoteCondaInit) { $AutoDLRemoteCondaInit } else { "/root/miniconda3/etc/profile.d/conda.sh" }
        AutoDLRemoteCondaEnv     = $AutoDLRemoteCondaEnv
        AutoDLRemoteMultiplexer  = if ($AutoDLRemoteMultiplexer) { $AutoDLRemoteMultiplexer } else { "auto" }
        AutoDLDefaultTmuxSession = if ($AutoDLDefaultTmuxSession) { $AutoDLDefaultTmuxSession } else { "train" }
        AutoDLRemoteLogDir       = if ($AutoDLRemoteLogDir) { $AutoDLRemoteLogDir } else { "$AutoDLRemoteProjectDir/.autodl-logs" }
        AutoDLTensorBoardLogDir  = $AutoDLTensorBoardLogDir
        AutoDLTensorBoardPort    = if ($AutoDLTensorBoardPort) { [int]$AutoDLTensorBoardPort } else { 6006 }
        AutoDLTrainEntry         = $AutoDLTrainEntry
    }

    $required = @(
        "AutoDLHostAlias",
        "AutoDLRemoteProjectDir",
        "AutoDLRemoteCondaEnv",
        "AutoDLTensorBoardLogDir",
        "AutoDLTrainEntry"
    )

    foreach ($name in $required) {
        if ([string]::IsNullOrWhiteSpace([string]$cfg[$name])) {
            throw "Config value '$name' is required. Edit $(Get-AutoDLConfigPath)"
        }
    }

    return [pscustomobject]$cfg
}

function Invoke-AutoDLSSH {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config,
        [Parameter(Mandatory = $true)]
        [string]$RemoteCommand
    )

    Assert-CommandExists -Name "ssh"
    & ssh $Config.AutoDLHostAlias $RemoteCommand
    if ($LASTEXITCODE -ne 0) {
        throw "Remote command failed with exit code $LASTEXITCODE"
    }
}

function Invoke-AutoDLSCP {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config,
        [Parameter(Mandatory = $true)]
        [string]$LocalPath,
        [Parameter(Mandatory = $true)]
        [string]$RemotePath
    )

    Assert-CommandExists -Name "scp"
    & scp $LocalPath "$($Config.AutoDLHostAlias):$RemotePath"
    if ($LASTEXITCODE -ne 0) {
        throw "SCP failed with exit code $LASTEXITCODE"
    }
}
