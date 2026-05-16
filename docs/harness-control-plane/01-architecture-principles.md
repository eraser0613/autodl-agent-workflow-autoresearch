# 01. Harness Control Plane 架构与底层原理

## 1. 为什么这个项目需要 Harness 层

很多 Agent 项目表面上看是：

```text
LLM -> Tool Calling -> Shell / Browser / API
```

但真正落地到远程训练、模型部署、代码修改、多机器协作时，会遇到这些问题：

- Agent 每次只看到当前上下文，容易忘记之前做过什么。
- 远程命令失败后，如果没有结构化记录，很难判断是网络问题、环境问题、数据问题还是代码问题。
- 长训练、下载 checkpoint、编译 CUDA extension 这类任务成本高，不能盲目重复执行。
- 多个 SSH / AutoDL 实例同时推进时，需要知道哪台机器在线、哪台正在跑任务、哪台连接失败。
- 经验如果只停留在聊天记录里，下次遇到类似问题仍然要重新排查。

所以本项目引入的是一层 **Agent Harness Control Plane**。

它不是一个具体模型算法，也不是一个单纯脚本集合，而是位于 Agent 和远程机器之间的治理层：

```text
Claude Code / Codex / Other Agents
        ↓
Local Harness Control Plane
        ↓
SSH / AutoDL / GPU Servers
        ↓
Open-source repos / training / inference / evaluation
        ↓
Structured logs / state / summaries / skills
```

## 2. 本项目的核心设计思想

OpenSpec 设计文档中已经明确了这个目标：

- 把 SSH/AutoDL 机器表示成 managed targets。
- 把 harness 活动表示成 durable runs/jobs。
- 优先做低风险治理：连接失败分类、重复命令检测、stale job 检测、foreground 长训练警告。
- 输出结构化 events/summaries，供 dashboard 和未来 MCP 使用。
- 把重复错误沉淀成 skill/runbook candidate。

对应设计文件：

```text
openspec/changes/evolve-multi-ssh-agent-harness/design.md:1
openspec/changes/evolve-multi-ssh-agent-harness/design.md:28
openspec/changes/evolve-multi-ssh-agent-harness/design.md:45
openspec/changes/evolve-multi-ssh-agent-harness/design.md:55
```

## 3. 为什么先做本地文件型 Control Plane

这次没有直接上数据库、队列系统、Kubernetes 或复杂调度器，而是选择本地 JSON / JSONL 文件。

原因是：

1. **当前项目已经有文件型 run records**

   现有 harness 已经把每次运行记录在：

   ```text
   result/agent-runs/<run-id>/run.json
   result/agent-runs/<run-id>/commands.jsonl
   result/agent-runs/<run-id>/stdout/*.txt
   result/agent-runs/<run-id>/launchers/*.sh
   ```

   所以最安全的方式是“读取现有事实，生成派生状态”，而不是重写整个执行系统。

2. **Claude Code 很适合读写本地文本文件**

   JSON、JSONL、Markdown、PowerShell profile 都适合 Agent 读取、比较、修改和解释。

3. **容易回滚**

   新增的 summary/state/event 文件都是派生物。即使删掉，也不会破坏原始 run records。

4. **为未来 MCP / Web / 多 Agent 做准备**

   未来 MCP tools 不需要直接读凌乱日志，可以读结构化 summary。

## 4. 当前分层

可以把项目分成 7 层：

```text
Layer 1: Target Registry
  管理多个 SSH / AutoDL 目标。

Layer 2: Runtime / Execution
  通过 scripts/autodl/agent.ps1 执行远程命令。

Layer 3: Run / Job State
  把 commands.jsonl 转成 state.json/jobs.jsonl/events.jsonl。

Layer 4: Governance / Guardrails
  发现重复命令、stale job、foreground 长训练、连接失败等风险。

Layer 5: Observability / Replay
  提供结构化事件、artifact、error signature 和 replay hint。

Layer 6: Skill / Runbook Capture
  把反复出现的问题沉淀成可复用经验。

Layer 7: Dashboard / Future MCP
  Web UI 和未来 MCP 消费控制平面状态。
```

## 5. 核心数据流

一次完整的数据流大致是：

```text
agent.ps1 执行远程命令
        ↓
写入 result/agent-runs/<run-id>/commands.jsonl 和 stdout
        ↓
scripts/autodl/summarize_agent_runs.mjs 读取原始记录
        ↓
生成 state.json / jobs.jsonl / events.jsonl
        ↓
web/server/harness.js 读取结构化状态
        ↓
web/public/app.js 展示 timeline / error / warning / replay hint
        ↓
用户或 Claude Code 根据结构化信息决定下一步
```

这里的关键是：

> 原始执行记录仍然是 source of truth，summary 是可再生成的派生状态。

## 6. 和普通脚本项目的区别

普通远程训练脚本通常是：

```text
run_train.ps1 -> ssh -> python train.py
```

失败时只能看一堆日志。

这个项目要变成：

```text
run/job/target/state/event/error/signature/skill
```

也就是把“执行行为”变成可以被系统理解和治理的数据模型。

这是 Agent Harness 的核心价值。

## 7. 面试表达

你可以这样讲：

> 我做的不是一个单纯 AutoDL 训练脚本，而是一个面向 AI Coding Agent 的远程执行 Control Plane。它把多个 SSH GPU 实例抽象成 targets，把每条远程命令抽象成 jobs，把一次 repo intake/training/eval 抽象成 runs，并通过结构化日志、错误分类、重复命令检测、stale job 检测和 skill 沉淀，解决 Agent 在长期远程任务中容易丢状态、重复试错、不可观测的问题。

进一步可以补充：

> 当前阶段我没有直接做全自动调度，而是选择 human-in-the-loop：Claude Code 保持决策入口，Harness 负责记录、治理、预警和复盘。这降低了自动化误操作风险，也方便逐步扩展到 MCP 和多 Agent worker。
