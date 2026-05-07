**AutoDL Agent Workflow**

This is a small open-source toolkit for `Codex / Claude Code / Code Agent`. Its purpose is to make the workflow of "edit code locally + train remotely on AutoDL + inspect logs locally" much more efficient.

It is designed for situations like these:

- You mainly write code locally or let a local coding agent edit code for you
- Training must run on a remote AutoDL GPU
- You do not want to manually log in, type long remote commands, or search for logs every time
- You want SSH connection, code sync, remote training, monitoring, and TensorBoard access to be fixed scripts

This project is not tied to any specific research repository, model, dataset, or paper direction. It only does one thing:

- Help local coding agents use AutoDL efficiently

**Who This Is For**

- `Codex`
- `Claude Code`
- `Code Agent`
- Individual developers who manage AutoDL training from Windows PowerShell

**What You Usually Have At The Beginning**

In most cases, you only start with an SSH command from AutoDL and a password, for example:

```bash
ssh -p 20162 root@connect.xxx.seetacloud.com
```

and the SSH password for that instance.

That is enough to complete the full setup.

**What The Final Workflow Should Look Like**

After setup, your daily workflow should be reduced to a few stable commands like these:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\autodl\test_remote_connection.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\autodl\sync_to_autodl.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\autodl\run_remote_train.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\autodl\show_remote_status.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\autodl\watch_remote_training.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\autodl\open_tb_tunnel.ps1
```

That means you no longer need to remember hostnames, ports, remote paths, or training commands every time.

**Assumed Environment**

This project assumes the following by default:

- Local OS: Windows
- Local shell: PowerShell
- Remote system: AutoDL Linux instance
- Remote login: SSH
- Remote Python environment: usually Conda
- Remote persistent session tool: `screen` or `tmux`, with `screen` preferred for compatibility

**Step 1: Generate An SSH Key Pair On Your Local Machine**

Run the following in PowerShell:

```powershell
ssh-keygen -t rsa
Start-Service ssh-agent
ssh-add $env:USERPROFILE\.ssh\id_rsa
```

What these commands do:

- `ssh-keygen -t rsa`
  - Generates an SSH key pair on your local machine
  - By default it creates:
    - Private key: `C:\Users\YourUserName\.ssh\id_rsa`
    - Public key: `C:\Users\YourUserName\.ssh\id_rsa.pub`
- `Start-Service ssh-agent`
  - Starts the Windows SSH agent
- `ssh-add`
  - Loads your private key into the current session so it can be used for passwordless login

If `Set-Service -StartupType Automatic` fails with access denied, that does not block the setup. It is enough that `Start-Service ssh-agent` and `ssh-add` work.

**Step 2: Print Your Local Public Key**

Run:

```powershell
Get-Content $env:USERPROFILE\.ssh\id_rsa.pub
```

You will get one full line starting with `ssh-rsa` or `ssh-ed25519`.

That entire line is the public key you need to place on the remote server.

**Step 3: Log Into AutoDL Once Using The Password**

Use the SSH command provided by AutoDL, for example:

```powershell
ssh -p 40162 root@connect.xxx.seetacloud.com
```

Then enter the AutoDL password.

This is usually the last time you need password-based login. After this step, you will switch to public-key login.

**Step 4: Add Your Public Key To The Remote Server**

After you log in, run:

```bash
mkdir -p ~/.ssh
chmod 700 ~/.ssh
cat >> ~/.ssh/authorized_keys
```

Then paste the full public key line from your local machine, press Enter once, and press:

```text
Ctrl + D
```

Then run:

```bash
chmod 600 ~/.ssh/authorized_keys
exit
```

Why this matters:

- `authorized_keys` is the file that tells the remote server which public keys are allowed for passwordless SSH login
- Once your local public key is in that file, your local private key can authenticate without a password

**Step 5: Create A Local SSH Alias**

Edit this file:

```text
C:\Users\YourUserName\.ssh\config
```

Add something like this:

```sshconfig
Host autodl-main
  HostName connect.xxx.seetacloud.com
  User root
  Port 40162
  IdentityFile C:\Users\YourUserName\.ssh\id_rsa
  IdentitiesOnly yes
  ServerAliveInterval 30
  ServerAliveCountMax 6
  TCPKeepAlive yes
```

What the fields mean:

- `Host autodl-main`
  - This is your local alias for the remote instance
  - All scripts in this toolkit use that alias by default
- `HostName`
  - The actual AutoDL hostname
- `Port`
  - The actual AutoDL SSH port
- `IdentityFile`
  - Your local private key path

After that, you should be able to connect like this:

```powershell
ssh autodl-main
```

**Step 6: Verify Passwordless SSH**

Run:

```powershell
ssh -o BatchMode=yes autodl-main "echo ssh-ok"
```

If the output is:

```text
ssh-ok
```

then passwordless login is working.

**Step 7: Copy The Local Config Template**

This open-source project does not include your real runtime config. It only ships a template.

Run:

```powershell
Copy-Item .\scripts\autodl\autodl.config.ps1.example .\scripts\autodl\autodl.config.ps1
```

Then edit:

```text
scripts\autodl\autodl.config.ps1
```

You will usually need to change these fields:

- `AutoDLHostAlias`
  - The SSH alias for the remote machine, usually `autodl-main`
- `AutoDLRemoteProjectDir`
  - The remote project directory
- `AutoDLRemoteCondaEnv`
  - The remote Conda environment name
- `AutoDLTrainEntry`
  - The actual training command
- `AutoDLRemoteLogDir`
  - The remote log directory
- `AutoDLTensorBoardPort`
  - The TensorBoard port

Example:

```powershell
$AutoDLHostAlias = "autodl-main"
$AutoDLRemoteProjectDir = "/root/autodl-tmp/my-project"
$AutoDLRemoteCondaEnv = "base"
$AutoDLTrainEntry = "python train.py --config configs/base.yaml"
$AutoDLRemoteLogDir = "/root/autodl-tmp/outputs/logs"
$AutoDLTensorBoardPort = 6006
```

**Step 8: Test The Remote Connection Script**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\autodl\test_remote_connection.ps1
```

This script checks:

- Whether SSH works
- Whether the host alias is correct
- Whether the Conda environment exists
- Whether `screen` or `tmux` is available
- Whether remote shell commands work normally

If this step fails, do not continue to sync or training. Fix SSH and the config first.

**Step 9: Sync Your Local Code To AutoDL**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\autodl\sync_to_autodl.ps1
```

This script is responsible for:

- Packaging your local project
- Ignoring files that should not be uploaded
- Sending the archive to the remote server
- Extracting it into the target directory on the remote machine

By default it uses:

```text
scripts\autodl\.autodlignore
```

That file controls what should not be synced, for example:

- Large checkpoints
- Logs
- Datasets
- Local caches
- Temporary files

If sync is heavier than necessary, improve `.autodlignore`.

**Step 10: Start Remote Training**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\autodl\run_remote_train.ps1
```

This script will:

- SSH into the remote machine
- Enter the project directory
- Activate the Conda environment
- Start training inside `screen` or `tmux`
- Write logs into a stable log directory

After that, the training should continue even if you close the current terminal.

**Step 11: Check Remote Training Status**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\autodl\show_remote_status.ps1
```

It is intended to show:

- Current persistent sessions
- GPU status
- The latest log tail
- Important remote directory status

This is the fastest way to confirm whether training actually started correctly.

**Step 12: Watch Remote Training Continuously**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\autodl\watch_remote_training.ps1
```

This is useful when:

- You just started a run and want to watch the first few epochs
- You want to see whether loss and validation metrics are changing
- You want to detect immediate crashes or obvious failure signs

This script is basically a remote log polling tool.

**Step 13: Open A TensorBoard Tunnel**

If TensorBoard is already running on the remote machine, run:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\autodl\open_tb_tunnel.ps1
```

Then open this in your local browser:

```text
http://127.0.0.1:6006
```

Prerequisites:

- TensorBoard must already be running on the remote machine
- The port in `autodl.config.ps1` must match the remote setup

**What Each Script Does**

`scripts\autodl\autodl.config.ps1.example`

- Template configuration file
- Copy it to `autodl.config.ps1` and fill in your real runtime values

`scripts\autodl\common.ps1`

- Shared helper functions
- Used by the other scripts for config loading, SSH execution, path handling, and logging

`scripts\autodl\test_remote_connection.ps1`

- Verifies SSH, environment, and basic remote dependencies

`scripts\autodl\sync_to_autodl.ps1`

- Syncs the local project to the remote machine

`scripts\autodl\run_remote_train.ps1`

- Starts training on the remote server

`scripts\autodl\show_remote_status.ps1`

- Shows current remote status

`scripts\autodl\watch_remote_training.ps1`

- Continuously polls training logs

`scripts\autodl\open_tb_tunnel.ps1`

- Creates a TensorBoard SSH tunnel

`scripts\autodl\.autodlignore`

- Controls which files should not be synced

**3DGS AutoDL Workflow**

This repository also includes a 3D Gaussian Splatting profile for using local Claude Code as the controller while AutoDL acts as the remote GPU execution sandbox.

Start with:

```powershell
Copy-Item .\scripts\autodl\autodl.3dgs.config.ps1.example .\scripts\autodl\autodl.3dgs.config.ps1
# edit $AutoDL3DGSLocalProjectDir in scripts\autodl\autodl.3dgs.config.ps1 when syncing a target repo such as Uni3R
powershell -ExecutionPolicy Bypass -File .\scripts\autodl\discover_3dgs_project.ps1 -ProjectDir "E:/path/to/target-3dgs-repo"
powershell -ExecutionPolicy Bypass -File .\scripts\autodl\test_3dgs_remote_connection.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\autodl\sync_3dgs_to_autodl.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\autodl\bootstrap_3dgs_remote.ps1 -NoSync
powershell -ExecutionPolicy Bypass -File .\scripts\autodl\run_3dgs_train.ps1 -NoSync
powershell -ExecutionPolicy Bypass -File .\scripts\autodl\show_3dgs_status.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\autodl\watch_3dgs_training.ps1
```

See `docs\3DGS_AUTODL_CLAUDE_CODE_WORKFLOW.md` for the full workflow, including SSH setup, dataset placement, train/render/eval commands, TensorBoard, result pullback, and Claude Code guardrails.

**Local Web Control Deck**

This repository includes a local-only read dashboard for Claude Code-driven AutoDL work.
It visualizes run records and can trigger the existing read-only status probe, but it does not replace Claude Code as the command executor.

Start it from the repository root:

```powershell
cd .\web
npm start
```

Then open:

```text
http://127.0.0.1:3766
```

The deck reads:

- `web/config/targets.local.json` when present, otherwise it falls back to `scripts/autodl/autodl.agent.config.ps1`
- `result/agent-runs/<run-id>/run.json`
- `result/agent-runs/<run-id>/commands.jsonl`
- `result/agent-runs/<run-id>/stdout/*.txt`

To register multiple SSH targets, copy the example registry and add one entry per target:

```powershell
Copy-Item .\web\config\targets.example.json .\web\config\targets.local.json
Copy-Item .\profiles\targets\target.agent.local.ps1.example .\profiles\targets\autodl-a.agent.local.ps1
```

Each target points to a private harness config path. The status button calls the same PowerShell harness with that target's config:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\autodl\agent.ps1 -ConfigPath .\profiles\targets\autodl-a.agent.local.ps1 -Action status -Lines 120
```

Keep sensitive SSH keys, passwords, tokens, real AutoDL configs, and `web/config/targets.local.json` outside git. Use the generated prompts or copied commands inside Claude Code for actual decision-making and follow-up actions.

**Recommended Daily Workflow**

The most common loop should look like this:

1. Edit code locally
2. Run `sync_to_autodl.ps1`
3. Run `run_remote_train.ps1`
4. Use `show_remote_status.ps1` to verify the run
5. Use `watch_remote_training.ps1` to monitor early training
6. Open `open_tb_tunnel.ps1` when you need TensorBoard

In other words, the efficient pattern is not to live inside a long manual SSH session. The better pattern is to treat the remote machine as a controlled training node.

**Common Problems**

`ssh-add` worked, but SSH still asks for a password

- Usually the public key was not written correctly into `authorized_keys`
- Or `IdentityFile` in your local SSH config is wrong
- Or the remote hostname or port is wrong

`test_remote_connection.ps1` fails

- First test `ssh autodl-main`
- Then inspect `autodl.config.ps1`
- Confirm that the remote Conda environment name is correct

Sync is too slow

- Check `.autodlignore`
- Do not upload datasets, logs, or large checkpoints with your code

Training starts but you cannot find logs

- Check `AutoDLRemoteLogDir`
- Check whether your training command actually writes logs
- Check whether `screen` or `tmux` created the session correctly

You switched to another AutoDL server

- You do not need to rewrite the scripts
- You only need to:
  - update `~/.ssh/config`
  - update `autodl.config.ps1`
  - deploy your public key to the new instance once

**How To Publish This As A Separate GitHub Repository**

This directory can be used directly as a standalone repository.

Inside the directory, run:

```powershell
cd .\autodl-agent-workflow
git init
git add .
git commit -m "init autodl agent workflow"
```

Then create a GitHub repository and connect it:

```powershell
git remote add origin YOUR_REPOSITORY_URL
git branch -M main
git push -u origin main
```

**Security Notes**

Do not publish the following:

- Your real `autodl.config.ps1`
- Your real `autodl.3dgs.config.ps1`
- Any real server password
- Any private key
- Real datasets
- Private checkpoints
- Sensitive local config from your user profile

The repository should contain only:

- Public scripts
- Example config
- Generic documentation

**Research Policy Template**

If you want `Codex / Claude Code / Code Agent` to do more than launch training, and also analyze experiments, decide whether to continue, and clean failed artifacts, see:

```text
docs\AUTORESEARCH_TEMPLATE.md
```

That file is a generic template. It is not tied to this repository and not tied to any specific research task.
