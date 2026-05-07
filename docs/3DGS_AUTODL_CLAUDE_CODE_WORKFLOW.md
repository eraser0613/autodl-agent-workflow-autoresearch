# 3DGS AutoDL Claude Code Workflow

This guide explains how to use this repository as a local Claude Code controller for reproducing and retrying open-source 3D Gaussian Splatting projects on AutoDL.

The intended model is:

```text
Local Windows + Claude Code
  -> PowerShell scripts
  -> SSH / SCP
  -> AutoDL GPU instance
  -> Conda + CUDA + 3DGS train/render/eval
```

Claude Code stays local. AutoDL is only the remote GPU execution sandbox.

## 1. First-time SSH setup

AutoDL usually gives an SSH command like:

```powershell
ssh -p 40162 root@connect.example.seetacloud.com
```

Generate or reuse a local SSH key:

```powershell
ssh-keygen -t rsa
Start-Service ssh-agent
ssh-add $env:USERPROFILE\.ssh\id_rsa
Get-Content $env:USERPROFILE\.ssh\id_rsa.pub
```

Log in once with the AutoDL password and append the public key to `~/.ssh/authorized_keys`:

```bash
mkdir -p ~/.ssh
chmod 700 ~/.ssh
cat >> ~/.ssh/authorized_keys
# paste the full public key, press Enter, then Ctrl+D
chmod 600 ~/.ssh/authorized_keys
exit
```

Create a local SSH alias in `C:\Users\YourUserName\.ssh\config`:

```sshconfig
Host autodl-main
  HostName connect.example.seetacloud.com
  User root
  Port 40162
  IdentityFile C:\Users\YourUserName\.ssh\id_rsa
  IdentitiesOnly yes
  ServerAliveInterval 30
  ServerAliveCountMax 6
  TCPKeepAlive yes
```

Verify passwordless SSH before running the 3DGS scripts:

```powershell
ssh -o BatchMode=yes autodl-main "echo ssh-ok"
```

## 2. Create the private 3DGS config

Copy the example config:

```powershell
Copy-Item .\scripts\autodl\autodl.3dgs.config.ps1.example .\scripts\autodl\autodl.3dgs.config.ps1
```

Edit:

```text
scripts\autodl\autodl.3dgs.config.ps1
```

At minimum, set:

```powershell
$AutoDLHostAlias = "autodl-main"
$AutoDL3DGSLocalProjectDir = "E:/xiangmu/vision-repro-agent/3dgs_paper/downloads_short/007_uni3r_unified_3d_reconstruct_2508.03643/r"
$AutoDL3DGSRemoteWorkspaceDir = "/root/autodl-tmp/3dgs-sandbox"
$AutoDL3DGSRemoteProjectDir = "/root/autodl-tmp/3dgs-sandbox/project"
$AutoDL3DGSRemoteDataRoot = "/root/autodl-tmp/3dgs-sandbox/data"
$AutoDL3DGSSceneName = "garden"
$AutoDL3DGSRemoteSceneDir = "/root/autodl-tmp/3dgs-sandbox/data/garden"
$AutoDL3DGSRemoteOutputRoot = "/root/autodl-tmp/3dgs-sandbox/outputs"
$AutoDL3DGSRemoteModelDir = "/root/autodl-tmp/3dgs-sandbox/outputs/garden"
$AutoDL3DGSRemoteCondaEnv = "gaussian_splatting"
```

Fork-specific command changes belong in the private config:

```powershell
$AutoDL3DGSTrainCommand = "python train.py -s /root/autodl-tmp/3dgs-sandbox/data/garden -m /root/autodl-tmp/3dgs-sandbox/outputs/garden --iterations 30000"
$AutoDL3DGSRenderCommand = "python render.py -m /root/autodl-tmp/3dgs-sandbox/outputs/garden"
$AutoDL3DGSEvalCommand = "python metrics.py -m /root/autodl-tmp/3dgs-sandbox/outputs/garden"
```

Do not commit the real config. It is ignored by `.gitignore`.

## 3. Discover an unfamiliar 3DGS project

If you do not know how a 3DGS repository starts, run local discovery first against the configured target repo:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\autodl\discover_3dgs_project.ps1 -ProjectDir $AutoDL3DGSLocalProjectDir
```

This inspects README files, environment files, requirements files, setup files, submodules, and likely Python entry points. It writes a suggested profile snippet under `result/`.

Review the generated snippet, then copy the useful parts into:

```text
scripts\autodl\autodl.3dgs.config.ps1
```

If the repository is already synced to AutoDL, run remote discovery:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\autodl\discover_3dgs_remote_project.ps1
```

Discovery is intentionally advisory. Claude Code should read the suggested commands and README candidates before launching setup or training.

## 4. Place datasets on AutoDL, not in local sync

Large 3DGS datasets should live directly on AutoDL, for example:

```text
/root/autodl-tmp/3dgs-sandbox/data/garden/
  images/
  sparse/0/
```

Normal sync intentionally excludes:

- `data/`, `dataset/`, `datasets/`
- `outputs/`, `runs/`, `logs/`
- images, videos, checkpoints, archives
- `.ply`, `.splat`, COLMAP-style generated outputs
- private AutoDL config files

If your upstream 3DGS repository stores source files in a directory named `images` or `data`, adjust `.autodlignore.3dgs` before syncing.

## 5. Validate remote access and runtime

Run:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\autodl\test_3dgs_remote_connection.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\autodl\show_3dgs_runtime_diagnostics.ps1
```

These commands check SSH, GPU visibility, Conda, Python, CUDA/PyTorch visibility, project paths, and common 3DGS package imports.

Check the configured dataset:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\autodl\check_3dgs_dataset.ps1
```

## 6. Sync source code

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\autodl\sync_3dgs_to_autodl.ps1
```

This packages the local project with `.autodlignore.3dgs`, uploads it to AutoDL, and extracts it into `$AutoDL3DGSRemoteProjectDir`.

## 7. Remote setup from zero

For a fresh AutoDL instance where the Conda environment may not exist, run bootstrap setup:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\autodl\bootstrap_3dgs_remote.ps1 -NoSync
```

If you want to try the repository's `environment.yml` or `environment.yaml` first:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\autodl\bootstrap_3dgs_remote.ps1 -NoSync -UseEnvironmentFile
```

After the environment exists, run setup after the first sync or after changing dependencies:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\autodl\setup_3dgs_remote.ps1 -NoSync
```

The setup commands come from `$AutoDL3DGSSetupCommands` in your private config. They run inside the configured Conda environment and remote project directory.

## 8. Daily 3DGS experiment loop

Typical loop:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\autodl\run_3dgs_train.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\autodl\show_3dgs_status.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\autodl\watch_3dgs_training.ps1
```

Training runs in `tmux` or `screen`, so it continues after the local terminal closes.

Render after training:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\autodl\run_3dgs_render.ps1
```

Evaluate metrics:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\autodl\run_3dgs_eval.ps1
```

Pull selected results:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\autodl\pull_3dgs_results.ps1
```

Pull checkpoints as well only when needed:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\autodl\pull_3dgs_results.ps1 -IncludeCheckpoints
```

## 9. TensorBoard

If TensorBoard is already running remotely:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\autodl\open_3dgs_tb_tunnel.ps1
```

To start TensorBoard remotely and open the tunnel:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\autodl\open_3dgs_tb_tunnel.ps1 -StartRemote
```

Then open:

```text
http://127.0.0.1:6006
```

## 10. Claude Code prompts

Example prompts to use inside Claude Code:

```text
Use the 3DGS AutoDL workflow. First run the 3DGS connection test, then sync the project, then launch training. Keep all remote commands inside the configured workspace.
```

```text
Read the latest 3DGS training log using show_3dgs_status.ps1 and watch_3dgs_training.ps1. If there is a CUDA or dataset error, explain the root cause before changing code.
```

```text
Update my private 3DGS config train command for scene garden, then run train with -NoSync because the source is already synced.
```

## 11. Guardrails

Claude Code should normally only operate inside configured paths:

- `$AutoDL3DGSRemoteWorkspaceDir`
- `$AutoDL3DGSRemoteProjectDir`
- `$AutoDL3DGSRemoteArchiveDir`
- `$AutoDL3DGSRemoteDataRoot`
- `$AutoDL3DGSRemoteOutputRoot`
- `$AutoDL3DGSRemoteLogDir`

Claude Code must ask for explicit approval before:

- deleting remote artifacts or broad directories
- killing non-default sessions or unrelated processes
- editing SSH configuration
- uploading keys or credentials
- installing system packages
- downgrading CUDA/PyTorch/system dependencies
- rebooting or shutting down AutoDL
- editing files outside the configured workspace

Never upload local private keys, Claude credentials, LLM API keys, or private datasets as part of this workflow.
