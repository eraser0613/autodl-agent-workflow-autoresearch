# SSH connection refused

## Applies when

Harness status or target checks contain `ssh: connect to host ... port ...: Connection refused`.

## Meaning

This is a target/connection-layer failure. It does not prove a remote training job failed; it means the local harness cannot currently reach the SSH endpoint.

## First checks

1. Inspect `result/targets/<target-id>/status.json` for the classified health state.
2. Verify the AutoDL instance is running and the SSH port has not changed.
3. Update the SSH alias in the user's SSH config if AutoDL issued a new endpoint.
4. Re-run a bounded target status probe before starting or retrying workloads.

## Do not

- Do not mark training as failed solely because a later status probe cannot connect.
- Do not start replacement jobs on another target until the current job state is understood.
