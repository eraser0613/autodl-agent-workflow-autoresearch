# CLAUDE.md

This project is a Claude Code-first remote-control harness for AutoDL GPU servers.

## Core goal

Build and use a local harness that lets Claude Code control AutoDL safely and reproducibly. The harness is more important than any single 3DGS script.

For each unfamiliar 3DGS-style repository:

1. Clone the repository on the AutoDL server.
2. Explore the repository remotely: README, environment files, submodules, entrypoints, data assumptions, checkpoints, and smoke commands.
3. Run small reversible probes before expensive setup or training.
4. Capture every command, log, exit code, cwd, conda env, and remote artifact path.
5. After a path succeeds, internalize that repo-specific knowledge into `profiles/<project>.local.ps1` or a project-specific runbook.
6. Do not put repo-specific training assumptions into the generic harness.

## Main entrypoints

Use these from the project root:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\autodl\agent.ps1 -Action status
powershell -ExecutionPolicy Bypass -File .\scripts\autodl\agent.ps1 -Action init -RepoName <repo-name>
powershell -ExecutionPolicy Bypass -File .\scripts\autodl\agent.ps1 -Action clone -RepoUrl <git-url> -RepoName <repo-name>
powershell -ExecutionPolicy Bypass -File .\scripts\autodl\agent.ps1 -Action run -RepoName <repo-name> -NoConda -Command "pwd && ls -la"
powershell -ExecutionPolicy Bypass -File .\scripts\autodl\agent.ps1 -Action start -RepoName <repo-name> -SessionName <name> -Command "<long command>"
powershell -ExecutionPolicy Bypass -File .\scripts\autodl\replay_agent_run.ps1 -RunId <run-id> -DryRun
```

Use `-CommandBase64` for complex probes containing quotes, shell variables, heredocs, pipes, or regexes. Prefer file-based base64 generation from `tmp/<probe>.sh` so command text is preserved exactly.

## AutoDL connection

The current private config uses SSH alias:

```text
autodl-main
```

Private config:

```text
scripts/autodl/autodl.agent.config.ps1
```

This file is intentionally ignored by git. It should contain endpoint-specific values only, not passwords or tokens.

If the AutoDL instance changes, update `C:\Users\15981\.ssh\config` and verify:

```powershell
ssh -o BatchMode=yes autodl-main "echo ssh-ok && hostname && nvidia-smi"
```

## AutoDL network acceleration

AutoDL GitHub/HuggingFace/academic access should source the network turbo script when present:

```bash
source /etc/network_turbo
```

The current harness config internalizes this as:

```powershell
$AutoDLAgentRemotePrelude = "if [ -f /etc/network_turbo ]; then source /etc/network_turbo; fi"
```

Keep this behavior for git clone, pip install from GitHub, HuggingFace downloads, and similar remote academic-resource access.

## Remote workspace layout

Default remote workspace:

```text
/root/autodl-tmp/agent-workspace
  repos/
  runs/
  artifacts/
```

Local run records:

```text
result/agent-runs/<run-id>/
```

Remote run records:

```text
/root/autodl-tmp/agent-workspace/runs/<run-id>/
```

## Safety and reproducibility rules

- Do not paste passwords, private keys, or tokens into scripts or config files.
- Prefer SSH aliases and `ssh-copy-id` over password-based automation.
- Run every remote command through `scripts/autodl/agent.ps1`; avoid ad-hoc bare SSH except for one-time account setup or emergency diagnosis.
- For failures, read the harness log before changing approach.
- Do not start long training directly with `-Action run`; use `-Action start` so it is logged and detachable.
- Distinguish `nvidia-smi` driver-supported CUDA from actual toolkit CUDA. Check toolkit with `/usr/local/cuda/bin/nvcc --version` and `readlink -f /usr/local/cuda`.

## Current Scaffold-GS intake state

Repo:

```text
https://github.com/city-super/Scaffold-GS
```

Harness run id:

```text
20260504-184448-Scaffold-GS
```

Remote repo:

```text
/root/autodl-tmp/agent-workspace/repos/Scaffold-GS
```

Commit observed remotely:

```text
59c833b56bbbf510f3f64d40f81721995caced66
```

Important environment fact:

```text
nvidia-smi reports driver-supported CUDA 13.0, but the actual toolkit is /usr/local/cuda-12.4, nvcc V12.4.131.
```

Scaffold-GS facts discovered so far:

- Official environment is `environment.yml` with Python 3.7.13, PyTorch 1.12.1, cudatoolkit 11.6, `pytorch-scatter`, `wandb`, `lpips`, `laspy`, `diff-gaussian-rasterization`, and `simple-knn`.
- Training entry is `train.sh`, and `single_train.sh` is the single-scene wrapper.
- `train.sh` calls `python train.py --eval -s data/${data} ... --iterations 30000 -m outputs/${data}/${logdir}/$time`.
- Dataset layout expects project-local `data/<dataset>/<scene>/images` and `data/<dataset>/<scene>/sparse/0`.
- Current AutoDL `base` conda env is smoke-tested for this repo: Python 3.12.3, PyTorch 2.5.1+cu124, CUDA available, and imports for `torch_scatter`, `wandb`, `lpips`, `plyfile`, `diff_gaussian_rasterization`, and `simple_knn._C` are OK.
- Minimal text COLMAP scene exists at `mini_colmap_scene`; it has 3 images and `cameras.txt` uses `PINHOLE`.
- Barn data exists at `data/custom/Barn`: 410 images, 205 registered images, no registered image missing from `images/`, one camera, `points3D.bin` present, and `database.db` present.

Known smoke results:

- Harness seq `0056` exited 0 for a 1-iteration smoke on `mini_colmap_scene`.
- Mini output path: `/root/autodl-tmp/agent-workspace/repos/Scaffold-GS/outputs/mini_colmap_scene/smoke_1iter_fullres_20260507_175948`.
- Mini remote log: `/root/autodl-tmp/agent-workspace/runs/20260504-184448-Scaffold-GS/logs/0056.log`.
- Mini local stdout: `result/agent-runs/20260504-184448-Scaffold-GS/stdout/0056.txt`.
- Harness seq `0061` exited 0 for a 1-iteration smoke on `data/custom/Barn` with `--resolution 8`.
- Barn output path: `/root/autodl-tmp/agent-workspace/repos/Scaffold-GS/outputs/custom/Barn/smoke_1iter_20260507_180426`.
- Barn remote logs: smoke `/root/autodl-tmp/agent-workspace/runs/20260504-184448-Scaffold-GS/logs/0061.log`, artifact summary `/root/autodl-tmp/agent-workspace/runs/20260504-184448-Scaffold-GS/logs/0062.log`.
- Barn local stdout: `result/agent-runs/20260504-184448-Scaffold-GS/stdout/0061.txt` and `stdout/0062.txt`.
- Barn artifacts include `point_cloud/iteration_1/point_cloud.ply` (3,746,200 bytes), MLP `.pt` files, 52 test renders, 52 GT images, 52 error images, and metrics `SSIM 0.3327933`, `PSNR 9.5277967`, `LPIPS 0.7182686`.
- Harness seq `0073` confirmed a completed Barn 10000-iteration training run. Output path: `/root/autodl-tmp/agent-workspace/repos/Scaffold-GS/outputs/custom/Barn/train_10000_nockpt_20260507_182100`. Metrics: `SSIM 0.9342324`, `PSNR 29.1392136`, `LPIPS 0.0814643`. Artifacts include iteration 1000/5000/10000 point clouds and 52 final test renders/GT/error images.

Caution:

- Do not use `--resolution 8` with the 64x48 mini scene under `--eval`: training/saving/rendering succeeds, but final LPIPS evaluation fails because the image becomes too small for VGG pooling. Use `--resolution 1` for the mini smoke.
- If regenerating the mini scene, remove stale `cameras.bin`, `images.bin`, and `points3D.bin`; Scaffold-GS may prefer binary COLMAP files over text files.
- Barn 10000-iteration training passed when checkpoint saving was disabled.
- Do not pass `--checkpoint_iterations` in the current Scaffold-GS code without fixing `GaussianModel.capture()`: seq `0070` failed at iteration 5000 checkpoint save with `AttributeError: 'GaussianModel' object has no attribute '_local'`. Normal `--save_iterations` works.
- Do not start longer 30000-iteration training without explicit confirmation.

Known-good mini smoke command:

```bash
export CUDA_VISIBLE_DEVICES=0
export WANDB_MODE=disabled
export WANDB_DISABLED=true
python train.py --eval \
  -s mini_colmap_scene \
  --voxel_size 0.001 \
  --update_init_factor 16 \
  --appearance_dim 0 \
  --ratio 20 \
  --resolution 1 \
  --iterations 1 \
  --test_iterations 1 \
  --save_iterations 1 \
  -m outputs/mini_colmap_scene/smoke_1iter
```
