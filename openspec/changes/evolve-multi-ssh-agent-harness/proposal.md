## Why

The current AutoDL harness has proven useful for single-repository remote experiments, but the next bottleneck is the control layer: multiple SSH targets, long-running jobs, repeated operational failures, and project knowledge are still coordinated manually. This change evolves the harness into a local agent control plane with explicit target/job state, run governance, observability, and reusable troubleshooting knowledge.

## What Changes

- Introduce a structured multi-SSH target registry for AutoDL/GPU servers, with health/status metadata and connection-failure classification.
- Introduce a first-class run/job state model that aggregates existing `run.json`, `commands.jsonl`, stdout logs, launchers, sessions, artifacts, and exit codes.
- Add governance checks to prevent unsafe or wasteful execution patterns, including duplicate expensive commands, long training in foreground mode, repeated identical failures, stale jobs, and connection-loss confusion.
- Add structured observability events and summaries so runs can be inspected, replayed, compared, and rendered in the local web dashboard.
- Add an error signature and skill-candidate path for recurring connection, deployment, CUDA, checkpoint, dataset, and code-modification failures.
- Prepare clear seams for later MCP exposure and project-evaluation agents without exposing raw SSH as the primary interface.
- No breaking change to existing `scripts/autodl/agent.ps1` entrypoints; new behavior should wrap or summarize the current harness records first.

## Capabilities

### New Capabilities
- `target-registry`: Register, inspect, and classify multiple SSH/AutoDL targets as managed resources.
- `run-job-state`: Model runs and jobs with durable status, command identity, artifacts, and failure state derived from harness records.
- `execution-governance`: Apply preflight/post-run guardrails, duplicate detection, retry limits, stale-job checks, and connection-failure handling.
- `observability-replay`: Emit structured events and summaries for run inspection, dashboard display, replay, and future optimization.
- `skill-knowledge-capture`: Convert recurring operational failures and repo-specific lessons into reusable skill/runbook candidates while keeping project-specific assumptions in profiles.

### Modified Capabilities

None. This repository has no existing OpenSpec capability specs yet.

## Impact

- Affected local code: `scripts/autodl/`, `web/`, `profiles/`, and new `config/`, `policies/`, `skills/`, or `result/targets/` support files as needed.
- Affected data model: existing `result/agent-runs/<run-id>/` records remain authoritative, with additional derived state files such as `jobs.jsonl`, `state.json`, and `events.jsonl`.
- Affected workflow: Claude Code remains the decision interface; the harness becomes the control plane for multi-target status, governed execution, and structured diagnosis.
- Future integrations: MCP tools should call harness APIs/policies rather than raw SSH; project-evaluation agents should consume structured run/job/artifact summaries.
