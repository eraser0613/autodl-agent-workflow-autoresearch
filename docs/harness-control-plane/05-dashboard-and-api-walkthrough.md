# 05. Web Dashboard 与 API 代码走读

## 1. Dashboard 的定位

本项目的 Web Dashboard 不是一个危险的“网页远程 Shell”。

它的定位是：

```text
Local-only read dashboard
```

也就是：

- 只监听本地 `127.0.0.1`。
- 主要读取 target/run/job/status summary。
- 远程操作仍然通过 Claude Code + `scripts/autodl/agent.ps1`。
- 页面可以生成 prompt / replay hint，但不绕过 harness。

入口文件：

```text
web/server/index.js
web/server/harness.js
web/public/app.js
```

## 2. Server 路由结构

`web/server/index.js` 提供 HTTP API。

核心 API：

```text
GET  /api/health
GET  /api/targets
GET  /api/targets/:targetId
POST /api/targets/:targetId/status
GET  /api/runs
GET  /api/runs/:runId
GET  /api/runs/:runId/stdout/:fileName
POST /api/status
```

其中 `/api/targets/:targetId/status` 会触发 target status probe。

## 3. Dashboard 后端的核心：harness.js

主要文件：

```text
web/server/harness.js
```

它承担的职责：

1. 读取 target registry。
2. 读取 last-known target status。
3. 调用 `agent.ps1 -Action status`。
4. 读取 runs。
5. 读取 run detail。
6. 读取 stdout。
7. 把结构化 summary 暴露给前端。

## 4. Target API

### 4.1 listTargets

关键代码：

```text
web/server/harness.js:286
```

`listTargets()` 会返回：

```json
{
  "source": "web-local | root-local | default-agent-config",
  "registryPath": "...",
  "targets": [
    {
      "id": "autodl-main",
      "name": "AutoDL Main",
      "hostAlias": "autodl-main",
      "configPath": "scripts/autodl/autodl.agent.config.ps1",
      "lastStatus": { ... }
    }
  ]
}
```

前端可以直接展示 target card。

### 4.2 runStatus

关键代码：

```text
web/server/harness.js:446
```

`runStatus(lines, targetId)` 做的事情：

```text
找到 target
  ↓
组装 powershell.exe -File scripts/autodl/agent.ps1 -Action status
  ↓
spawn 子进程
  ↓
收集 stdout/stderr
  ↓
设置 timeout
  ↓
写 result/targets/<target-id>/status.json
  ↓
返回 JSON 给前端
```

这里的关键不是简单 spawn，而是把结果写入 target status。

### 4.3 classifySshStatus

关键代码：

```text
web/server/harness.js:186
```

它把 raw status probe 分类成：

```text
online
connection-refused
timeout
auth-failed
config-missing
unknown
```

这使 dashboard 可以显示明确提示，而不是只显示 exit code。

## 5. Run API

### 5.1 listRuns

`listRuns()` 会读取：

```text
result/agent-runs/<run-id>/run.json
result/agent-runs/<run-id>/commands.jsonl
result/agent-runs/<run-id>/state.json
```

如果存在 `state.json`，会优先使用派生状态。

这样 dashboard 的 run list 可以展示：

- run id
- repo name
- status
- command count
- failed count
- background count
- artifact count
- latest job

### 5.2 getRun

关键代码：

```text
web/server/harness.js:404
```

`getRun(runId)` 会返回：

```json
{
  "run_id": "...",
  "manifest": { ... },
  "state": { ... },
  "commands": [ ... ],
  "jobs": [ ... ],
  "events": [ ... ],
  "stdout_files": [ ... ]
}
```

这里新增的关键点是：

```text
jobs.jsonl
events.jsonl
state.json
```

前端优先用 `jobs`，没有 jobs 才 fallback 到原始 `commands`。

## 6. 前端状态模型

主要文件：

```text
web/public/app.js
```

前端维护一个 `state`：

```js
const state = {
  health: null,
  targets: [],
  selectedTargetId: null,
  targetStatusById: {},
  runs: [],
  selectedRunId: null,
  selectedRun: null,
  selectedCommand: null,
  stdout: '',
  loading: false,
  error: '',
};
```

## 7. 前端如何优先使用 jobs.jsonl

关键代码：

```text
web/public/app.js:199
web/public/app.js:207
web/public/app.js:435
```

逻辑是：

```js
const commands = state.selectedRun.jobs?.length
  ? state.selectedRun.jobs
  : state.selectedRun.commands || [];
```

也就是说：

- 如果 summarizer 已经生成 jobs.jsonl，就展示结构化 job。
- 如果还没有生成，就兼容老的 commands.jsonl。

这个兼容策略很重要，因为它允许渐进式迁移。

## 8. Target 状态提示

前端函数：

```text
web/public/app.js:69
```

`statusProblem()` 会把 target status 转成用户可理解的提示。

例如：

```text
AutoDL SSH 连接被拒绝
远端实例可能已关机、SSH 端口已变化，或本地 SSH alias 指向旧实例。
这个状态只代表连接层失败，不等同于远端训练失败。
```

这就是把底层错误转成运维语义。

## 9. Timeline 展示

关键代码：

```text
web/public/app.js:435
```

`renderTimeline()` 展示每个 job：

```text
seq | status | duration | command preview
```

如果 job 来自 `jobs.jsonl`，它就会带有更多字段：

- `error_signature`
- `policy_warnings`
- `artifacts`
- `command_hash`
- `replayable`

## 10. Inspector 展示治理信息

关键代码：

```text
web/public/app.js:459
web/public/app.js:480
web/public/app.js:484
```

`renderInspector()` 会显示：

- status
- cwd
- conda env
- remote log
- error signature
- warning count
- artifact count
- policy warnings
- error classification
- command
- replay hint
- stdout

这使 dashboard 不只是日志查看器，而是一个 Agent 轨迹解释器。

## 11. Replay Hint

如果 job 是 replayable，前端会显示：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\autodl\replay_agent_run.ps1 -RunId <run-id> -DryRun
```

意义：

- 先 dry-run。
- 不直接重复执行。
- 让用户/Agent 看到复现路径。

## 12. 为什么 Dashboard 不直接暴露任意 SSH 命令

这是安全设计。

如果 dashboard 提供一个网页输入框让用户执行任意 SSH 命令，就会绕过：

- `agent.ps1` 的记录机制。
- Run/job 状态模型。
- Policy checks。
- 日志归档。
- Claude Code 的人工确认。

所以当前 dashboard 是 local-only、read-first、prompt-generating。

## 13. 未来可以怎么扩展

后续可以加：

```text
/api/events
/api/skill-candidates
/api/artifacts
/api/runs/:runId/replay-plan
/api/targets/:targetId/lease
```

但原则仍然是：

> API 调用 Harness 的受控动作，不直接变成裸 SSH 代理。

## 14. 面试表达

你可以这样讲：

> 我做了一个本地只读 Dashboard，用 Node.js 提供 API，读取 target registry、run state、jobs.jsonl 和 events.jsonl，并把连接失败、错误分类、policy warning、artifact 和 replay hint 展示出来。它不是直接执行任意 SSH 的控制台，而是消费 Harness 生成的结构化状态，保持所有远程执行都经过 agent.ps1，从而保证可记录、可复盘和可治理。
