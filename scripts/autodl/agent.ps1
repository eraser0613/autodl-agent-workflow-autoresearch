param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("init", "clone", "run", "start", "status")]
    [string]$Action,

    [string]$ConfigPath,
    [string]$RunId,
    [string]$RepoUrl,
    [string]$RepoName,
    [string]$Ref,
    [string]$Cwd = ".",
    [string]$RemoteCwd,
    [string]$Command,
    [string]$CommandBase64,
    [string]$CondaEnv,
    [string]$SessionName,
    [int]$Lines = 120,
    [switch]$NoConda,
    [switch]$AllowDestructive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "common.ps1")

if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
    $script:AutoDLAgentConfigPathOverride = $ConfigPath
}

$cfg = Import-AutoDLAgentConfig

if (-not [string]::IsNullOrWhiteSpace($CommandBase64)) {
    $Command = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($CommandBase64))
}

switch ($Action) {
    "init" {
        $run = New-AutoDLAgentRun -Config $cfg -RunId $RunId -RepoName $RepoName -RepoUrl $RepoUrl -Ref $Ref
        Write-Host "agent workspace initialized"
        Write-Host "run_id: $($run.RunId)"
        Write-Host "local_run_dir: $($run.LocalRunDir)"
        Write-Host "remote_run_dir: $($run.RemoteRunDir)"
    }

    "clone" {
        if ([string]::IsNullOrWhiteSpace($RepoUrl)) {
            throw "-RepoUrl is required for -Action clone."
        }
        if ([string]::IsNullOrWhiteSpace($RepoName)) {
            throw "-RepoName is required for -Action clone."
        }
        $resolvedRunId = Resolve-AutoDLAgentRunId -Config $cfg -RunId $RunId -RepoName $RepoName -RepoUrl $RepoUrl -Ref $Ref
        $result = Clone-AutoDLAgentRepo -Config $cfg -RunId $resolvedRunId -RepoUrl $RepoUrl -RepoName $RepoName -Ref $Ref -AllowDestructive:$AllowDestructive
        Write-Host $result.Output
        Write-Host ""
        Write-Host "run_id: $resolvedRunId"
        Write-Host "seq: $($result.Seq)"
        Write-Host "exit_code: $($result.ExitCode)"
        Write-Host "remote_log: $($result.RemoteLog)"
        if ($result.ExitCode -ne 0) {
            exit $result.ExitCode
        }
    }

    "run" {
        if ([string]::IsNullOrWhiteSpace($Command)) {
            throw "-Command is required for -Action run."
        }
        $resolvedRunId = Resolve-AutoDLAgentRunId -Config $cfg -RunId $RunId -RepoName $RepoName -RepoUrl $RepoUrl -Ref $Ref
        $result = Invoke-AutoDLAgentCommand `
            -Config $cfg `
            -RunId $resolvedRunId `
            -Command $Command `
            -RepoName $RepoName `
            -Cwd $Cwd `
            -RemoteCwd $RemoteCwd `
            -CondaEnv $CondaEnv `
            -NoConda:$NoConda `
            -AllowDestructive:$AllowDestructive `
            -TailLines $Lines
        Write-Host $result.Output
        Write-Host ""
        Write-Host "run_id: $resolvedRunId"
        Write-Host "seq: $($result.Seq)"
        Write-Host "exit_code: $($result.ExitCode)"
        Write-Host "remote_log: $($result.RemoteLog)"
        Write-Host "local_stdout: $($result.LocalStdout)"
        if ($result.ExitCode -ne 0) {
            exit $result.ExitCode
        }
    }

    "start" {
        if ([string]::IsNullOrWhiteSpace($Command)) {
            throw "-Command is required for -Action start."
        }
        if ([string]::IsNullOrWhiteSpace($SessionName)) {
            throw "-SessionName is required for -Action start."
        }
        $resolvedRunId = Resolve-AutoDLAgentRunId -Config $cfg -RunId $RunId -RepoName $RepoName -RepoUrl $RepoUrl -Ref $Ref
        $result = Start-AutoDLAgentJob `
            -Config $cfg `
            -RunId $resolvedRunId `
            -Command $Command `
            -SessionName $SessionName `
            -RepoName $RepoName `
            -Cwd $Cwd `
            -RemoteCwd $RemoteCwd `
            -CondaEnv $CondaEnv `
            -NoConda:$NoConda `
            -AllowDestructive:$AllowDestructive
        Write-Host "background job started"
        Write-Host "run_id: $resolvedRunId"
        Write-Host "seq: $($result.Seq)"
        Write-Host "session: $($result.SessionName)"
        Write-Host "launcher: $($result.LauncherPath)"
        Write-Host "log: $($result.LogFile)"
    }

    "status" {
        $resolvedRunId = if ([string]::IsNullOrWhiteSpace($RunId)) { Get-AutoDLAgentCurrentRun -Config $cfg } else { $RunId }
        $result = Get-AutoDLAgentJobStatus -Config $cfg -RunId $resolvedRunId -SessionName $SessionName -Lines $Lines
        Write-Host $result.Output
        if ($result.ExitCode -ne 0) {
            exit $result.ExitCode
        }
    }
}
