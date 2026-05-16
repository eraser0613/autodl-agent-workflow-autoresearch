## Context

The repository currently provides PowerShell entrypoints under `scripts/autodl/`, project profiles under `profiles/`, a local web dashboard under `web/`, and durable run records under `result/agent-runs/<run-id>/`. This is enough for single-target remote control, but multi-SSH work requires a stronger control plane: the harness must know what targets exist, what jobs are running, what failed, whether a failure is connection-related or workload-related, and what repeated lessons should become reusable skills.

The user wants Claude Code to remain the command/decision interface while the local harness becomes the runtime/governance layer. The design therefore favors local files, deterministic summaries, and explicit policies over a hidden autonomous scheduler.

## Goals / Non-Goals

**Goals:**

- Represent SSH/AutoDL machines as managed targets with health, GPU, disk, and lease state.
- Represent harness activity as runs and jobs with durable status derived from existing records.
- Add low-risk governance first: detect connection failures, duplicate commands, stale jobs, foreground long training, repeated identical failures, and missing artifact summaries.
- Produce structured events/summaries that the web dashboard and future MCP tools can consume.
- Establish a path from repeated error signatures to skill/runbook candidates.
- Preserve existing `agent.ps1` usage and run records.

**Non-Goals:**

- Do not replace Claude Code with a fully autonomous scheduler in this change.
- Do not expose arbitrary SSH execution through MCP in this change.
- Do not Dockerize all remote execution yet; many CUDA projects are ABI-sensitive.
- Do not move repo-specific assumptions into the generic harness.
- Do not delete or migrate historical run records destructively.

## Decisions

### Decision 1: Add a local control-plane data model before changing execution

Use local JSON/JSONL files to summarize existing harness records:

```text
config/targets.example.json
web/config/targets.local.json
result/targets/<target-id>/status.json
result/agent-runs/<run-id>/state.json
result/agent-runs/<run-id>/jobs.jsonl
result/agent-runs/<run-id>/events.jsonl
```

Rationale: existing runs already capture the source of truth. A derived state layer is safer than rewriting `agent.ps1` first.

Alternative considered: build a database-backed server immediately. Rejected for now because local files match the current repository style and are easier for Claude Code to inspect/edit.

### Decision 2: Treat targets, runs, jobs, artifacts, and errors as separate concepts

- Target: SSH/GPU resource.
- Run: a project-level intake/training/evaluation session.
- Job: one concrete command/session within a run.
- Artifact: remote or local output produced by a job.
- Error signature: classified failure pattern that can trigger a skill candidate.

Rationale: this separation enables multiple runs per target, multiple jobs per run, and project-level summaries without conflating SSH health with training success.

### Decision 3: Implement guardrails as policy checks around the current harness

Start with wrappers/summarizers and preflight checks rather than invasive changes:

- Foreground long-training warnings.
- Duplicate command hash detection.
- Same error signature retry cap.
- Connection-failure classification.
- Stale-session detection.
- Output-path overwrite warning.

Rationale: policies can evolve independently and later become hooks/middleware.

### Decision 4: Keep the dashboard local-first and mostly read-only

The web dashboard should initially list targets, runs, jobs, events, errors, and artifacts. Mutating actions should remain explicit and routed through existing harness commands or generated prompts.

Rationale: this gives visibility without turning the browser into an unsafe remote shell.

### Decision 5: Capture skills as candidates before formalizing automation

Repeated errors should create structured candidates under `skills/` or `result/skill-candidates/`, but promotion to a real skill/runbook should remain reviewed.

Rationale: avoids prematurely encoding one-off fixes while preserving hard-won operational knowledge.

### Decision 6: Prepare MCP seams but defer MCP implementation

Define future tool boundaries around safe harness operations such as `list_targets`, `check_target`, `list_runs`, `get_job_log`, `classify_error`, and `list_artifacts`. Do not expose raw SSH.

Rationale: MCP should be an interface to the governed harness, not a bypass around it.

## Risks / Trade-offs

- [Risk] Derived state can drift from raw logs. → Mitigation: keep raw `commands.jsonl` authoritative and regenerate summaries idempotently.
- [Risk] Guardrails block legitimate experiments. → Mitigation: warn first where possible, require explicit confirmation for risky cases, and record override reasons.
- [Risk] Multi-target orchestration can start conflicting jobs. → Mitigation: introduce leases before autonomous scheduling.
- [Risk] Skill candidates become noisy. → Mitigation: only generate candidates after repeated signatures or explicit user confirmation.
- [Risk] Dashboard actions could bypass safety. → Mitigation: keep initial dashboard read-only or prompt-generating.

## Migration Plan

1. Add example target registry and derived status schema without changing existing runs.
2. Add a local summarizer that reads `result/agent-runs/*/run.json` and `commands.jsonl` into run/job state.
3. Add connection/error classification rules and events.
4. Surface summaries in the web dashboard.
5. Add optional preflight wrappers for future commands.
6. Later, expose stable operations through MCP.

Rollback is simple for early phases: remove derived files and continue using `scripts/autodl/agent.ps1` directly.

## Open Questions

- Should target leases be stored only locally or also mirrored remotely in the AutoDL workspace?
- Should policy overrides require a textual reason from Claude/user?
- Should formal skills live in `.claude/skills/`, top-level `skills/`, or both?
- Should the web dashboard eventually trigger commands directly or only generate Claude/harness prompts?
