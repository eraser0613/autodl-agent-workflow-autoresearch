## ADDED Requirements

### Requirement: Error signature catalog
The system SHALL maintain a catalog of recurring operational error signatures with pattern, category, example, likely cause, suggested next action, and optional related skill or runbook.

#### Scenario: Recognized error signature
- **WHEN** a job log matches a cataloged signature
- **THEN** the system attaches the signature id and suggested next action to the job summary

#### Scenario: Unknown failure
- **WHEN** a failed job does not match a known signature
- **THEN** the system marks the failure unknown and preserves enough log context for later review

### Requirement: Skill candidate generation
The system SHALL identify repeated unknown or recurring known failures as candidates for a troubleshooting skill or runbook.

#### Scenario: Repeated failure pattern
- **WHEN** the same error signature appears across multiple jobs or runs
- **THEN** the system records a skill candidate with examples and proposed scope

#### Scenario: Project-specific lesson
- **WHEN** a lesson applies only to a single repository or dataset
- **THEN** the system recommends storing it in that project profile or runbook rather than a generic troubleshooting skill

### Requirement: Skill scope separation
The system SHALL distinguish generic troubleshooting skills, repo intake skills, deployment skills, and project-specific profiles.

#### Scenario: CUDA ABI mismatch lesson
- **WHEN** a failure concerns general PyTorch/CUDA/NVIDIA library compatibility
- **THEN** the system may classify it as a generic troubleshooting skill candidate

#### Scenario: Scaffold-GS checkpoint bug lesson
- **WHEN** a lesson concerns a specific Scaffold-GS checkout behavior
- **THEN** the system keeps the lesson in the Scaffold-GS profile or project runbook
