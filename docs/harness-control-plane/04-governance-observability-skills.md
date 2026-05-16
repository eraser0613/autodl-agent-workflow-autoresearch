# 04. 执行治理、可观测性与 Skill 沉淀

## 1. 为什么 Agent 需要执行治理

Agent 最大的问题之一不是“不会调用工具”，而是：

- 出错后重复执行同样的命令。
- 把连接失败误判为训练失败。
- 把长训练放在 foreground 里跑，导致中断不可恢复。
- 不看历史日志，直接换策略或重装环境。
- 同一台 GPU 被多个任务抢占。
- 失败经验没有沉淀，下次从零开始。

所以 Harness 需要 Governance，也就是执行治理层。

它的作用不是替代 Agent 思考，而是在关键节点给出约束、警告和结构化反馈。

## 2. 当前治理规则

规则文件：

```text
policies/governance.rules.json
```

当前包含：

```text
duplicateCommand
longForegroundTraining
retryLimits
staleJob
secretPatterns
```

这些规则不是一次性完成所有自动化，而是先建立治理语义。

## 3. 重复命令检测

重复命令检测的核心是 command hash。

一个 job 的 command hash 来自：

```text
cwd + conda_env + command
```

这样可以避免误判：

- 同样命令在不同目录下执行，不一定是同一件事。
- 同样命令在不同 conda env 下执行，也可能结果不同。

检测逻辑在：

```text
scripts/autodl/summarize_agent_runs.mjs:225
```

如果当前 job 的 hash 之前出现过，就添加 policy warning：

```json
{
  "id": "duplicate-command",
  "severity": "warn",
  "message": "Command hash already appeared in seq ..."
}
```

这对 Agent 很重要：

> 下次看到重复失败时，Agent 应该先解释为什么重复，而不是继续 retry。

## 4. Foreground 长训练检测

长训练应该用：

```powershell
scripts/autodl/agent.ps1 -Action start
```

而不是：

```powershell
scripts/autodl/agent.ps1 -Action run
```

原因：

- `run` 是前台命令，连接断了容易丢控制。
- `start` 会使用 screen/tmux，任务可分离、可回看日志。
- 长训练必须可恢复、可检查、可归档。

检测逻辑在：

```text
scripts/autodl/summarize_agent_runs.mjs:225
```

它会识别：

```text
python train.py
--iterations >= 1000
train_* 风格命令
```

并生成 warning。

## 5. Stale Background Job 检测

后台 job 有一个特殊问题：

```text
启动成功 != 训练完成
```

如果一个 background job 很久没有 finish record，就不能直接认为成功或失败。

当前逻辑：

```text
scripts/autodl/summarize_agent_runs.mjs:111
```

当 background job 超过阈值仍没有 finish 信息时，标记为：

```text
stale-candidate
```

并生成治理提示：

```text
inspect remote session/log before replacing it
```

这个设计防止：

- 旧任务其实还在跑，却被新任务覆盖。
- Agent 因为看不到结果就重复启动训练。
- 连接中断后错误判断任务状态。

## 6. 连接失败和工作负载失败分离

这是远程训练 Harness 很关键的一点。

例如：

```text
ssh: connect to host ... port ...: Connection refused
```

这表示本地控制通道失败，不代表远程 Python 训练失败。

连接分类在：

```text
web/server/harness.js:186
```

错误签名在：

```text
policies/error-signatures.json:5
```

Summarizer 会把 connection 类错误作为独立类别，不和 workload failure 混在一起：

```text
scripts/autodl/summarize_agent_runs.mjs:173
```

面试时这点很好讲：

> 在分布式/远程系统里，控制面失败和数据面/工作负载失败必须分离。我的 harness 会把 SSH connection-refused 标记为 target health 问题，而不是直接把训练任务判 failed。

## 7. Error Signature 库

错误签名文件：

```text
policies/error-signatures.json:1
```

每个 signature 包括：

```json
{
  "id": "cuda-oom",
  "category": "workload",
  "severity": "retry-with-changes",
  "patterns": ["cuda out of memory"],
  "likelyCause": "...",
  "suggestedNextAction": "...",
  "skillType": "troubleshooting"
}
```

这个设计有几个好处：

1. **把日志字符串变成结构化知识**

   不是只知道“报错了”，而是知道类别、严重程度、原因、下一步建议。

2. **支持可扩展**

   后续可以不断添加新的 signature。

3. **支持 skill 沉淀**

   同一个 signature 多次出现，就说明值得写成 runbook。

## 8. 当前已有错误类别

| Signature | Category | 说明 |
|---|---|---|
| `ssh-connection-refused` | connection | AutoDL 关机、端口变化、alias 过期 |
| `ssh-auth-failed` | connection | SSH key / 用户认证失败 |
| `ssh-timeout` | connection | 网络不可达 |
| `cuda-oom` | workload | 显存不足 |
| `cudnn-symbol-mismatch` | environment | NVIDIA/CUDNN 库加载顺序错误 |
| `checkpoint-corrupted` | artifact | checkpoint 下载损坏 |
| `dataset-format-error` | dataset | 数据格式不符合 repo loader |
| `lpips-image-too-small` | workload/profile | 图像太小导致 LPIPS/VGG 失败 |
| `duplicate-command` | governance | 重复执行风险 |

## 9. 可观测性 Events

可观测性不只是“有日志”，而是日志要结构化。

当前 event 生成在：

```text
scripts/autodl/summarize_agent_runs.mjs:303
```

事件包括：

```text
job_started
job_finished
artifact_found
error_classified
policy_warning
summary_generated
```

这些事件可以用于：

- Dashboard timeline。
- 回放调试。
- 统计失败率。
- 比较不同 repo 的接入成本。
- 将来做 Agent 轨迹评估。

## 10. Skill / Runbook 沉淀

新增目录：

```text
skills/troubleshooting/
skills/deployment/
skills/intake/
```

当前已经写了几个初始 runbook：

```text
skills/troubleshooting/ssh-connection-refused.md
skills/troubleshooting/cuda-oom.md
skills/troubleshooting/lpips-image-too-small.md
skills/deployment/cudnn-symbol-mismatch.md
skills/deployment/checkpoint-corrupted.md
skills/intake/dataset-format-adaptation.md
```

Skill candidate 生成逻辑：

```text
scripts/autodl/summarize_agent_runs.mjs:375
```

它会把反复出现的 signature 写入：

```text
result/skill-candidates/<signature-id>.json
```

## 11. 为什么不把所有经验都做成通用 skill

不是所有经验都应该通用化。

例如：

```text
CUDA OOM
CUDNN symbol mismatch
SSH connection refused
checkpoint corrupted
```

这些适合做通用 skill。

但：

```text
Scaffold-GS 当前 commit 不要传 --checkpoint_iterations
LiteVGGT 当前 AutoDL image 要禁用 fused attention
mini scene resolution 不能太低
```

这些更适合放在：

```text
profiles/<project>.local.ps1
项目 runbook
```

这就是设计文档里的原则：

> Do not move repo-specific assumptions into the generic harness.

对应：

```text
openspec/changes/evolve-multi-ssh-agent-harness/design.md:23
```

## 12. 面试表达

你可以这样讲：

> 我在 Harness 层做了执行治理：通过 command hash 防止重复执行，通过 foreground 长训练检测避免不可恢复任务，通过 stale background job 检测防止误重启，通过错误签名库把日志报错分类成 connection、environment、workload、dataset 等类别。这样 Agent 不再只是看到一段 stdout，而是能获得结构化的失败原因和下一步建议。

再进一步可以说：

> 我还把 repeated error signature 转成 skill candidate。也就是说，这个系统不仅能执行任务，还能从失败中沉淀可复用经验，逐步形成一个面向远程模型部署和开源项目复现的知识库。
