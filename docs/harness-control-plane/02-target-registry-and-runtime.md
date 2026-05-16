# 02. Target Registry、Runtime 与 SSH 连接治理

## 1. Target Registry 解决什么问题

在单机单任务阶段，我们只需要一个 SSH alias，例如：

```text
autodl-main
```

但当你要同时管理多个 AutoDL / GPU 服务器时，只靠一个配置文件会遇到问题：

- 不知道当前有哪些 target。
- 不知道哪个 target 在线。
- 不知道哪个 target 正在被某个 run 使用。
- 不知道某个 SSH 失败是认证问题、端口变化，还是实例关机。
- 多个 Agent 可能误用同一台 GPU。

因此引入 Target Registry。

## 2. Target 的数据结构

示例文件：

```text
config/targets.example.json:1
```

一个 target 大致长这样：

```json
{
  "id": "autodl-main",
  "name": "AutoDL Main",
  "hostAlias": "autodl-main",
  "configPath": "scripts/autodl/autodl.agent.config.ps1",
  "remoteRoot": "/root/autodl-tmp/agent-workspace",
  "defaultCondaEnv": "base",
  "remoteMultiplexer": "screen",
  "capacity": 1,
  "tags": ["autodl", "gpu", "default"],
  "lease": {
    "mode": "local-file",
    "staleAfterMinutes": 720
  },
  "health": {
    "probeTimeoutSeconds": 120,
    "statusLines": 120
  }
}
```

每个字段的意义：

| 字段 | 作用 |
|---|---|
| `id` | 本地稳定标识，不随端口变化改变 |
| `hostAlias` | SSH config 中的 alias，比如 `autodl-main` |
| `configPath` | 该 target 使用的 harness config |
| `remoteRoot` | 远程工作区根目录 |
| `defaultCondaEnv` | 默认 conda 环境 |
| `remoteMultiplexer` | 使用 screen / tmux 管理长任务 |
| `capacity` | 当前 target 可并发承载多少任务，通常 GPU 单卡是 1 |
| `tags` | 便于筛选，例如 `4090d`、`autodl`、`standby` |
| `lease` | 防止多个 run 抢同一台机器 |
| `health` | status probe 的参数 |

## 3. 为什么真实 host/port 不放在 registry 里

示例里只保存 `hostAlias`，不保存真实 HostName、Port、IdentityFile。

原因：

1. SSH 连接信息可能包含隐私。
2. AutoDL 端口经常变化，应该由用户本地 SSH config 管理。
3. Harness 只需要知道“调用哪个 alias”。
4. 避免误提交私密配置。

所以真实信息在：

```text
C:\Users\15981\.ssh\config
scripts/autodl/autodl.agent.config.ps1
profiles/targets/*.local.ps1
```

这些 private/local 文件都应该被 git ignore。

## 4. Target Registry 的读取逻辑

关键代码：

```text
web/server/harness.js:286
```

`listTargets()` 会做几件事：

1. 加载 target registry。
2. 对每个 target 规范化字段。
3. 读取 last-known status。
4. 返回给 dashboard。

读取优先级是：

```text
web/config/targets.local.json
        ↓
config/targets.local.json
        ↓
scripts/autodl/autodl.agent.config.ps1 fallback
```

这个设计的好处是：

- 兼容旧配置。
- 支持 web-local 配置。
- 支持根目录统一配置。
- 不强制用户一次性迁移。

## 5. Runtime / Sandbox 的实际边界

本项目当前没有直接用 Docker 作为 remote sandbox，而是使用：

```text
本地 Windows + PowerShell harness
远程 AutoDL Linux + conda env + screen/tmux
```

这是一个更适合 CUDA 研究项目的选择。

原因：

- 很多 3DGS / CUDA extension 仓库依赖宿主 `nvcc`、PyTorch ABI、CUDA toolkit。
- Docker 反而可能引入额外显卡映射、驱动兼容问题。
- 当前阶段更重要的是把状态、日志、命令记录和安全边界做好。

所以当前 Runtime 设计是：

```text
Local runtime:
  Node.js dashboard
  PowerShell harness
  JSON/JSONL state files

Remote runtime:
  SSH alias
  conda env
  /root/autodl-tmp/agent-workspace
  screen/tmux detached sessions
```

## 6. SSH 健康检查

新增入口：

```text
scripts/autodl/check_targets.mjs
```

它会调用 web harness 中的 `runStatus()`：

```text
scripts/autodl/check_targets.mjs:17
web/server/harness.js:446
```

核心流程：

```text
读取 targets
  ↓
对每个 target 调用 agent.ps1 -Action status
  ↓
收集 stdout/stderr/exit_code/timed_out
  ↓
分类连接状态
  ↓
写 result/targets/<target-id>/status.json
```

## 7. 连接状态分类

关键代码：

```text
web/server/harness.js:186
```

`classifySshStatus(status)` 会把原始输出分类成：

| 分类 | 含义 |
|---|---|
| `online` | status probe 成功 |
| `connection-refused` | 端口拒绝，常见于 AutoDL 关机或端口变更 |
| `timeout` | 网络超时或实例不可达 |
| `auth-failed` | SSH key / 用户 / authorized_keys 不对 |
| `config-missing` | 本地 target config 文件不存在 |
| `unknown` | 其他未知失败 |

这一步非常重要，因为：

> SSH 连接失败不等于远程训练失败。

如果 AutoDL 端口变了，你本地无法连上，但远程可能仍有历史任务、文件或日志。Harness 必须区分“控制通道断了”和“工作负载失败了”。

## 8. 持久化 last-known target status

关键代码：

```text
web/server/harness.js:214
```

`writeTargetStatus(target, probe)` 会写：

```text
result/targets/<target-id>/status.json
```

内容包括：

```json
{
  "schema": "autodl-agent-target-status/v1",
  "target_id": "autodl-main",
  "health": "connection-refused",
  "ok": false,
  "exit_code": 1,
  "checked_at": "...",
  "last_seen_at": "...",
  "failure_hint": "..."
}
```

这样 dashboard 在 target 离线时仍能展示 last-known 状态，而不是一片空白。

## 9. Lease 的意义

Target Registry 中已经预留了 lease 字段：

```text
config/targets.example.json:15
config/targets.example.json:35
```

Lease 用来表达：

```text
target_id -> leased_by -> run_id/job_id -> expires_at
```

解决的问题：

- 防止两个长训练同时占用同一张 GPU。
- 防止连接中断后误以为 target 空闲。
- 防止多个 Agent worker 抢机器。

当前实现已经能读取/标记 stale lease，后续可以进一步把 lease 写入 preflight 流程。

## 10. 面试表达

你可以这样讲：

> 我把远程 GPU 服务器抽象成 Target，而不是把 SSH 命令散落在脚本里。每个 Target 有稳定 id、SSH alias、配置路径、容量、tag、health 和 lease 状态。健康检查不是只返回成功失败，而是分类成 connection-refused、timeout、auth-failed 等状态，并持久化到 result/targets。这样系统可以区分“控制通道不可达”和“远程任务失败”，这是多 Agent / 多 SSH 管控的基础。
