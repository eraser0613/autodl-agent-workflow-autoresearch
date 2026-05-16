# Harness Control Plane 学习文档

这组文档用于把本项目整理成一个适合实习准备、面试讲解和后续扩展的 Agent Harness 项目。

本项目的核心不是“写一个训练脚本”，而是把 Claude Code / Codex / 其他 Agent 的远程执行过程变成一个可管理、可观测、可复盘、可沉淀经验的本地控制平面。

## 推荐阅读顺序

1. [01-architecture-principles.md](01-architecture-principles.md)
   - 解释为什么需要 Harness 层，以及本项目的分层架构。
2. [02-target-registry-and-runtime.md](02-target-registry-and-runtime.md)
   - 解释多 SSH target、Runtime、Sandbox、连接状态和 lease 的设计。
3. [03-run-job-state-and-summarizer.md](03-run-job-state-and-summarizer.md)
   - 解释 Run / Job / Artifact / Event 状态模型，以及 summarizer 的核心代码。
4. [04-governance-observability-skills.md](04-governance-observability-skills.md)
   - 解释治理规则、错误分类、防死循环、可观测性和 skill 沉淀。
5. [05-dashboard-and-api-walkthrough.md](05-dashboard-and-api-walkthrough.md)
   - 解释本地 Web Dashboard 如何消费控制平面状态。
6. [06-internship-talking-points.md](06-internship-talking-points.md)
   - 帮你把项目包装成实习简历/面试表达。

## 当前已实现的关键入口

```text
config/targets.example.json                         # 多 SSH target registry 示例
policies/error-signatures.json                      # 错误签名库
policies/governance.rules.json                      # 治理规则种子
scripts/autodl/check_targets.mjs                    # target 健康检查与分类
scripts/autodl/summarize_agent_runs.mjs             # run/job/event 状态汇总器
web/server/harness.js                               # Dashboard 后端 API 与 target/run 读取逻辑
web/public/app.js                                   # Dashboard 前端展示逻辑
openspec/changes/evolve-multi-ssh-agent-harness/    # OpenSpec 设计与任务
skills/                                             # 可复用 runbook / skill candidates
```

## 一句话项目定位

> 一个面向 AI Coding Agent 的本地远程训练控制平面：通过多 SSH target 管理、结构化 Run/Job 状态、执行治理、错误分类、日志回放和 skill 沉淀，让 Agent 可以安全、可复现地推进多个 GPU 服务器上的开源项目实验。

## 面试时可以强调的关键词

- Agent Harness
- Runtime / Sandbox
- Control Plane
- Multi-target orchestration
- Durable state
- Observability
- Replayability
- Guardrails / Middleware
- Error signature classification
- Skill / Runbook capture
- Human-in-the-loop automation
