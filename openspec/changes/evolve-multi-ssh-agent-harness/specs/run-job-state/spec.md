## ADDED Requirements

### Requirement: Run state summary
The system SHALL derive a durable run state summary from existing harness records, including run id, repo name, target, remote workspace paths, local record paths, aggregate job counts, latest status, and timestamps.

#### Scenario: Summarize existing run
- **WHEN** a run directory contains `run.json` and `commands.jsonl`
- **THEN** the system produces a run summary without modifying the raw command records

#### Scenario: Missing command records
- **WHEN** a run directory has `run.json` but no `commands.jsonl`
- **THEN** the system marks job state as unknown or empty while preserving the run metadata

### Requirement: Job state records
The system SHALL model each foreground or background command as a job with sequence number, command hash, kind, cwd, conda environment, start time, finish time when available, exit code when available, remote log path, local stdout path, status, and replayability.

#### Scenario: Completed foreground command
- **WHEN** a command record has `finished_at` and `exit_code` zero
- **THEN** the job status is succeeded

#### Scenario: Failed foreground command
- **WHEN** a command record has `finished_at` and non-zero `exit_code`
- **THEN** the job status is failed and the error classifier can attach a failure category

#### Scenario: Background command without finish record
- **WHEN** a command record has kind background and no finish information
- **THEN** the job status is running or unknown until session/status probes provide more information

### Requirement: Artifact references
The system SHALL attach known local and remote artifact references to jobs and runs when paths are present in command output, profiles, or summary files.

#### Scenario: Output path found in stdout
- **WHEN** a job stdout contains an output path marker such as `OUT=`, `TRAIN_OUT=`, `SMOKE_OUT=`, or `SUMMARY_JSON`
- **THEN** the system records that path as a candidate artifact reference for the job

#### Scenario: Artifact cannot be verified
- **WHEN** an artifact path is remote and the target is offline
- **THEN** the system records it as unverified instead of discarding it
