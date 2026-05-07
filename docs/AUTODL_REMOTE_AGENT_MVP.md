# AutoDL Remote Agent MVP

This workflow is for local Claude Code controlling an AutoDL GPU server through a small harness.

The harness does not assume a fixed 3DGS training command. For each unfamiliar repository, start from a remote `git clone`, explore install and run commands on the server, capture evidence, and only then turn the successful path into a project-specific profile.

## Files

- `scripts/autodl/autodl.agent.config.ps1.example` — copy to the private local config.
- `scripts/autodl/agent.ps1` — main harness entrypoint.
- `scripts/autodl/replay_agent_run.ps1` — prints a replay plan from a previous run log.
- `profiles/project.profile.ps1.example` — template for learned per-project runbooks.
- `result/agent-runs/<run-id>/` — local command logs, stdout tails, launchers, and manifests.

## First-time setup

Create SSH access first. Prefer an SSH alias so secrets stay out of project files:

```sshconfig
Host autodl-main
  HostName connect.example.seetacloud.com
  User root
  Port 40162
  IdentityFile C:\Users\15981\.ssh\id_rsa
  IdentitiesOnly yes
```

Verify:

```powershell
ssh -o BatchMode=yes autodl-main "echo ssh-ok"
```

Copy the harness config:

```powershell
Copy-Item .\scripts\autodl\autodl.agent.config.ps1.example .\scripts\autodl\autodl.agent.config.ps1
```

Edit only local/private values such as `$AutoDLAgentHostAlias` and workspace paths. Do not store tokens or private keys in this file.

## Minimal exploration loop

Initialize a run and remote workspace:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\autodl\agent.ps1 -Action init -RepoName gaussian-splatting
```

Clone a repository on the remote server:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\autodl\agent.ps1 `
  -Action clone `
  -RepoUrl https://github.com/graphdeco-inria/gaussian-splatting.git `
  -RepoName gaussian-splatting `
  -Ref main
```

Run one bounded probe at a time:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\autodl\agent.ps1 `
  -Action run `
  -RepoName gaussian-splatting `
  -NoConda `
  -Command "pwd && ls -la && find . -maxdepth 2 -type f | sort | head -80"
```

Check runtime facts:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\autodl\agent.ps1 `
  -Action run `
  -RepoName gaussian-splatting `
  -Command "python -V && which python && nvidia-smi"
```

Start a long job in tmux/screen:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\autodl\agent.ps1 `
  -Action start `
  -RepoName gaussian-splatting `
  -CondaEnv gaussian_splatting `
  -SessionName gs-train `
  -Command "python train.py -s /root/autodl-tmp/data/garden -m outputs/garden --iterations 3000"
```

Inspect status and latest logs:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\autodl\agent.ps1 -Action status -SessionName gs-train
```

## Logs and replay

Each command appends a JSON record to:

```text
result/agent-runs/<run-id>/commands.jsonl
```

Each foreground command also writes a masked stdout tail to:

```text
result/agent-runs/<run-id>/stdout/<seq>.txt
```

To print a replay plan:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\autodl\replay_agent_run.ps1 -RunId <run-id> -DryRun
```

MVP replay intentionally prints commands instead of auto-executing them. Review and run selected commands manually.

## Exploration protocol for Claude Code

Use this protocol when controlling an unfamiliar 3DGS-style project:

1. Do not assume the project is standard 3DGS.
2. Clone the target repo on the AutoDL server.
3. Run small probes first: tree, README, requirements, environment files, entrypoint help.
4. Try environment setup and imports before any expensive training.
5. For failures, read the log and explain the root cause before trying the next command.
6. Start long compile/train jobs only through `-Action start` so they are logged and detachable.
7. When training or evaluation succeeds, summarize the known-good server image, dependencies, data paths, checkpoints, commands, and output evidence.
8. Move project-specific knowledge into `profiles/<project>.local.ps1`; do not add special cases to the generic harness.

## Safety notes

- Real configs, secrets, keys, and run logs are ignored by git.
- Avoid putting tokens in commands. Prefer preconfigured remote credentials.
- The harness blocks obvious destructive/system-modifying commands unless `-AllowDestructive` is passed.
- Keep remote work under `$AutoDLAgentRemoteRoot` unless you deliberately change the safety policy.

## Continuation notes for Claude Code

A project-level `CLAUDE.md` now records how this harness should be used in future sessions. When resuming this project, read that file first, then check the current SSH alias and harness status.

Current durable harness behavior:

- AutoDL access uses SSH alias `autodl-main`.
- Remote commands should go through `scripts/autodl/agent.ps1`, not ad-hoc SSH.
- AutoDL academic-resource access should source `/etc/network_turbo` when present; the current private config sets this through `$AutoDLAgentRemotePrelude`.
- Foreground `run` commands are executed through uploaded launcher scripts so complex quoting, shell variables, heredocs, and pipes survive reliably.
- Use `-CommandBase64` for complex probes, preferably generated from `tmp/<probe>.sh`.
- Distinguish `nvidia-smi` driver-supported CUDA from actual toolkit CUDA; verify toolkit with `/usr/local/cuda/bin/nvcc --version` and `readlink -f /usr/local/cuda`.

Current Scaffold-GS run:

```text
run_id: 20260504-184448-Scaffold-GS
remote repo: /root/autodl-tmp/agent-workspace/repos/Scaffold-GS
commit: 59c833b56bbbf510f3f64d40f81721995caced66
actual CUDA toolkit: /usr/local/cuda-12.4, nvcc V12.4.131
```

Next recommended Scaffold-GS milestone: create/adapt the `scaffold_gs` conda environment, verify imports and CUDA extensions, place a minimal COLMAP scene, then run a 1-iteration smoke command before any full training.
