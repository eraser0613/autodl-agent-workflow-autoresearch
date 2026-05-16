## 1. Control-Plane Data Foundations

- [x] 1.1 Add example target registry schema with at least one AutoDL-style target and documented fields.
- [x] 1.2 Add local policy/error-signature seed files for connection, CUDA OOM, checkpoint, dataset, and duplicate-command categories.
- [x] 1.3 Add derived output directories or placeholders for target status and skill candidates without committing private target secrets.

## 2. Run and Job State Summarization

- [x] 2.1 Implement a local summarizer that reads `result/agent-runs/*/run.json` and `commands.jsonl`.
- [x] 2.2 Derive per-job status, command hash, timing, log/stdout paths, replayability, and basic artifact candidates.
- [x] 2.3 Write idempotent `state.json`, `jobs.jsonl`, and `events.jsonl` summaries per run.
- [x] 2.4 Ensure missing or partial run records are represented as unknown rather than failing the whole summary.

## 3. Target Health and Lease Awareness

- [x] 3.1 Implement target registry loading from example/local config with secret-safe defaults.
- [x] 3.2 Add a status command or script that checks configured targets and classifies SSH outcomes.
- [x] 3.3 Persist last-known target status under `result/targets/<target-id>/status.json`.
- [x] 3.4 Add lease fields and stale-lease detection to the target status model.

## 4. Execution Governance

- [x] 4.1 Add duplicate command hash detection within a run.
- [x] 4.2 Add foreground long-training detection and warning logic.
- [x] 4.3 Add repeated error-signature retry/loop warnings.
- [x] 4.4 Classify connection failures separately from workload failures.
- [x] 4.5 Add stale background-job detection using available local and remote metadata.

## 5. Observability and Dashboard Integration

- [x] 5.1 Emit structured events for target checks, job starts/finishes, policy warnings, artifacts, and error classifications.
- [x] 5.2 Extend the local web dashboard to read and display target, run, job, and event summaries.
- [x] 5.3 Display offline/last-known target state without requiring live SSH.
- [x] 5.4 Add run comparison or replay links based on existing launcher/replay metadata.

## 6. Skill and Runbook Capture

- [x] 6.1 Implement error-signature matching against job stdout/log summaries.
- [x] 6.2 Create skill-candidate records when repeated signatures or unknown failures recur.
- [x] 6.3 Separate generic troubleshooting candidates from project-specific profile notes.
- [x] 6.4 Seed initial troubleshooting/runbook candidates from Scaffold-GS, LiteVGGT, MVP, and SSH connection failures.

## 7. Validation

- [x] 7.1 Run the summarizer against existing Scaffold-GS and LiteVGGT/MVP records.
- [x] 7.2 Verify generated summaries are deterministic across repeated runs.
- [x] 7.3 Verify the dashboard still starts and can render existing runs.
- [x] 7.4 Verify no private SSH config, passwords, tokens, or target secrets are committed.
