param(
    [string]$SessionName,
    [string]$LogPath,
    [int]$PollIntervalSeconds = 20,
    [string]$OutputPath,
    [int]$StallThreshold = 3
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "common.ps1")

$cfg = Import-AutoDLConfig
if ([string]::IsNullOrWhiteSpace($SessionName)) {
    $SessionName = $cfg.AutoDLDefaultTmuxSession
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $OutputPath = Join-Path (Join-Path (Get-AutoDLRepoRoot) "result") "watch-$($SessionName)-$stamp.log"
}

$outputDir = Split-Path -Parent $OutputPath
if (-not [string]::IsNullOrWhiteSpace($outputDir)) {
    New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
}

$sessionQuoted = ConvertTo-BashSingleQuoted $SessionName
$logPathQuoted = if ([string]::IsNullOrWhiteSpace($LogPath)) { "''" } else { ConvertTo-BashSingleQuoted $LogPath }
$logDirQuoted = ConvertTo-BashSingleQuoted $cfg.AutoDLRemoteLogDir
$muxQuoted = ConvertTo-BashSingleQuoted ([string]$cfg.AutoDLRemoteMultiplexer)

$remoteCommand = @'
set +e
SESSION_NAME=__SESSION_QUOTED__
LOG_PATH=__LOG_PATH_QUOTED__
LOG_DIR=__LOG_DIR_QUOTED__
MUX_MODE=__MUX_QUOTED__
if [ "$MUX_MODE" = "auto" ]; then
  if command -v tmux >/dev/null 2>&1; then
    MUX_MODE=tmux
  elif command -v screen >/dev/null 2>&1; then
    MUX_MODE=screen
  else
    MUX_MODE=none
  fi
fi
if [ -z "$LOG_PATH" ]; then
  LOG_PATH=$(ls -1t "$LOG_DIR"/*.log 2>/dev/null | head -n 1)
fi
SESSION_EXISTS=0
if [ "$MUX_MODE" = "tmux" ]; then
  tmux has-session -t "$SESSION_NAME" 2>/dev/null && SESSION_EXISTS=1
elif [ "$MUX_MODE" = "screen" ]; then
  screen -list 2>/dev/null | grep -Fq ".$SESSION_NAME" && SESSION_EXISTS=1
fi
echo "__WATCH_BEGIN__"
echo "ts=$(date '+%F %T')"
echo "host=$(hostname)"
echo "mux=$MUX_MODE"
echo "session_exists=$SESSION_EXISTS"
echo "log_path=$LOG_PATH"
GPU_LINE=$(nvidia-smi --query-gpu=name,utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits 2>/dev/null | head -n 1)
if [ -n "$GPU_LINE" ]; then
  IFS=',' read -r GPU_NAME GPU_UTIL GPU_MEM_USED GPU_MEM_TOTAL <<EOF
$GPU_LINE
EOF
  GPU_NAME=$(echo "$GPU_NAME" | sed 's/^ *//; s/ *$//')
  GPU_UTIL=$(echo "$GPU_UTIL" | sed 's/^ *//; s/ *$//')
  GPU_MEM_USED=$(echo "$GPU_MEM_USED" | sed 's/^ *//; s/ *$//')
  GPU_MEM_TOTAL=$(echo "$GPU_MEM_TOTAL" | sed 's/^ *//; s/ *$//')
  echo "gpu_name=$GPU_NAME"
  echo "gpu_util=$GPU_UTIL"
  echo "gpu_mem_used=$GPU_MEM_USED"
  echo "gpu_mem_total=$GPU_MEM_TOTAL"
fi
if [ -n "$LOG_PATH" ] && [ -f "$LOG_PATH" ]; then
  echo "__LOG_TAIL__"
  tail -n 120 "$LOG_PATH"
fi
echo "__WATCH_END__"
'@

$remoteCommand = $remoteCommand.Replace("__SESSION_QUOTED__", $sessionQuoted)
$remoteCommand = $remoteCommand.Replace("__LOG_PATH_QUOTED__", $logPathQuoted)
$remoteCommand = $remoteCommand.Replace("__LOG_DIR_QUOTED__", $logDirQuoted)
$remoteCommand = $remoteCommand.Replace("__MUX_QUOTED__", $muxQuoted)

$seenEpochLines = [System.Collections.Generic.HashSet[string]]::new()
$seenMetaLines = [System.Collections.Generic.HashSet[string]]::new()
$stallCount = 0
$finished = $false

function Get-MetaValue {
    param(
        [hashtable]$Map,
        [string]$Key,
        [string]$Default = ""
    )

    if ($Map.ContainsKey($Key) -and -not [string]::IsNullOrWhiteSpace([string]$Map[$Key])) {
        return [string]$Map[$Key]
    }

    return $Default
}

function Write-WatchLine {
    param([string]$Line)
    Add-Content -Path $OutputPath -Value $Line
    Write-Host $Line
}

Write-WatchLine ("[{0}] watch-start session={1} output={2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $SessionName, $OutputPath)

while (-not $finished) {
    $raw = Invoke-AutoDLSSH -Config $cfg -RemoteCommand $remoteCommand
    $lines = @($raw -split "`r?`n")

    $meta = @{}
    $logTail = New-Object System.Collections.Generic.List[string]
    $inLogTail = $false

    foreach ($line in $lines) {
        if ($line -eq "__LOG_TAIL__") {
            $inLogTail = $true
            continue
        }
        if ($line -eq "__WATCH_BEGIN__" -or $line -eq "__WATCH_END__") {
            continue
        }
        if ($inLogTail) {
            $logTail.Add($line)
            continue
        }
        if ($line -match "^(?<k>[^=]+)=(?<v>.*)$") {
            $meta[$Matches.k] = $Matches.v
        }
    }

    $summary = "[{0}] host={1} gpu={2} util={3}% mem={4}/{5}MiB session={6} log={7}" -f `
        (Get-MetaValue -Map $meta -Key "ts" -Default (Get-Date -Format "yyyy-MM-dd HH:mm:ss")), `
        (Get-MetaValue -Map $meta -Key "host" -Default "?"), `
        (Get-MetaValue -Map $meta -Key "gpu_name" -Default "?"), `
        (Get-MetaValue -Map $meta -Key "gpu_util" -Default "?"), `
        (Get-MetaValue -Map $meta -Key "gpu_mem_used" -Default "?"), `
        (Get-MetaValue -Map $meta -Key "gpu_mem_total" -Default "?"), `
        (Get-MetaValue -Map $meta -Key "session_exists" -Default "?"), `
        (Get-MetaValue -Map $meta -Key "log_path" -Default "")

    if ($seenMetaLines.Add($summary)) {
        Write-WatchLine $summary
    } else {
        Write-Host $summary
    }

    $newEpoch = $false
    foreach ($line in $logTail) {
        $trimmed = $line.TrimEnd()
        if ($trimmed -match '^Epoch\s+' -or $trimmed -match '^--- ' -or $trimmed -match 'Traceback' -or $trimmed -match 'RuntimeError' -or $trimmed -match 'Killed') {
            if ($seenEpochLines.Add($trimmed)) {
                Write-WatchLine ("  {0}" -f $trimmed)
            }
            if ($trimmed -match '^Epoch\s+') {
                $newEpoch = $true
            }
        }
    }

    if ($newEpoch) {
        $stallCount = 0
    } else {
        $stallCount += 1
    }

    $joinedTail = ($logTail -join "`n")
    if ($joinedTail -match 'Epoch\s+9/' -or $joinedTail -match 'Epoch\s+10/' -or $joinedTail -match 'Epoch\s+19/' -or $joinedTail -match 'Epoch\s+20/') {
        Write-WatchLine ("[{0}] watch-stop reason=final_epoch_detected" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"))
        $finished = $true
        break
    }

    if ((Get-MetaValue -Map $meta -Key "session_exists" -Default "1") -eq "0" -and $stallCount -ge $StallThreshold) {
        Write-WatchLine ("[{0}] watch-stop reason=session_missing stall={1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $stallCount)
        $finished = $true
        break
    }

    Start-Sleep -Seconds $PollIntervalSeconds
}
