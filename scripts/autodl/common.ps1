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

function ConvertTo-UnixLineEndings {
    param(
        [AllowNull()]
        [string]$Value
    )

    if ($null -eq $Value) {
        return $null
    }

    return $Value.Replace("`r`n", "`n").Replace("`r", "`n")
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

function Invoke-AutoDLSCPFromRemote {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config,
        [Parameter(Mandatory = $true)]
        [string]$RemotePath,
        [Parameter(Mandatory = $true)]
        [string]$LocalPath
    )

    Assert-CommandExists -Name "scp"
    & scp "$($Config.AutoDLHostAlias):$RemotePath" $LocalPath
    if ($LASTEXITCODE -ne 0) {
        throw "SCP download failed with exit code $LASTEXITCODE"
    }
}

function Get-AutoDL3DGSConfigPath {
    return Join-Path $PSScriptRoot "autodl.3dgs.config.ps1"
}

function Get-AutoDL3DGSIgnorePath {
    return Join-Path $PSScriptRoot ".autodlignore.3dgs"
}

function Get-AutoDLScopedValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [object]$Default = $null
    )

    $variable = Get-Variable -Name $Name -Scope 1 -ErrorAction SilentlyContinue
    if ($null -eq $variable) {
        return $Default
    }

    if ($null -eq $variable.Value) {
        return $Default
    }

    return $variable.Value
}

function Import-AutoDL3DGSConfig {
    $configPath = Get-AutoDL3DGSConfigPath
    if (-not (Test-Path $configPath)) {
        $examplePath = Join-Path $PSScriptRoot "autodl.3dgs.config.ps1.example"
        throw "Missing 3DGS config: $configPath`nCreate it first:`nCopy-Item '$examplePath' '$configPath'"
    }

    . $configPath

    $workspaceDir = Get-AutoDLScopedValue -Name "AutoDL3DGSRemoteWorkspaceDir"
    $sceneName = Get-AutoDLScopedValue -Name "AutoDL3DGSSceneName"
    $dataRoot = Get-AutoDLScopedValue -Name "AutoDL3DGSRemoteDataRoot" -Default $(if ($workspaceDir) { "$workspaceDir/data" } else { $null })
    $outputRoot = Get-AutoDLScopedValue -Name "AutoDL3DGSRemoteOutputRoot" -Default $(if ($workspaceDir) { "$workspaceDir/outputs" } else { $null })
    $remoteProjectDir = Get-AutoDLScopedValue -Name "AutoDL3DGSRemoteProjectDir" -Default $(if ($workspaceDir) { "$workspaceDir/project" } else { $null })
    $remoteArchiveDir = Get-AutoDLScopedValue -Name "AutoDL3DGSRemoteArchiveDir" -Default $(if ($workspaceDir) { "$workspaceDir/.autodl-sync" } else { $null })
    $remoteLogDir = Get-AutoDLScopedValue -Name "AutoDL3DGSRemoteLogDir" -Default $(if ($workspaceDir) { "$workspaceDir/logs" } else { $null })
    $remoteSceneDir = Get-AutoDLScopedValue -Name "AutoDL3DGSRemoteSceneDir" -Default $(if ($dataRoot -and $sceneName) { "$dataRoot/$sceneName" } else { $null })
    $remoteModelDir = Get-AutoDLScopedValue -Name "AutoDL3DGSRemoteModelDir" -Default $(if ($outputRoot -and $sceneName) { "$outputRoot/$sceneName" } else { $null })

    $cfg = [ordered]@{
        AutoDLHostAlias                  = Get-AutoDLScopedValue -Name "AutoDLHostAlias"
        AutoDL3DGSLocalProjectDir        = Get-AutoDLScopedValue -Name "AutoDL3DGSLocalProjectDir" -Default (Get-AutoDLRepoRoot)
        AutoDLRemoteProjectDir           = $remoteProjectDir
        AutoDLRemoteArchiveDir           = $remoteArchiveDir
        AutoDLRemoteCondaInit            = Get-AutoDLScopedValue -Name "AutoDL3DGSRemoteCondaInit" -Default "/root/miniconda3/etc/profile.d/conda.sh"
        AutoDLRemoteCondaEnv             = Get-AutoDLScopedValue -Name "AutoDL3DGSRemoteCondaEnv"
        AutoDLRemoteMultiplexer          = Get-AutoDLScopedValue -Name "AutoDL3DGSRemoteMultiplexer" -Default "auto"
        AutoDLDefaultTmuxSession         = Get-AutoDLScopedValue -Name "AutoDL3DGSTrainSessionName" -Default "3dgs-train"
        AutoDLRemoteLogDir               = $remoteLogDir
        AutoDLTensorBoardLogDir          = Get-AutoDLScopedValue -Name "AutoDL3DGSTensorBoardLogDir" -Default $outputRoot
        AutoDLTensorBoardPort            = [int](Get-AutoDLScopedValue -Name "AutoDL3DGSTensorBoardPort" -Default 6006)
        AutoDL3DGSRemoteWorkspaceDir     = $workspaceDir
        AutoDL3DGSRemoteProjectDir       = $remoteProjectDir
        AutoDL3DGSRemoteArchiveDir       = $remoteArchiveDir
        AutoDL3DGSRemoteDataRoot         = $dataRoot
        AutoDL3DGSSceneName              = $sceneName
        AutoDL3DGSRemoteSceneDir         = $remoteSceneDir
        AutoDL3DGSRemoteOutputRoot       = $outputRoot
        AutoDL3DGSRemoteModelDir         = $remoteModelDir
        AutoDL3DGSRemoteLogDir           = $remoteLogDir
        AutoDL3DGSRemoteCondaInit        = Get-AutoDLScopedValue -Name "AutoDL3DGSRemoteCondaInit" -Default "/root/miniconda3/etc/profile.d/conda.sh"
        AutoDL3DGSRemoteCondaEnv         = Get-AutoDLScopedValue -Name "AutoDL3DGSRemoteCondaEnv"
        AutoDL3DGSPythonVersion          = Get-AutoDLScopedValue -Name "AutoDL3DGSPythonVersion" -Default "3.8"
        AutoDL3DGSRemoteMultiplexer      = Get-AutoDLScopedValue -Name "AutoDL3DGSRemoteMultiplexer" -Default "auto"
        AutoDL3DGSTrainSessionName       = Get-AutoDLScopedValue -Name "AutoDL3DGSTrainSessionName" -Default "3dgs-train"
        AutoDL3DGSRenderSessionName      = Get-AutoDLScopedValue -Name "AutoDL3DGSRenderSessionName" -Default "3dgs-render"
        AutoDL3DGSEvalSessionName        = Get-AutoDLScopedValue -Name "AutoDL3DGSEvalSessionName" -Default "3dgs-eval"
        AutoDL3DGSSetupSessionName       = Get-AutoDLScopedValue -Name "AutoDL3DGSSetupSessionName" -Default "3dgs-setup"
        AutoDL3DGSTensorBoardLogDir      = Get-AutoDLScopedValue -Name "AutoDL3DGSTensorBoardLogDir" -Default $outputRoot
        AutoDL3DGSTensorBoardPort        = [int](Get-AutoDLScopedValue -Name "AutoDL3DGSTensorBoardPort" -Default 6006)
        AutoDL3DGSTrainCommand           = Get-AutoDLScopedValue -Name "AutoDL3DGSTrainCommand"
        AutoDL3DGSRenderCommand          = Get-AutoDLScopedValue -Name "AutoDL3DGSRenderCommand"
        AutoDL3DGSEvalCommand            = Get-AutoDLScopedValue -Name "AutoDL3DGSEvalCommand"
        AutoDL3DGSSetupCommands          = @(Get-AutoDLScopedValue -Name "AutoDL3DGSSetupCommands" -Default @())
        AutoDL3DGSResultIncludes         = @(Get-AutoDLScopedValue -Name "AutoDL3DGSResultIncludes" -Default @())
        AutoDL3DGSLocalResultDir         = Get-AutoDLScopedValue -Name "AutoDL3DGSLocalResultDir" -Default (Join-Path (Join-Path (Get-AutoDLRepoRoot) "result") "3dgs")
    }

    $required = @(
        "AutoDLHostAlias",
        "AutoDL3DGSRemoteWorkspaceDir",
        "AutoDL3DGSRemoteProjectDir",
        "AutoDL3DGSRemoteArchiveDir",
        "AutoDL3DGSRemoteDataRoot",
        "AutoDL3DGSSceneName",
        "AutoDL3DGSRemoteSceneDir",
        "AutoDL3DGSRemoteOutputRoot",
        "AutoDL3DGSRemoteModelDir",
        "AutoDL3DGSRemoteLogDir",
        "AutoDL3DGSRemoteCondaEnv",
        "AutoDL3DGSTrainCommand",
        "AutoDL3DGSRenderCommand",
        "AutoDL3DGSEvalCommand"
    )

    foreach ($name in $required) {
        if ([string]::IsNullOrWhiteSpace([string]$cfg[$name])) {
            throw "3DGS config value '$name' is required. Edit $(Get-AutoDL3DGSConfigPath)"
        }
    }

    return [pscustomobject]$cfg
}

function Start-AutoDLRemoteLauncher {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config,
        [Parameter(Mandatory = $true)]
        [string]$SessionName,
        [Parameter(Mandatory = $true)]
        [string]$Command,
        [string]$LogPrefix = $SessionName,
        [string]$RemoteProjectDir = $Config.AutoDLRemoteProjectDir,
        [string]$RemoteArchiveDir = $Config.AutoDLRemoteArchiveDir,
        [string]$RemoteLogDir = $Config.AutoDLRemoteLogDir,
        [string]$RemoteCondaInit = $Config.AutoDLRemoteCondaInit,
        [string]$RemoteCondaEnv = $Config.AutoDLRemoteCondaEnv,
        [string]$RemoteMultiplexer = $Config.AutoDLRemoteMultiplexer,
        [hashtable]$Environment = @{}
    )

    if ([string]::IsNullOrWhiteSpace($SessionName)) {
        throw "SessionName is required."
    }
    if ([string]::IsNullOrWhiteSpace($Command)) {
        throw "Command is required."
    }

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $remoteLauncherPath = "$RemoteArchiveDir/launch-$LogPrefix-$timestamp.sh"
    $remoteLogFile = "$RemoteLogDir/$LogPrefix-$timestamp.log"
    $localLauncherPath = Join-Path $env:TEMP "launch-$LogPrefix-$timestamp.sh"

    $envLines = New-Object System.Collections.Generic.List[string]
    foreach ($key in $Environment.Keys) {
        $envLines.Add("export $key=$(ConvertTo-BashSingleQuoted ([string]$Environment[$key]))")
    }
    $environmentBlock = ($envLines -join "`n")

    $launcherContent = @"
#!/usr/bin/env bash
set -euo pipefail
mkdir -p $(ConvertTo-BashSingleQuoted $RemoteLogDir)
cd $(ConvertTo-BashSingleQuoted $RemoteProjectDir)
source $(ConvertTo-BashSingleQuoted $RemoteCondaInit)
conda activate $(ConvertTo-BashSingleQuoted $RemoteCondaEnv)
$environmentBlock
`{
$Command
`} 2>&1 | tee $(ConvertTo-BashSingleQuoted $remoteLogFile)
"@
    [System.IO.File]::WriteAllText(
        $localLauncherPath,
        $launcherContent,
        [System.Text.UTF8Encoding]::new($false)
    )

    $remotePrep = "mkdir -p $(ConvertTo-BashSingleQuoted $RemoteArchiveDir) $(ConvertTo-BashSingleQuoted $RemoteLogDir)"
    Invoke-AutoDLSSH -Config $Config -RemoteCommand (ConvertTo-UnixLineEndings $remotePrep)

    Write-Host "Uploading remote launcher..."
    Invoke-AutoDLSCP -Config $Config -LocalPath $localLauncherPath -RemotePath $remoteLauncherPath

    $remoteStart = @"
set -e
chmod +x $(ConvertTo-BashSingleQuoted $remoteLauncherPath)
MUX_MODE=$(ConvertTo-BashSingleQuoted $RemoteMultiplexer)
if [ "`$MUX_MODE" = "auto" ]; then
  if command -v tmux >/dev/null 2>&1; then
    MUX_MODE=tmux
  elif command -v screen >/dev/null 2>&1; then
    MUX_MODE=screen
  else
    echo "Neither tmux nor screen is installed" >&2
    exit 1
  fi
fi
if [ "`$MUX_MODE" = "tmux" ]; then
  if tmux has-session -t $(ConvertTo-BashSingleQuoted $SessionName) 2>/dev/null; then
    tmux kill-session -t $(ConvertTo-BashSingleQuoted $SessionName)
  fi
  tmux new-session -d -s $(ConvertTo-BashSingleQuoted $SessionName) "bash $(ConvertTo-BashSingleQuoted $remoteLauncherPath)"
else
  screen -S $(ConvertTo-BashSingleQuoted $SessionName) -X quit >/dev/null 2>&1 || true
  screen -dmS $(ConvertTo-BashSingleQuoted $SessionName) bash $(ConvertTo-BashSingleQuoted $remoteLauncherPath)
fi
printf 'mux=%s\n' "`$MUX_MODE"
printf 'session=%s\n' $(ConvertTo-BashSingleQuoted $SessionName)
printf 'launcher=%s\n' $(ConvertTo-BashSingleQuoted $remoteLauncherPath)
printf 'log=%s\n' $(ConvertTo-BashSingleQuoted $remoteLogFile)
"@

    Invoke-AutoDLSSH -Config $Config -RemoteCommand (ConvertTo-UnixLineEndings $remoteStart)
    Remove-Item $localLauncherPath -Force

    Write-Host ""
    Write-Host "Remote command started."
    Write-Host "session: $SessionName"
    Write-Host "launcher: $remoteLauncherPath"
    Write-Host "log file: $remoteLogFile"

    return [pscustomobject]@{
        SessionName = $SessionName
        LauncherPath = $remoteLauncherPath
        LogFile = $remoteLogFile
    }
}

function Get-AutoDLAgentConfigPath {
    $override = Get-Variable -Name "AutoDLAgentConfigPathOverride" -Scope Script -ErrorAction SilentlyContinue
    if ($override -and -not [string]::IsNullOrWhiteSpace([string]$override.Value)) {
        return Resolve-AutoDLLocalPath ([string]$override.Value)
    }

    return Join-Path $PSScriptRoot "autodl.agent.config.ps1"
}

function Assert-AutoDLAgentName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        throw "$Name is required."
    }
    if ($Value -notmatch '^[A-Za-z0-9._-]+$') {
        throw "$Name may only contain letters, numbers, dot, underscore, and dash: $Value"
    }
}

function Join-AutoDLRemotePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Base,
        [Parameter(Mandatory = $true)]
        [string]$Child
    )

    return $Base.TrimEnd('/') + '/' + $Child.TrimStart('/')
}

function Resolve-AutoDLLocalPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return $Path
    }

    return Join-Path (Get-AutoDLRepoRoot) $Path
}

function Import-AutoDLAgentConfig {
    $configPath = Get-AutoDLAgentConfigPath
    if (-not (Test-Path $configPath)) {
        $examplePath = Join-Path $PSScriptRoot "autodl.agent.config.ps1.example"
        throw "Missing agent config: $configPath`nCreate it first:`nCopy-Item '$examplePath' '$configPath'"
    }

    . $configPath

    $remoteRoot = Get-AutoDLScopedValue -Name "AutoDLAgentRemoteRoot" -Default "/root/autodl-tmp/agent-workspace"
    $localRunsDir = Resolve-AutoDLLocalPath (Get-AutoDLScopedValue -Name "AutoDLAgentLocalRunsDir" -Default "result/agent-runs")

    $cfg = [ordered]@{
        AutoDLAgentConfigPath                   = $configPath
        AutoDLHostAlias                         = Get-AutoDLScopedValue -Name "AutoDLAgentHostAlias"
        AutoDLAgentHostAlias                    = Get-AutoDLScopedValue -Name "AutoDLAgentHostAlias"
        AutoDLAgentRemoteRoot                   = $remoteRoot
        AutoDLAgentRemoteReposDir               = Get-AutoDLScopedValue -Name "AutoDLAgentRemoteReposDir" -Default (Join-AutoDLRemotePath $remoteRoot "repos")
        AutoDLAgentRemoteRunsDir                = Get-AutoDLScopedValue -Name "AutoDLAgentRemoteRunsDir" -Default (Join-AutoDLRemotePath $remoteRoot "runs")
        AutoDLAgentRemoteArtifactsDir           = Get-AutoDLScopedValue -Name "AutoDLAgentRemoteArtifactsDir" -Default (Join-AutoDLRemotePath $remoteRoot "artifacts")
        AutoDLAgentLocalRunsDir                 = $localRunsDir
        AutoDLAgentCondaInit                    = Get-AutoDLScopedValue -Name "AutoDLAgentCondaInit" -Default "/root/miniconda3/etc/profile.d/conda.sh"
        AutoDLAgentDefaultCondaEnv              = Get-AutoDLScopedValue -Name "AutoDLAgentDefaultCondaEnv" -Default "base"
        AutoDLAgentRemoteMultiplexer            = Get-AutoDLScopedValue -Name "AutoDLAgentRemoteMultiplexer" -Default "auto"
        AutoDLAgentRemotePrelude                = Get-AutoDLScopedValue -Name "AutoDLAgentRemotePrelude" -Default ""
        AutoDLAgentAllowOutsideWorkspace        = [bool](Get-AutoDLScopedValue -Name "AutoDLAgentAllowOutsideWorkspace" -Default $false)
        AutoDLAgentRequireConfirmForDestructive = [bool](Get-AutoDLScopedValue -Name "AutoDLAgentRequireConfirmForDestructive" -Default $true)
        AutoDLAgentSecretEnvNames               = @(Get-AutoDLScopedValue -Name "AutoDLAgentSecretEnvNames" -Default @())
    }

    $required = @(
        "AutoDLAgentHostAlias",
        "AutoDLAgentRemoteRoot",
        "AutoDLAgentRemoteReposDir",
        "AutoDLAgentRemoteRunsDir",
        "AutoDLAgentLocalRunsDir"
    )

    foreach ($name in $required) {
        if ([string]::IsNullOrWhiteSpace([string]$cfg[$name])) {
            throw "Agent config value '$name' is required. Edit $(Get-AutoDLAgentConfigPath)"
        }
    }

    return [pscustomobject]$cfg
}

function ConvertTo-AutoDLMaskedText {
    param(
        [AllowNull()]
        [string]$Text,
        [pscustomobject]$Config
    )

    if ($null -eq $Text) {
        return $null
    }

    $masked = $Text
    $secretNames = @()
    if ($Config -and $Config.PSObject.Properties.Name -contains "AutoDLAgentSecretEnvNames") {
        $secretNames = @($Config.AutoDLAgentSecretEnvNames)
    }

    foreach ($name in $secretNames) {
        if (-not [string]::IsNullOrWhiteSpace([string]$name)) {
            $escaped = [regex]::Escape([string]$name)
            $masked = [regex]::Replace($masked, "(?i)($escaped\s*[:=]\s*)[^\s'\"";]+", '$1***SECRET***')
        }
    }

    $masked = [regex]::Replace($masked, 'gh[pousr]_[A-Za-z0-9_]{20,}', '***SECRET***')
    $masked = [regex]::Replace($masked, 'hf_[A-Za-z0-9]{20,}', '***SECRET***')
    $masked = [regex]::Replace($masked, 'sk-[A-Za-z0-9_-]{20,}', '***SECRET***')
    $masked = [regex]::Replace($masked, 'https://[^\s/@:]+:[^\s/@]+@', 'https://***SECRET***@')

    return $masked
}

function Initialize-AutoDLAgentWorkspace {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    New-Item -ItemType Directory -Force -Path $Config.AutoDLAgentLocalRunsDir | Out-Null
    $remoteInit = @"
set -e
mkdir -p $(ConvertTo-BashSingleQuoted $Config.AutoDLAgentRemoteRoot) \
         $(ConvertTo-BashSingleQuoted $Config.AutoDLAgentRemoteReposDir) \
         $(ConvertTo-BashSingleQuoted $Config.AutoDLAgentRemoteRunsDir) \
         $(ConvertTo-BashSingleQuoted $Config.AutoDLAgentRemoteArtifactsDir)
"@
    Invoke-AutoDLSSH -Config $Config -RemoteCommand (ConvertTo-UnixLineEndings $remoteInit)
}

function Get-AutoDLAgentCurrentRunPath {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    return Join-Path $Config.AutoDLAgentLocalRunsDir "CURRENT"
}

function Set-AutoDLAgentCurrentRun {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config,
        [Parameter(Mandatory = $true)]
        [string]$RunId
    )

    New-Item -ItemType Directory -Force -Path $Config.AutoDLAgentLocalRunsDir | Out-Null
    Set-Content -Path (Get-AutoDLAgentCurrentRunPath $Config) -Value $RunId -Encoding UTF8
}

function Get-AutoDLAgentCurrentRun {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    $path = Get-AutoDLAgentCurrentRunPath $Config
    if (-not (Test-Path $path)) {
        return $null
    }

    $runId = (Get-Content -Path $path -Raw).Trim()
    if ([string]::IsNullOrWhiteSpace($runId)) {
        return $null
    }
    return $runId
}

function Resolve-AutoDLAgentRunDir {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config,
        [Parameter(Mandatory = $true)]
        [string]$RunId
    )

    Assert-AutoDLAgentName -Name "RunId" -Value $RunId
    return Join-Path $Config.AutoDLAgentLocalRunsDir $RunId
}

function Resolve-AutoDLAgentRemoteRunDir {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config,
        [Parameter(Mandatory = $true)]
        [string]$RunId
    )

    Assert-AutoDLAgentName -Name "RunId" -Value $RunId
    return Join-AutoDLRemotePath $Config.AutoDLAgentRemoteRunsDir $RunId
}

function New-AutoDLAgentRun {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config,
        [string]$RunId,
        [string]$RepoName,
        [string]$RepoUrl,
        [string]$Ref
    )

    Initialize-AutoDLAgentWorkspace -Config $Config

    if ([string]::IsNullOrWhiteSpace($RunId)) {
        $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
        if ([string]::IsNullOrWhiteSpace($RepoName)) {
            $RunId = "$stamp-agent"
        } else {
            Assert-AutoDLAgentName -Name "RepoName" -Value $RepoName
            $RunId = "$stamp-$RepoName"
        }
    } else {
        Assert-AutoDLAgentName -Name "RunId" -Value $RunId
    }

    $localRunDir = Resolve-AutoDLAgentRunDir -Config $Config -RunId $RunId
    $remoteRunDir = Resolve-AutoDLAgentRemoteRunDir -Config $Config -RunId $RunId
    New-Item -ItemType Directory -Force -Path $localRunDir | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $localRunDir "stdout") | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $localRunDir "stderr") | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $localRunDir "launchers") | Out-Null

    $remotePrep = @"
set -e
mkdir -p $(ConvertTo-BashSingleQuoted $remoteRunDir) \
         $(ConvertTo-BashSingleQuoted (Join-AutoDLRemotePath $remoteRunDir "logs")) \
         $(ConvertTo-BashSingleQuoted (Join-AutoDLRemotePath $remoteRunDir "launchers")) \
         $(ConvertTo-BashSingleQuoted (Join-AutoDLRemotePath $remoteRunDir "artifacts"))
"@
    Invoke-AutoDLSSH -Config $Config -RemoteCommand (ConvertTo-UnixLineEndings $remotePrep)

    $manifest = [ordered]@{
        run_id = $RunId
        repo_name = $RepoName
        repo_url = $RepoUrl
        ref = $Ref
        host_alias = $Config.AutoDLAgentHostAlias
        remote_root = $Config.AutoDLAgentRemoteRoot
        remote_repos_dir = $Config.AutoDLAgentRemoteReposDir
        remote_run_dir = $remoteRunDir
        local_run_dir = $localRunDir
        created_at = (Get-Date).ToString("o")
    }

    $manifestPath = Join-Path $localRunDir "run.json"
    $manifest | ConvertTo-Json -Depth 8 | Set-Content -Path $manifestPath -Encoding UTF8
    Set-AutoDLAgentCurrentRun -Config $Config -RunId $RunId

    return [pscustomobject]@{
        RunId = $RunId
        LocalRunDir = $localRunDir
        RemoteRunDir = $remoteRunDir
        ManifestPath = $manifestPath
    }
}

function Resolve-AutoDLAgentRunId {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config,
        [string]$RunId,
        [string]$RepoName,
        [string]$RepoUrl,
        [string]$Ref
    )

    if (-not [string]::IsNullOrWhiteSpace($RunId)) {
        Assert-AutoDLAgentName -Name "RunId" -Value $RunId
        $localRunDir = Resolve-AutoDLAgentRunDir -Config $Config -RunId $RunId
        if (-not (Test-Path $localRunDir)) {
            New-AutoDLAgentRun -Config $Config -RunId $RunId -RepoName $RepoName -RepoUrl $RepoUrl -Ref $Ref | Out-Null
        }
        return $RunId
    }

    $current = Get-AutoDLAgentCurrentRun -Config $Config
    if (-not [string]::IsNullOrWhiteSpace($current)) {
        return $current
    }

    $run = New-AutoDLAgentRun -Config $Config -RepoName $RepoName -RepoUrl $RepoUrl -Ref $Ref
    return $run.RunId
}

function Get-AutoDLAgentNextSequence {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config,
        [Parameter(Mandatory = $true)]
        [string]$RunId
    )

    $commandsPath = Join-Path (Resolve-AutoDLAgentRunDir -Config $Config -RunId $RunId) "commands.jsonl"
    if (-not (Test-Path $commandsPath)) {
        return 1
    }

    $lines = @(Get-Content -Path $commandsPath)
    return $lines.Count + 1
}

function Write-AutoDLAgentCommandRecord {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config,
        [Parameter(Mandatory = $true)]
        [string]$RunId,
        [Parameter(Mandatory = $true)]
        [hashtable]$Record
    )

    $localRunDir = Resolve-AutoDLAgentRunDir -Config $Config -RunId $RunId
    New-Item -ItemType Directory -Force -Path $localRunDir | Out-Null
    $commandsPath = Join-Path $localRunDir "commands.jsonl"
    ($Record | ConvertTo-Json -Depth 12 -Compress) | Add-Content -Path $commandsPath -Encoding UTF8
}

function Test-AutoDLAgentDestructiveCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command
    )

    $patterns = @(
        '(^|[;&|]\s*)rm\s+-[^\n;&|]*[rf][^\n;&|]*\s+/(\s|$)',
        '(^|[;&|]\s*)rm\s+-[^\n;&|]*[rf][^\n;&|]*\s+\*',
        '(^|[;&|]\s*)(sudo\s+)?(shutdown|reboot|poweroff)\b',
        '(^|[;&|]\s*)(sudo\s+)?mkfs\b',
        '(^|[;&|]\s*)dd\s+[^\n;&|]*\bof=/dev/',
        '(^|[;&|]\s*)(sudo\s+)?(apt|apt-get|yum|dnf)\s+(install|remove|purge)\b',
        '(^|[;&|]\s*)(sudo\s+)?(chmod|chown)\s+-R\s+[^\n;&|]*\s+/'
    )

    foreach ($pattern in $patterns) {
        if ($Command -match $pattern) {
            return $true
        }
    }

    return $false
}

function Assert-AutoDLAgentCommandAllowed {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config,
        [Parameter(Mandatory = $true)]
        [string]$Command,
        [switch]$AllowDestructive
    )

    if ((Test-AutoDLAgentDestructiveCommand -Command $Command) -and $Config.AutoDLAgentRequireConfirmForDestructive -and -not $AllowDestructive) {
        throw "Command looks destructive or system-modifying. Re-run with -AllowDestructive only after reviewing it: $Command"
    }
}

function Resolve-AutoDLAgentRepoDir {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config,
        [Parameter(Mandatory = $true)]
        [string]$RepoName
    )

    Assert-AutoDLAgentName -Name "RepoName" -Value $RepoName
    return Join-AutoDLRemotePath $Config.AutoDLAgentRemoteReposDir $RepoName
}

function Resolve-AutoDLAgentRemoteCwd {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config,
        [string]$RepoName,
        [string]$Cwd,
        [string]$RemoteCwd
    )

    if (-not [string]::IsNullOrWhiteSpace($RemoteCwd)) {
        if ($RemoteCwd.StartsWith($Config.AutoDLAgentRemoteRoot) -or $Config.AutoDLAgentAllowOutsideWorkspace) {
            return $RemoteCwd
        }
        throw "RemoteCwd must stay under $($Config.AutoDLAgentRemoteRoot): $RemoteCwd"
    }

    if ([string]::IsNullOrWhiteSpace($RepoName)) {
        return $Config.AutoDLAgentRemoteRoot
    }

    $repoDir = Resolve-AutoDLAgentRepoDir -Config $Config -RepoName $RepoName
    if ([string]::IsNullOrWhiteSpace($Cwd) -or $Cwd -eq ".") {
        return $repoDir
    }
    if ($Cwd.Contains("..") -or $Cwd.Contains(";")) {
        throw "Cwd cannot contain '..' or ';': $Cwd"
    }
    if ($Cwd.StartsWith("/")) {
        if ($Cwd.StartsWith($Config.AutoDLAgentRemoteRoot) -or $Config.AutoDLAgentAllowOutsideWorkspace) {
            return $Cwd
        }
        throw "Cwd must stay under $($Config.AutoDLAgentRemoteRoot): $Cwd"
    }

    return Join-AutoDLRemotePath $repoDir $Cwd
}

function Invoke-AutoDLAgentCommand {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config,
        [Parameter(Mandatory = $true)]
        [string]$RunId,
        [Parameter(Mandatory = $true)]
        [string]$Command,
        [string]$RepoName,
        [string]$Cwd = ".",
        [string]$RemoteCwd,
        [string]$CondaEnv,
        [switch]$NoConda,
        [switch]$AllowDestructive,
        [int]$TailLines = 120
    )

    Assert-AutoDLAgentCommandAllowed -Config $Config -Command $Command -AllowDestructive:$AllowDestructive
    Assert-CommandExists -Name "ssh"
    Assert-CommandExists -Name "scp"

    $seq = Get-AutoDLAgentNextSequence -Config $Config -RunId $RunId
    $seqText = $seq.ToString("0000")
    $localRunDir = Resolve-AutoDLAgentRunDir -Config $Config -RunId $RunId
    $remoteRunDir = Resolve-AutoDLAgentRemoteRunDir -Config $Config -RunId $RunId
    $remoteLogsDir = Join-AutoDLRemotePath $remoteRunDir "logs"
    $remoteLaunchersDir = Join-AutoDLRemotePath $remoteRunDir "launchers"
    $remoteLogFile = Join-AutoDLRemotePath $remoteLogsDir "$seqText.log"
    $remoteLauncherPath = Join-AutoDLRemotePath $remoteLaunchersDir "$seqText.sh"
    $localLauncherPath = Join-Path (Join-Path $localRunDir "launchers") "$seqText.sh"
    $cwdResolved = Resolve-AutoDLAgentRemoteCwd -Config $Config -RepoName $RepoName -Cwd $Cwd -RemoteCwd $RemoteCwd
    $envName = if ([string]::IsNullOrWhiteSpace($CondaEnv)) { $Config.AutoDLAgentDefaultCondaEnv } else { $CondaEnv }
    $useConda = if ($NoConda) { "0" } else { "1" }
    $startedAt = Get-Date
    $prelude = if ($Config.PSObject.Properties.Name -contains "AutoDLAgentRemotePrelude") { [string]$Config.AutoDLAgentRemotePrelude } else { "" }

    $launcherContent = @"
#!/usr/bin/env bash
set +e
mkdir -p $(ConvertTo-BashSingleQuoted $remoteLogsDir)
cd $(ConvertTo-BashSingleQuoted $cwdResolved)
$prelude
if [ "$useConda" = "1" ] && [ -f $(ConvertTo-BashSingleQuoted $Config.AutoDLAgentCondaInit) ]; then
  source $(ConvertTo-BashSingleQuoted $Config.AutoDLAgentCondaInit)
  conda activate $(ConvertTo-BashSingleQuoted $envName)
fi
printf 'run_id=%s\n' $(ConvertTo-BashSingleQuoted $RunId) > $(ConvertTo-BashSingleQuoted $remoteLogFile)
printf 'seq=%s\n' $(ConvertTo-BashSingleQuoted $seqText) >> $(ConvertTo-BashSingleQuoted $remoteLogFile)
printf 'cwd=%s\n' `$(pwd) >> $(ConvertTo-BashSingleQuoted $remoteLogFile)
printf 'conda_env=%s\n' $(ConvertTo-BashSingleQuoted $(if ($NoConda) { "none" } else { $envName })) >> $(ConvertTo-BashSingleQuoted $remoteLogFile)
printf 'command=%s\n' $(ConvertTo-BashSingleQuoted $Command) >> $(ConvertTo-BashSingleQuoted $remoteLogFile)
printf '%s\n' '--- command output ---' >> $(ConvertTo-BashSingleQuoted $remoteLogFile)
{
$Command
} >> $(ConvertTo-BashSingleQuoted $remoteLogFile) 2>&1
status=`$?
printf '%s\n' '--- command exit ---' >> $(ConvertTo-BashSingleQuoted $remoteLogFile)
printf 'exit_code=%s\n' "`$status" >> $(ConvertTo-BashSingleQuoted $remoteLogFile)
exit `$status
"@

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $localLauncherPath) | Out-Null
    [System.IO.File]::WriteAllText($localLauncherPath, (ConvertTo-UnixLineEndings $launcherContent), [System.Text.UTF8Encoding]::new($false))

    $remotePrep = "mkdir -p $(ConvertTo-BashSingleQuoted $remoteLaunchersDir) $(ConvertTo-BashSingleQuoted $remoteLogsDir)"
    Invoke-AutoDLSSH -Config $Config -RemoteCommand (ConvertTo-UnixLineEndings $remotePrep) | Out-Null
    Invoke-AutoDLSCP -Config $Config -LocalPath $localLauncherPath -RemotePath $remoteLauncherPath | Out-Null

    $remoteRun = @"
set +e
bash $(ConvertTo-BashSingleQuoted $remoteLauncherPath)
status=`$?
echo "__AUTODL_AGENT_EXIT_CODE__=`$status"
echo "__AUTODL_AGENT_LOG__=$(ConvertTo-BashSingleQuoted $remoteLogFile)"
tail -n $TailLines $(ConvertTo-BashSingleQuoted $remoteLogFile) || true
exit `$status
"@

    $output = & ssh $Config.AutoDLAgentHostAlias (ConvertTo-UnixLineEndings $remoteRun) 2>&1
    $exitCode = $LASTEXITCODE
    $finishedAt = Get-Date
    $maskedOutput = ConvertTo-AutoDLMaskedText -Text (($output | Out-String).TrimEnd()) -Config $Config
    $stdoutPath = Join-Path (Join-Path $localRunDir "stdout") "$seqText.txt"
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $stdoutPath) | Out-Null
    Set-Content -Path $stdoutPath -Value $maskedOutput -Encoding UTF8

    $record = [ordered]@{
        seq = $seq
        run_id = $RunId
        kind = "foreground"
        repo_name = $RepoName
        cwd = $cwdResolved
        conda_env = if ($NoConda) { $null } else { $envName }
        command = ConvertTo-AutoDLMaskedText -Text $Command -Config $Config
        started_at = $startedAt.ToString("o")
        finished_at = $finishedAt.ToString("o")
        duration_ms = [int]($finishedAt - $startedAt).TotalMilliseconds
        exit_code = $exitCode
        remote_log = $remoteLogFile
        launcher = $remoteLauncherPath
        local_launcher = $localLauncherPath
        local_stdout = $stdoutPath
        replayable = ($exitCode -eq 0 -and -not (Test-AutoDLAgentDestructiveCommand -Command $Command))
        destructive = (Test-AutoDLAgentDestructiveCommand -Command $Command)
    }
    Write-AutoDLAgentCommandRecord -Config $Config -RunId $RunId -Record $record

    return [pscustomobject]@{
        RunId = $RunId
        Seq = $seq
        ExitCode = $exitCode
        RemoteLog = $remoteLogFile
        LocalStdout = $stdoutPath
        Output = $maskedOutput
    }
}

function Start-AutoDLAgentJob {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config,
        [Parameter(Mandatory = $true)]
        [string]$RunId,
        [Parameter(Mandatory = $true)]
        [string]$Command,
        [Parameter(Mandatory = $true)]
        [string]$SessionName,
        [string]$RepoName,
        [string]$Cwd = ".",
        [string]$RemoteCwd,
        [string]$CondaEnv,
        [switch]$NoConda,
        [switch]$AllowDestructive
    )

    Assert-AutoDLAgentName -Name "SessionName" -Value $SessionName
    Assert-AutoDLAgentCommandAllowed -Config $Config -Command $Command -AllowDestructive:$AllowDestructive
    Assert-CommandExists -Name "scp"

    $seq = Get-AutoDLAgentNextSequence -Config $Config -RunId $RunId
    $seqText = $seq.ToString("0000")
    $localRunDir = Resolve-AutoDLAgentRunDir -Config $Config -RunId $RunId
    $remoteRunDir = Resolve-AutoDLAgentRemoteRunDir -Config $Config -RunId $RunId
    $remoteLaunchersDir = Join-AutoDLRemotePath $remoteRunDir "launchers"
    $remoteLogsDir = Join-AutoDLRemotePath $remoteRunDir "logs"
    $remoteLauncherPath = Join-AutoDLRemotePath $remoteLaunchersDir "$seqText-$SessionName.sh"
    $remoteLogFile = Join-AutoDLRemotePath $remoteLogsDir "$seqText-$SessionName.log"
    $localLauncherPath = Join-Path (Join-Path $localRunDir "launchers") "$seqText-$SessionName.sh"
    $cwdResolved = Resolve-AutoDLAgentRemoteCwd -Config $Config -RepoName $RepoName -Cwd $Cwd -RemoteCwd $RemoteCwd
    $envName = if ([string]::IsNullOrWhiteSpace($CondaEnv)) { $Config.AutoDLAgentDefaultCondaEnv } else { $CondaEnv }
    $useConda = if ($NoConda) { "0" } else { "1" }
    $startedAt = Get-Date
    $prelude = if ($Config.PSObject.Properties.Name -contains "AutoDLAgentRemotePrelude") { [string]$Config.AutoDLAgentRemotePrelude } else { "" }

    $launcherContent = @"
#!/usr/bin/env bash
set -euo pipefail
mkdir -p $(ConvertTo-BashSingleQuoted $remoteLogsDir)
cd $(ConvertTo-BashSingleQuoted $cwdResolved)
$prelude
if [ "$useConda" = "1" ] && [ -f $(ConvertTo-BashSingleQuoted $Config.AutoDLAgentCondaInit) ]; then
  source $(ConvertTo-BashSingleQuoted $Config.AutoDLAgentCondaInit)
  conda activate $(ConvertTo-BashSingleQuoted $envName)
fi
{
printf 'run_id=%s\n' $(ConvertTo-BashSingleQuoted $RunId)
printf 'seq=%s\n' $(ConvertTo-BashSingleQuoted $seqText)
printf 'session=%s\n' $(ConvertTo-BashSingleQuoted $SessionName)
printf 'cwd=%s\n' `$(pwd)
printf 'conda_env=%s\n' $(ConvertTo-BashSingleQuoted $(if ($NoConda) { "none" } else { $envName }))
printf 'command=%s\n' $(ConvertTo-BashSingleQuoted $Command)
printf '%s\n' '--- command output ---'
$Command
status=`$?
printf '%s\n' '--- command exit ---'
printf 'exit_code=%s\n' "`$status"
exit `$status
} 2>&1 | tee $(ConvertTo-BashSingleQuoted $remoteLogFile)
"@

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $localLauncherPath) | Out-Null
    [System.IO.File]::WriteAllText($localLauncherPath, (ConvertTo-UnixLineEndings $launcherContent), [System.Text.UTF8Encoding]::new($false))

    $remotePrep = "mkdir -p $(ConvertTo-BashSingleQuoted $remoteLaunchersDir) $(ConvertTo-BashSingleQuoted $remoteLogsDir)"
    Invoke-AutoDLSSH -Config $Config -RemoteCommand (ConvertTo-UnixLineEndings $remotePrep) | Out-Null
    Invoke-AutoDLSCP -Config $Config -LocalPath $localLauncherPath -RemotePath $remoteLauncherPath | Out-Null

    $remoteStart = @"
set -e
chmod +x $(ConvertTo-BashSingleQuoted $remoteLauncherPath)
MUX_MODE=$(ConvertTo-BashSingleQuoted $Config.AutoDLAgentRemoteMultiplexer)
if [ "`$MUX_MODE" = "auto" ]; then
  if command -v tmux >/dev/null 2>&1; then
    MUX_MODE=tmux
  elif command -v screen >/dev/null 2>&1; then
    MUX_MODE=screen
  else
    echo "Neither tmux nor screen is installed" >&2
    exit 1
  fi
fi
if [ "`$MUX_MODE" = "tmux" ]; then
  if tmux has-session -t $(ConvertTo-BashSingleQuoted $SessionName) 2>/dev/null; then
    tmux kill-session -t $(ConvertTo-BashSingleQuoted $SessionName)
  fi
  tmux new-session -d -s $(ConvertTo-BashSingleQuoted $SessionName) "bash $(ConvertTo-BashSingleQuoted $remoteLauncherPath)"
else
  screen -S $(ConvertTo-BashSingleQuoted $SessionName) -X quit >/dev/null 2>&1 || true
  screen -dmS $(ConvertTo-BashSingleQuoted $SessionName) bash $(ConvertTo-BashSingleQuoted $remoteLauncherPath)
fi
printf 'mux=%s\n' "`$MUX_MODE"
printf 'session=%s\n' $(ConvertTo-BashSingleQuoted $SessionName)
printf 'launcher=%s\n' $(ConvertTo-BashSingleQuoted $remoteLauncherPath)
printf 'log=%s\n' $(ConvertTo-BashSingleQuoted $remoteLogFile)
"@
    Invoke-AutoDLSSH -Config $Config -RemoteCommand (ConvertTo-UnixLineEndings $remoteStart) | Out-Null

    $record = [ordered]@{
        seq = $seq
        run_id = $RunId
        kind = "background"
        repo_name = $RepoName
        cwd = $cwdResolved
        conda_env = if ($NoConda) { $null } else { $envName }
        command = ConvertTo-AutoDLMaskedText -Text $Command -Config $Config
        started_at = $startedAt.ToString("o")
        session = $SessionName
        launcher = $remoteLauncherPath
        remote_log = $remoteLogFile
        local_launcher = $localLauncherPath
        replayable = $false
        destructive = (Test-AutoDLAgentDestructiveCommand -Command $Command)
    }
    Write-AutoDLAgentCommandRecord -Config $Config -RunId $RunId -Record $record

    return [pscustomobject]@{
        RunId = $RunId
        Seq = $seq
        SessionName = $SessionName
        LauncherPath = $remoteLauncherPath
        LogFile = $remoteLogFile
    }
}

function Get-AutoDLAgentJobStatus {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config,
        [string]$RunId,
        [string]$SessionName,
        [int]$Lines = 120
    )

    if (-not [string]::IsNullOrWhiteSpace($SessionName)) {
        Assert-AutoDLAgentName -Name "SessionName" -Value $SessionName
    }
    if (-not [string]::IsNullOrWhiteSpace($RunId)) {
        Assert-AutoDLAgentName -Name "RunId" -Value $RunId
    }

    $remoteLogGlob = if ([string]::IsNullOrWhiteSpace($RunId)) {
        Join-AutoDLRemotePath $Config.AutoDLAgentRemoteRunsDir "*/logs/*.log"
    } else {
        Join-AutoDLRemotePath (Resolve-AutoDLAgentRemoteRunDir -Config $Config -RunId $RunId) "logs/*.log"
    }

    $sessionBlock = if ([string]::IsNullOrWhiteSpace($SessionName)) {
        "echo 'no session requested'"
    } else {
        @"
if [ "`$MUX_MODE" = "tmux" ]; then
  tmux capture-pane -pt $(ConvertTo-BashSingleQuoted $SessionName) 2>/dev/null | tail -n $Lines || echo 'tmux session not found'
elif [ "`$MUX_MODE" = "screen" ]; then
  screen -S $(ConvertTo-BashSingleQuoted $SessionName) -X hardcopy -h /tmp/autodl-agent-screen-$(ConvertTo-BashSingleQuoted $SessionName).log 2>/dev/null
  tail -n $Lines /tmp/autodl-agent-screen-$(ConvertTo-BashSingleQuoted $SessionName).log 2>/dev/null || echo 'screen session not found'
else
  echo 'no tmux/screen found'
fi
"@
    }

    $remoteStatus = @"
set +e
echo '=== gpu ==='
nvidia-smi || true
echo
echo '=== workspace ==='
echo 'root: '$(ConvertTo-BashSingleQuoted $Config.AutoDLAgentRemoteRoot)
echo 'repos: '$(ConvertTo-BashSingleQuoted $Config.AutoDLAgentRemoteReposDir)
echo 'runs: '$(ConvertTo-BashSingleQuoted $Config.AutoDLAgentRemoteRunsDir)
for p in $(ConvertTo-BashSingleQuoted $Config.AutoDLAgentRemoteRoot) $(ConvertTo-BashSingleQuoted $Config.AutoDLAgentRemoteReposDir) $(ConvertTo-BashSingleQuoted $Config.AutoDLAgentRemoteRunsDir); do
  if [ -e "`$p" ]; then du -sh "`$p" 2>/dev/null || true; else echo "missing: `$p"; fi
done
echo
echo '=== multiplexer ==='
MUX_MODE=$(ConvertTo-BashSingleQuoted $Config.AutoDLAgentRemoteMultiplexer)
if [ "`$MUX_MODE" = "auto" ]; then
  if command -v tmux >/dev/null 2>&1; then
    MUX_MODE=tmux
  elif command -v screen >/dev/null 2>&1; then
    MUX_MODE=screen
  else
    MUX_MODE=none
  fi
fi
echo "mode=`$MUX_MODE"
if [ "`$MUX_MODE" = "tmux" ]; then
  tmux ls 2>/dev/null || true
elif [ "`$MUX_MODE" = "screen" ]; then
  screen -list 2>/dev/null || true
fi
echo
echo '=== session output ==='
$sessionBlock
echo
echo '=== latest agent log tail ==='
latest_log=`$(ls -1t $remoteLogGlob 2>/dev/null | head -n 1)
if [ -n "`$latest_log" ]; then
  echo "latest_log=`$latest_log"
  tail -n $Lines "`$latest_log"
else
  echo 'no log files found'
fi
"@

    $output = & ssh $Config.AutoDLAgentHostAlias (ConvertTo-UnixLineEndings $remoteStatus) 2>&1
    $exitCode = $LASTEXITCODE
    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = (ConvertTo-AutoDLMaskedText -Text (($output | Out-String).TrimEnd()) -Config $Config)
    }
}

function Clone-AutoDLAgentRepo {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config,
        [Parameter(Mandatory = $true)]
        [string]$RunId,
        [Parameter(Mandatory = $true)]
        [string]$RepoUrl,
        [Parameter(Mandatory = $true)]
        [string]$RepoName,
        [string]$Ref,
        [switch]$AllowDestructive
    )

    Assert-AutoDLAgentName -Name "RepoName" -Value $RepoName
    $repoDir = Resolve-AutoDLAgentRepoDir -Config $Config -RepoName $RepoName
    $refBlock = ""
    if (-not [string]::IsNullOrWhiteSpace($Ref)) {
        $refBlock = @"
git fetch --all --tags
git checkout $(ConvertTo-BashSingleQuoted $Ref)
git submodule update --init --recursive
"@
    }
    $cloneCommand = @"
set -e
mkdir -p $(ConvertTo-BashSingleQuoted $Config.AutoDLAgentRemoteReposDir)
if [ -d $(ConvertTo-BashSingleQuoted (Join-AutoDLRemotePath $repoDir ".git")) ]; then
  cd $(ConvertTo-BashSingleQuoted $repoDir)
  git remote -v
else
  git -c http.version=HTTP/1.1 clone --recurse-submodules $(ConvertTo-BashSingleQuoted $RepoUrl) $(ConvertTo-BashSingleQuoted $repoDir)
  cd $(ConvertTo-BashSingleQuoted $repoDir)
fi
$refBlock
git rev-parse HEAD
git submodule status || true
"@

    return Invoke-AutoDLAgentCommand -Config $Config -RunId $RunId -Command $cloneCommand -RemoteCwd $Config.AutoDLAgentRemoteReposDir -NoConda -AllowDestructive:$AllowDestructive
}
