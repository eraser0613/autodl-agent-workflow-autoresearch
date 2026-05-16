## ADDED Requirements

### Requirement: Managed SSH target registry
The system SHALL maintain a local registry of SSH/AutoDL targets with stable target identifiers, SSH aliases, display names, tags, and optional runtime metadata such as GPU type, CUDA information, disk capacity, and workspace paths.

#### Scenario: List configured targets
- **WHEN** the user asks to inspect available targets
- **THEN** the system returns each registered target with its identifier, alias, tags, and last known health state

#### Scenario: Target metadata is absent
- **WHEN** a target has not yet been probed for GPU or disk metadata
- **THEN** the system still lists the target and marks missing runtime fields as unknown rather than failing

### Requirement: Target health classification
The system SHALL classify target health separately from workload success, including at least online, offline, connection-refused, auth-failed, timeout, degraded, and unknown states.

#### Scenario: SSH port refuses connection
- **WHEN** a target health check receives a connection refused error
- **THEN** the system marks the target as connection-refused and does not classify currently known jobs as failed solely because of that connection failure

#### Scenario: SSH succeeds
- **WHEN** a target health check successfully runs a minimal remote probe
- **THEN** the system records last_seen_at and marks the target online with the observed host and GPU metadata when available

### Requirement: Target lease awareness
The system SHALL support a local lease record that associates a target with a run or job to reduce accidental concurrent use of the same GPU resource.

#### Scenario: Target already leased
- **WHEN** a new long-running job is planned for a leased target
- **THEN** the system warns that the target is already leased and identifies the owning run or job

#### Scenario: Lease expires
- **WHEN** a lease has passed its expiry and no matching live job is detected
- **THEN** the system marks the lease stale instead of silently treating the target as free
