# 06. 实习准备：如何讲这个项目

## 1. 简历项目名称建议

可以写成：

```text
AI Agent Remote Training Harness / 多 SSH GPU 远程实验控制平台
```

或者：

```text
面向 AI Coding Agent 的 AutoDL 多目标远程执行 Control Plane
```

如果投偏工程平台/基础设施岗位，建议突出：

```text
Control Plane / Observability / Runtime Governance / Multi-target SSH
```

如果投偏 AI Agent 岗位，建议突出：

```text
Agent Harness / Tool Runtime / Memory & State / Skill Capture
```

## 2. 一句话介绍

> 我做了一个面向 Claude Code / Codex 这类 AI Coding Agent 的远程训练 Harness，把多个 AutoDL GPU 服务器抽象成 targets，把每次开源项目复现实验抽象成 runs/jobs，并通过结构化日志、错误分类、执行治理、回放和 skill 沉淀，让 Agent 能安全、可观测、可复现地推进长期远程任务。

## 3. 30 秒版本

> 这个项目最初是为了解决本地 Agent 控制 AutoDL 远程训练的问题。后来我把它演化成一个 Harness Control Plane：它能管理多个 SSH target，记录每条远程命令的 cwd、conda env、exit code、stdout、remote log 和 artifact path，并把原始 commands.jsonl 汇总成 state.json、jobs.jsonl、events.jsonl。同时我加入了治理逻辑，比如 SSH 连接失败分类、重复命令检测、foreground 长训练警告、stale background job 检测，以及错误签名库。这样 Agent 不是每次从零开始，而是能基于结构化状态继续推进任务。

## 4. 2 分钟版本

可以按这个结构讲：

### 背景

> 我在复现 3DGS、LiteVGGT、MVP 这类开源项目时，需要本地 Claude Code 控制 AutoDL GPU 服务器。直接 SSH 会有很多问题：日志分散、命令不可追踪、长训练中断、环境错误反复排查、多台机器状态不清楚。

### 方案

> 所以我设计了一层本地 Harness Control Plane。它保留 Claude Code 作为决策入口，远程命令都通过 `scripts/autodl/agent.ps1` 执行，并记录到 `result/agent-runs/<run-id>`。然后我新增了 Node.js summarizer，把这些原始记录转成结构化的 run/job/event 状态。

### 核心能力

> 第一是 Target Registry，管理多个 SSH / AutoDL target，并分类 online、connection-refused、timeout、auth-failed 等状态。第二是 Run/Job 状态模型，记录每条命令的 command hash、status、error signature、artifact 和 policy warning。第三是 Governance，比如防重复命令、防 foreground 长训练、防 stale background job。第四是 Skill Capture，把反复出现的 CUDA OOM、CUDNN mismatch、checkpoint corrupted、dataset format error 等问题沉淀成 runbook。

### 结果

> 现在这个系统不仅能执行远程任务，还能解释任务状态、区分连接失败和训练失败、给出下一步诊断建议，并把结果展示到本地 Dashboard。后续可以自然扩展到 MCP tools 和多 Agent worker。

## 5. 项目亮点拆解

### 亮点 1：把 Agent 执行过程数据化

不是只保存日志，而是抽象出：

```text
Target
Run
Job
Artifact
Event
Error Signature
Skill Candidate
```

这体现了系统建模能力。

### 亮点 2：区分连接层失败和工作负载失败

例如：

```text
SSH connection refused
```

不等于：

```text
remote training failed
```

这是远程控制系统里非常重要的可靠性设计。

### 亮点 3：幂等 summarizer

`scripts/autodl/summarize_agent_runs.mjs` 可以反复运行，从原始 run records 派生 summary，不破坏原始数据。

这体现了数据管道和可恢复设计。

### 亮点 4：治理逻辑不是硬编码在 Agent prompt 里

规则被放到：

```text
policies/error-signatures.json
policies/governance.rules.json
```

这使系统可维护、可扩展，而不是靠每次聊天记忆。

### 亮点 5：Skill 沉淀

把反复出现的问题沉淀为：

```text
skills/troubleshooting/
skills/deployment/
skills/intake/
```

这体现了 Agent 系统的长期学习能力。

## 6. 可以写进简历的 bullet

### 版本 A：偏 Agent 基础设施

- 设计并实现面向 Claude Code/Codex 的 AutoDL 远程执行 Harness，将 SSH GPU 服务器抽象为 targets，将开源项目实验流程抽象为 runs/jobs/events，实现长期任务状态持久化与可回放。
- 实现 Node.js summarizer，将原始 `commands.jsonl/stdout` 转换为结构化 `state.json/jobs.jsonl/events.jsonl`，支持 command hash、错误分类、artifact 提取、policy warning 和 skill candidate 生成。
- 构建执行治理机制，支持 SSH 连接失败分类、重复命令检测、foreground 长训练警告、stale background job 检测，降低 Agent 重复执行和误判远程任务状态的风险。
- 搭建本地只读 Web Dashboard，展示多 SSH target 状态、run/job timeline、错误签名、policy warnings、artifact 数量和 replay hint，为后续 MCP 化提供控制平面接口。

### 版本 B：偏工程平台

- 构建 AutoDL 多目标远程实验控制平台，统一管理 SSH target、GPU 训练任务、运行日志、artifact 和错误诊断信息。
- 基于 JSON/JSONL 设计 durable state model，实现 run/job/event 的幂等汇总与 dashboard 可视化。
- 设计 error signature 与 governance policy 机制，将 CUDA OOM、CUDNN mismatch、checkpoint corruption、dataset format error 等问题自动分类并沉淀为 runbook。

### 版本 C：偏 AI 应用工程

- 围绕 AI Coding Agent 远程控制场景，设计 Harness 层解决工具调用后的状态记忆、执行治理、可观测性和经验复用问题。
- 将模型部署/开源项目复现中的常见失败模式抽象为 skills/runbooks，使 Agent 能基于历史知识快速定位环境、连接、数据和代码问题。

## 7. 面试官可能问什么

### Q1：为什么不用数据库？

可以答：

> 当前阶段我选择本地 JSON/JSONL，因为项目原本已经有文件型 run records，而且 Claude Code 很适合读写文本状态。JSONL 方便 append 和流式处理，summary 是派生状态，可随时重建。后续如果多 worker 并发写入增多，可以迁移到 SQLite 或轻量服务端数据库。

### Q2：为什么不用 Docker？

可以答：

> 对普通任务 Docker 很好，但这个项目大量涉及 CUDA extension、PyTorch ABI、nvcc、AutoDL 镜像和 3DGS-style repo。过早 Docker 化会增加驱动和库兼容复杂度。所以当前先把 conda/env/runtime 状态记录清楚，Docker 作为后续可选 runtime provider。

### Q3：怎么防止 Agent 死循环？

可以答：

> 我通过 command hash 和 error signature 做检测。同一个 run 内重复 command hash 会产生 duplicate warning；同类错误多次出现会进入 skill candidate 或 retry limit 流程。对于 foreground 长训练和 stale background job 也会标记 policy warning，要求先检查日志或改变策略再执行。

### Q4：怎么判断远程任务是否失败？

可以答：

> 不能只看本地 SSH 是否可连。我的设计把 target health 和 job status 分开。SSH connection-refused 是 target/control-plane failure，不自动等于 workload failure。Job status 来自 commands.jsonl 的 exit_code、background session 状态和 stdout/log 分类。

### Q5：这个项目和普通 DevOps 脚本有什么区别？

可以答：

> 普通脚本重点是执行命令；这个项目重点是让 Agent 的执行过程可治理。它有状态模型、错误分类、事件流、policy warning、skill capture 和 dashboard。它更像 Agent Runtime/Harness 的控制层，而不是单个部署脚本。

## 8. 可以继续扩展的方向

### 方向 1：SQLite 状态后端

当多 Agent 并发写入变多，可以把 JSONL 派生状态迁移到 SQLite。

### 方向 2：MCP Server

把这些能力封装为 MCP tools：

```text
list_targets
check_target
list_runs
get_job_log
classify_error
list_artifacts
```

注意不要暴露 raw SSH。

### 方向 3：自动 project evaluation agent

每个开源项目跑完后自动生成：

```text
项目亮点
环境复杂度
数据要求
smoke 是否成功
质量指标
artifact summary
是否值得继续投入
```

### 方向 4：更完整的 lease / scheduler

给每个 target 加 lease，防止多 Agent 同时占用 GPU。

### 方向 5：Skill promotion workflow

把 `result/skill-candidates/*.json` 自动转成 `.md` runbook 草稿，再由人审核。

## 9. 你需要熟悉的关键代码

| 模块 | 文件 | 重点 |
|---|---|---|
| Target Registry | `config/targets.example.json` | 多 SSH target 数据结构 |
| Target Health | `web/server/harness.js:186` | SSH 状态分类 |
| Status Probe | `web/server/harness.js:446` | 调用 agent.ps1 status |
| Run API | `web/server/harness.js:404` | 返回 run/job/event 给前端 |
| Summarizer | `scripts/autodl/summarize_agent_runs.mjs:416` | 汇总单个 run |
| Job Summary | `scripts/autodl/summarize_agent_runs.mjs:225` | job 状态、hash、warning、artifact |
| Error Classification | `scripts/autodl/summarize_agent_runs.mjs:173` | 匹配 error signatures |
| Events | `scripts/autodl/summarize_agent_runs.mjs:303` | 生成结构化事件 |
| Dashboard Timeline | `web/public/app.js:435` | 展示 jobs |
| Dashboard Inspector | `web/public/app.js:459` | 展示 error/warning/replay |

## 10. 最后总结

这个项目可以包装成一个很有价值的实习准备项目，因为它不是简单 CRUD，也不是单纯调 API，而是同时体现了：

- AI Agent 工程化理解
- 远程执行和 SSH 运维经验
- 状态建模能力
- 日志和可观测性设计
- 安全边界意识
- 长任务治理能力
- 从失败中沉淀知识的系统设计能力

一句话：

> 这是一个把“Agent 会执行命令”升级为“Agent 能可靠推进长期远程任务”的工程项目。
