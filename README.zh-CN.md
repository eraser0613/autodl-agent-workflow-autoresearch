# AutoDL Agent Workflow

一个面向 `Claude Code / Codex / Code Agent` 的 AutoDL 远程训练控制工具包。它的目标是把“本地改代码、远程跑 GPU、回到本地看日志”的流程固定成可复用、可审计的脚本，而不是每次手动 SSH、复制命令和翻日志。

## 适合谁使用

- 使用 Windows + PowerShell 管理 AutoDL GPU 实例的个人开发者
- 希望让本地代码智能体安全控制远程训练的研究者
- 需要反复复现、调试、试跑 3DGS 或其他深度学习仓库的人
- 想把 SSH 连接、代码同步、训练启动、状态查看和日志监控标准化的项目

## 核心思路

```text
本地 Windows + Claude Code / Codex
  -> PowerShell 控制脚本
  -> SSH / SCP
  -> AutoDL Linux GPU 实例
  -> Conda / CUDA / 训练脚本
  -> 本地保存每轮命令与日志记录
```

Claude Code 或其他代码智能体留在本地，AutoDL 只作为远程 GPU 执行沙盒。所有远程操作尽量通过仓库中的脚本完成，便于记录、复盘和重复执行。

## 主要能力

- SSH 免密登录检查
- 本地代码打包并同步到 AutoDL
- 远程 Conda 环境与 GPU 状态检查
- 在 `screen` / `tmux` 中启动可断开的训练任务
- 查看远程训练状态和日志尾部
- 持续轮询训练日志
- 打开 TensorBoard 本地端口转发
- 针对 3D Gaussian Splatting 仓库的发现、同步、训练、渲染、评估流程
- 面向代码智能体的通用 AutoResearch 策略模板
- 本地只读 Web 控制面板，用于查看 run 记录和触发只读状态探测

## 目录概览

```text
scripts/autodl/
  通用 AutoDL PowerShell 脚本、3DGS 专用脚本、agent harness 脚本

docs/
  详细工作流文档和 AutoResearch 策略模板

profiles/
  项目或目标机器的配置模板

result/agent-runs/
  本地保存的 agent 执行记录、stdout、命令日志和启动脚本

web/
  本地 Web 控制面板
```

## 快速开始：通用 AutoDL 工作流

### 1. 配置 SSH 免密登录

AutoDL 通常会提供类似下面的 SSH 命令：

```powershell
ssh -p 40162 root@connect.xxx.seetacloud.com
```

在本地生成或复用 SSH key：

```powershell
ssh-keygen -t rsa
Start-Service ssh-agent
ssh-add $env:USERPROFILE\.ssh\id_rsa
Get-Content $env:USERPROFILE\.ssh\id_rsa.pub
```

首次用密码登录 AutoDL 后，把本地公钥追加到远程：

```bash
mkdir -p ~/.ssh
chmod 700 ~/.ssh
cat >> ~/.ssh/authorized_keys
# 粘贴完整公钥，回车，然后 Ctrl+D
chmod 600 ~/.ssh/authorized_keys
exit
```

然后在本地 `C:\Users\你的用户名\.ssh\config` 中添加 SSH alias：

```sshconfig
Host autodl-main
  HostName connect.xxx.seetacloud.com
  User root
  Port 40162
  IdentityFile C:\Users\你的用户名\.ssh\id_rsa
  IdentitiesOnly yes
  ServerAliveInterval 30
  ServerAliveCountMax 6
  TCPKeepAlive yes
```

验证免密登录：

```powershell
ssh -o BatchMode=yes autodl-main "echo ssh-ok"
```

### 2. 创建私有配置

复制示例配置：

```powershell
Copy-Item .\scripts\autodl\autodl.config.ps1.example .\scripts\autodl\autodl.config.ps1
```

编辑：

```text
scripts\autodl\autodl.config.ps1
```

常见需要修改的字段包括：

```powershell
$AutoDLHostAlias = "autodl-main"
$AutoDLRemoteProjectDir = "/root/autodl-tmp/my-project"
$AutoDLRemoteCondaEnv = "base"
$AutoDLTrainEntry = "python train.py --config configs/base.yaml"
$AutoDLRemoteLogDir = "/root/autodl-tmp/outputs/logs"
$AutoDLTensorBoardPort = 6006
```

真实配置文件不要提交到 git。

### 3. 日常命令

从仓库根目录运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\autodl\test_remote_connection.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\autodl\sync_to_autodl.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\autodl\run_remote_train.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\autodl\show_remote_status.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\autodl\watch_remote_training.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\autodl\open_tb_tunnel.ps1
```

推荐循环是：

1. 本地编辑代码
2. 同步到 AutoDL
3. 远程启动训练
4. 查看训练是否成功启动
5. 监控早期日志
6. 需要时打开 TensorBoard

## Claude Code-first Agent Harness

本仓库也包含更适合代码智能体使用的 harness。它比通用训练脚本更强调：

- 每条远程命令都有记录
- 每轮运行都有 run id
- 保存 stdout、exit code、cwd、conda env、远程 artifact 路径
- 避免把 repo-specific 假设写死进通用脚本
- 先做小型可逆探测，再做昂贵 setup 或训练

常用入口：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\autodl\agent.ps1 -Action status
powershell -ExecutionPolicy Bypass -File .\scripts\autodl\agent.ps1 -Action init -RepoName <repo-name>
powershell -ExecutionPolicy Bypass -File .\scripts\autodl\agent.ps1 -Action clone -RepoUrl <git-url> -RepoName <repo-name>
powershell -ExecutionPolicy Bypass -File .\scripts\autodl\agent.ps1 -Action run -RepoName <repo-name> -NoConda -Command "pwd && ls -la"
powershell -ExecutionPolicy Bypass -File .\scripts\autodl\agent.ps1 -Action start -RepoName <repo-name> -SessionName <name> -Command "<long command>"
powershell -ExecutionPolicy Bypass -File .\scripts\autodl\replay_agent_run.ps1 -RunId <run-id> -DryRun
```

复杂命令建议使用 `-CommandBase64`，特别是包含引号、shell 变量、heredoc、管道或正则时。

本地 run 记录默认写入：

```text
result/agent-runs/<run-id>/
```

远程工作区默认类似：

```text
/root/autodl-tmp/agent-workspace/
  repos/
  runs/
  artifacts/
```

## 3DGS 工作流

针对 3D Gaussian Splatting 复现，本仓库提供了一组专用脚本。

复制 3DGS 配置模板：

```powershell
Copy-Item .\scripts\autodl\autodl.3dgs.config.ps1.example .\scripts\autodl\autodl.3dgs.config.ps1
```

根据目标仓库和数据集修改：

```text
scripts\autodl\autodl.3dgs.config.ps1
```

典型流程：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\autodl\discover_3dgs_project.ps1 -ProjectDir "E:/path/to/target-3dgs-repo"
powershell -ExecutionPolicy Bypass -File .\scripts\autodl\test_3dgs_remote_connection.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\autodl\show_3dgs_runtime_diagnostics.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\autodl\check_3dgs_dataset.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\autodl\sync_3dgs_to_autodl.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\autodl\bootstrap_3dgs_remote.ps1 -NoSync
powershell -ExecutionPolicy Bypass -File .\scripts\autodl\run_3dgs_train.ps1 -NoSync
powershell -ExecutionPolicy Bypass -File .\scripts\autodl\show_3dgs_status.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\autodl\watch_3dgs_training.ps1
```

更多细节见：

```text
docs\3DGS_AUTODL_CLAUDE_CODE_WORKFLOW.md
```

该文档包含 SSH 设置、数据集放置、训练/渲染/评估命令、TensorBoard、结果拉回和 Claude Code 操作守则。

## AutoResearch 策略模板

如果你希望代码智能体不只是“启动训练”，还要负责：

- 阅读历史结果
- 提出新方案
- 判断继续还是停止
- 清理失败 artifact
- 避免重复方案
- 输出每轮研究报告

可以参考：

```text
docs\AUTORESEARCH_TEMPLATE.md
```

这个文件是通用模板，不绑定特定模型、数据集、论文方向或指标阈值。建议复制到你的主项目中，再改写成项目专用的研究策略。

## 本地 Web 控制面板

仓库包含一个本地只读 dashboard，用来查看 Claude Code 驱动的 AutoDL run 记录。它可以触发现有的只读状态探测，但不替代 Claude Code 作为命令执行者。

启动方式：

```powershell
cd .\web
npm start
```

然后打开：

```text
http://127.0.0.1:3766
```

它会读取：

- `web/config/targets.local.json`，如果存在
- 否则回退到 `scripts/autodl/autodl.agent.config.ps1`
- `result/agent-runs/<run-id>/run.json`
- `result/agent-runs/<run-id>/commands.jsonl`
- `result/agent-runs/<run-id>/stdout/*.txt`

多目标配置可从示例复制：

```powershell
Copy-Item .\web\config\targets.example.json .\web\config\targets.local.json
Copy-Item .\profiles\targets\target.agent.local.ps1.example .\profiles\targets\autodl-a.agent.local.ps1
```

注意：真实目标配置、SSH 信息、token、密码和本地私有路径不要提交。

## 常见问题

### SSH 仍然要求输入密码

通常是以下原因之一：

- 公钥没有正确写入远程 `~/.ssh/authorized_keys`
- 本地 SSH config 中的 `IdentityFile` 路径错误
- `HostName` 或 `Port` 与 AutoDL 当前实例不一致
- 远程 `~/.ssh` 或 `authorized_keys` 权限不正确

### `test_remote_connection.ps1` 失败

先单独验证：

```powershell
ssh autodl-main
```

然后检查：

- SSH alias 是否正确
- 私有配置是否存在
- Conda 环境名是否正确
- 远程是否有 `screen` 或 `tmux`

### 同步太慢

检查忽略文件：

```text
scripts\autodl\.autodlignore
scripts\autodl\.autodlignore.3dgs
```

不要把数据集、日志、checkpoint、渲染结果、缓存目录和大文件一起同步。

### 训练启动了但找不到日志

检查：

- 配置中的远程日志目录
- 训练命令是否真的写日志
- `screen` / `tmux` session 是否创建成功
- `show_remote_status.ps1` 或 agent harness 的 run 记录

### 更换 AutoDL 实例后怎么做

通常只需要：

1. 更新本地 `~/.ssh/config` 中的 host、port
2. 把公钥部署到新实例
3. 更新私有配置文件中的远程路径或环境名
4. 重新运行连接测试

## 安全注意事项

不要提交或公开：

- 真实 `autodl.config.ps1`
- 真实 `autodl.3dgs.config.ps1`
- 真实 `autodl.agent.config.ps1`
- SSH 私钥
- 服务器密码
- API token
- 私有数据集
- 私有 checkpoint
- 本地用户目录中的敏感配置
- `web/config/targets.local.json`

这个仓库应该只包含：

- 公共脚本
- 示例配置
- 通用文档
- 不含密钥和私有数据的运行模板

## 许可证

见 `LICENSE`。
