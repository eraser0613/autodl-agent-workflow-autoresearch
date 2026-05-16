## ADDED Requirements

### Requirement: Preflight execution checks
The system SHALL evaluate preflight checks before risky or expensive execution, including target health, target lease, foreground long-training detection, duplicate command hash, output-path reuse, and obvious secret patterns.

#### Scenario: Long training requested in foreground
- **WHEN** a command appears to start long training in foreground mode
- **THEN** the system warns that detachable execution is required or recommended before continuing

#### Scenario: Duplicate expensive command
- **WHEN** a command hash matches a previous expensive job in the same run
- **THEN** the system warns about duplicate execution and references the earlier job

### Requirement: Post-run classification
The system SHALL classify job completion into success, workload failure, connection failure, interrupted, stale, or unknown based on exit code, SSH/tool errors, command output, and session status.

#### Scenario: Connection refused after status check
- **WHEN** a status probe fails with SSH connection refused
- **THEN** the system records a target connection event and does not automatically mark a remote training job as failed

#### Scenario: CUDA OOM appears in logs
- **WHEN** a job log contains a recognized CUDA out-of-memory signature
- **THEN** the system classifies the job as workload failure with category cuda-oom

### Requirement: Retry and loop control
The system SHALL prevent blind repeated execution of the same failing command or failure signature beyond a configured limit.

#### Scenario: Same error repeats
- **WHEN** the same command hash or error signature has failed repeatedly in a run
- **THEN** the system blocks or warns against another automatic retry and recommends changing strategy

#### Scenario: Transient network failure
- **WHEN** a failure is classified as transient network failure
- **THEN** the system may allow a bounded retry according to policy and records the retry count

### Requirement: Stale job detection
The system SHALL detect candidate stale jobs using session liveness, log modification time, elapsed runtime, and GPU activity when available.

#### Scenario: No log progress
- **WHEN** a background job has no log update past the configured threshold
- **THEN** the system marks it stale-candidate and prompts for inspection before launching replacements
