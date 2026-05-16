## ADDED Requirements

### Requirement: Structured event log
The system SHALL append structured JSONL events for significant harness activity, including target checks, job starts, job finishes, connection failures, artifacts found, error classifications, policy warnings, and skill-candidate detections.

#### Scenario: Job finishes
- **WHEN** a job completes with an exit code
- **THEN** the system records a job_finished event with run id, job id, status, exit code, and log paths

#### Scenario: Policy warning occurs
- **WHEN** a preflight or post-run policy emits a warning
- **THEN** the system records a policy_warning event with the warning category and related job or target

### Requirement: Replay-ready summaries
The system SHALL preserve enough command metadata for replay and comparison, including command text or launcher path, command hash, cwd, conda environment, target, run id, and destructive/replayable flags.

#### Scenario: Replayable command
- **WHEN** a command record is marked replayable
- **THEN** the summary includes the command hash and launcher or command text required for dry-run replay

#### Scenario: Non-replayable background command
- **WHEN** a background command is not replayable
- **THEN** the summary still lists the job and explains that replay must be reconstructed manually

### Requirement: Dashboard-readable state
The system SHALL expose target, run, job, artifact, and event summaries in local files that the web dashboard can read without direct SSH access.

#### Scenario: Dashboard loads while target is offline
- **WHEN** the dashboard reads local summary files for an offline target
- **THEN** it displays last known state and offline health instead of requiring live SSH
