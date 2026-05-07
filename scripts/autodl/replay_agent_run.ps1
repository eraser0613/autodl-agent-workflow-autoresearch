param(
    [Parameter(Mandatory = $true)]
    [string]$RunId,
    [switch]$DryRun,
    [switch]$OnlySuccessful = $true,
    [switch]$IncludeBackgroundJobs
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "common.ps1")

$cfg = Import-AutoDLAgentConfig
$runDir = Resolve-AutoDLAgentRunDir -Config $cfg -RunId $RunId
$commandsPath = Join-Path $runDir "commands.jsonl"

if (-not (Test-Path $commandsPath)) {
    throw "Missing commands log: $commandsPath"
}

Write-Host "Replay plan for run: $RunId"
Write-Host "commands: $commandsPath"
Write-Host ""

$records = Get-Content -Path $commandsPath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_ | ConvertFrom-Json }

foreach ($record in $records) {
    if ($record.kind -eq "background" -and -not $IncludeBackgroundJobs) {
        Write-Host "# skip background seq=$($record.seq) session=$($record.session)"
        continue
    }
    if ($OnlySuccessful -and ($record.PSObject.Properties.Name -contains "exit_code") -and ([int]$record.exit_code -ne 0)) {
        Write-Host "# skip failed seq=$($record.seq) exit_code=$($record.exit_code)"
        continue
    }
    if (($record.PSObject.Properties.Name -contains "replayable") -and -not [bool]$record.replayable) {
        Write-Host "# skip non-replayable seq=$($record.seq) kind=$($record.kind)"
        continue
    }

    $repoPart = if ([string]::IsNullOrWhiteSpace([string]$record.repo_name)) { "" } else { " -RepoName `"$($record.repo_name)`"" }
    $cwdPart = if ([string]::IsNullOrWhiteSpace([string]$record.cwd)) { "" } else { " -RemoteCwd `"$($record.cwd)`"" }
    $condaPart = if ([string]::IsNullOrWhiteSpace([string]$record.conda_env)) { " -NoConda" } else { " -CondaEnv `"$($record.conda_env)`"" }
    $command = [string]$record.command
    $escapedCommand = $command.Replace('`', '``').Replace('"', '`"')
    Write-Host "powershell -ExecutionPolicy Bypass -File .\scripts\autodl\agent.ps1 -Action run -RunId `"$RunId`"$repoPart$cwdPart$condaPart -Command `"$escapedCommand`""
}

if (-not $DryRun) {
    Write-Host ""
    Write-Host "Automatic replay execution is intentionally not implemented in the MVP. Review the plan and run selected commands manually."
}
