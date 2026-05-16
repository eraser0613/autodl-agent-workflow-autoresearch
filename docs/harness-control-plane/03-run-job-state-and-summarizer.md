# 03. Run / Job 状态模型与 Summarizer 原理

## 1. 为什么需要 Run / Job 模型

Agent 做远程任务时，如果只看 shell 输出，会很快失控。

例如一个开源项目 intake 可能包含：

```text
clone repo
read README
check CUDA
create conda env
install dependencies
compile extension
download checkpoint
prepare dataset
run smoke
run long training
summarize artifacts
```

这些动作不能只是一串日志，它们应该被建模成：

```text
Run: 一次完整项目实验或接入流程
Job: Run 下面的一条具体命令或后台任务
Artifact: Job 产生的输出文件或远程路径
Event: Job 生命周期中的结构化事件
Error Signature: Job 失败后的分类结果
```

## 2. 当前原始数据在哪里

原始 harness 记录在：

```text
result/agent-runs/<run-id>/run.json
result/agent-runs/<run-id>/commands.jsonl
result/agent-runs/<run-id>/stdout/*.txt
result/agent-runs/<run-id>/launchers/*.sh
```

`commands.jsonl` 中每一行就是一次 command record，包含：

- `seq`
- `kind`
- `cwd`
- `conda_env`
- `command`
- `started_at`
- `finished_at`
- `exit_code`
- `remote_log`
- `local_stdout`
- `launcher`
- `replayable`

## 3. Summarizer 的定位

新增脚本：

```text
scripts/autodl/summarize_agent_runs.mjs
```

它不是执行远程命令，而是做“状态归纳”：

```text
读取原始 run records
        ↓
解析每条 command
        ↓
生成 job 状态
        ↓
提取 artifact candidate
        ↓
分类错误
        ↓
生成 event log
        ↓
写入派生文件
```

输出文件：

```text
result/agent-runs/<run-id>/state.json
result/agent-runs/<run-id>/jobs.jsonl
result/agent-runs/<run-id>/events.jsonl
result/agent-runs/SUMMARY.json
```

## 4. Job 状态推断

关键代码：

```text
scripts/autodl/summarize_agent_runs.mjs:111
```

`inferStatus(record)` 做状态推断：

```text
parse-error        -> parse-error
exit_code == 0     -> succeeded
exit_code != 0     -> failed
background old     -> stale-candidate
background active  -> running
otherwise          -> unknown
```

这里有两个关键设计：

1. **后台任务不等于成功或失败**

   `-Action start` 启动的是 screen/tmux detached job。启动成功只代表“launcher 成功启动”，不代表训练完成。

2. **老旧 background 任务会变成 stale-candidate**

   如果 background job 没有 finish record，且时间超过阈值，就先标记为 stale-candidate，要求人工或 Agent 检查远程 session/log，而不是盲目重启。

## 5. Command Hash 与重复检测

每个 job 会计算 command hash。

用途：

- 判断同一个 run 内是否重复跑了同一条命令。
- 避免 Agent 在错误时不断重复试错。
- 支持后续 retry policy。

关键代码：

```text
scripts/autodl/summarize_agent_runs.mjs:225
```

`commandSummary()` 会把每条 record 转成结构化 job，同时检查：

- command hash
- duplicate seqs
- status
- stdout
- error signature
- artifact candidates
- policy warnings

## 6. 错误分类

关键代码：

```text
scripts/autodl/summarize_agent_runs.mjs:173
```

`classifyError(record, stdoutText, signatures)` 会：

1. 如果 job 已经 succeeded，则不分类错误。
2. 把 command、parse error、stdout 合成一个 haystack。
3. 用 `policies/error-signatures.json` 里的 pattern 匹配。
4. 找到后返回：

```json
{
  "id": "cuda-oom",
  "category": "workload",
  "severity": "retry-with-changes",
  "likelyCause": "...",
  "suggestedNextAction": "..."
}
```

错误签名库：

```text
policies/error-signatures.json:1
```

示例：

```text
ssh-connection-refused -> connection
cuda-oom               -> workload
cudnn-symbol-mismatch  -> environment
checkpoint-corrupted   -> artifact
dataset-format-error   -> dataset
lpips-image-too-small  -> workload/project-profile
```

## 7. Artifact 提取

关键代码：

```text
scripts/autodl/summarize_agent_runs.mjs:205
```

`extractArtifacts(text)` 会从 command 和 stdout 里找路径，例如：

```text
TRAIN_OUT=...
SMOKE_OUT=...
SUMMARY_JSON=...
/root/autodl-tmp/...
outputs/...
result/...
```

提取后的 artifact 不一定立刻验证，因为远程 target 可能离线。

所以 artifact 会有：

```json
{
  "kind": "path",
  "path": "/root/autodl-tmp/...",
  "source": "text",
  "verified": false
}
```

这体现了一个重要原则：

> 离线时保留候选事实，不因无法验证而丢弃信息。

## 8. Run State 汇总

关键代码：

```text
scripts/autodl/summarize_agent_runs.mjs:326
```

`summarizeRunState()` 会计算：

```json
{
  "run_id": "...",
  "repo_name": "...",
  "status": "failed | running | stale-candidate | succeeded | partial | unknown",
  "counts": {
    "jobs": 72,
    "succeeded": 53,
    "failed": 18,
    "stale": 1,
    "background": 1,
    "connection_failures": 0,
    "policy_warnings": 3,
    "artifacts": 453
  },
  "latest_job": {
    "seq": 72,
    "status": "succeeded",
    "command_hash": "..."
  }
}
```

注意：Run 的 overall status 不一定等于 latest job status。

例如：

- 一个 run 中历史上有失败 command，但最后一个 command 成功了。
- 这说明“当前最后一步成功”，但整个 run 仍有失败历史，需要复盘。

## 9. Event Log

关键代码：

```text
scripts/autodl/summarize_agent_runs.mjs:303
```

`makeEvents()` 会生成结构化事件：

```text
job_started
job_finished
artifact_found
error_classified
policy_warning
summary_generated
```

这些 events 的价值是：

- Dashboard 可以显示时间线。
- 后续可以做 replay/debug。
- 未来可以训练/评估 Agent 行为。
- 可以对比不同 repo 的执行轨迹。

## 10. Skill Candidate 生成

关键代码：

```text
scripts/autodl/summarize_agent_runs.mjs:375
```

`writeSkillCandidates()` 会把重复出现的错误签名生成 candidate：

```text
result/skill-candidates/<signature-id>.json
```

注意它只是 candidate，不是直接变成正式 skill。

原因是：

- 有些错误是通用的，比如 CUDA OOM。
- 有些错误是 repo-specific 的，比如 Scaffold-GS 某个 commit 的 checkpoint bug。
- 需要人工/Claude 判断是否值得沉淀成通用技能。

## 11. 为什么输出 JSONL

`jobs.jsonl` 和 `events.jsonl` 用 JSONL，而不是一个大 JSON 数组。

原因：

- 方便 append。
- 方便按行处理。
- 大日志不会一次性读爆。
- 很多日志系统和数据管道都支持 JSONL。

## 12. 幂等性设计

Summarizer 是幂等的：同样输入多次运行，应产生同样输出。

为了做到这一点：

- 使用稳定排序。
- 派生时间尽量来自已有 run/job 时间，而不是每次运行的当前时间。
- 写文件前比较内容，没变化就不改。

这对工程很重要，因为：

> 如果 summary 每次运行都变，git diff、dashboard refresh、测试都会变得混乱。

## 13. 面试表达

你可以这样讲：

> 我实现了一个 summarizer，把原始 commands.jsonl 和 stdout 转换成结构化的 jobs.jsonl、state.json 和 events.jsonl。它会推断 job 状态、计算 command hash、检测重复命令、提取 artifact 路径、匹配错误签名，并生成可供 dashboard 和未来 MCP 消费的控制平面状态。这个设计把不可控的 shell 日志转成了可治理的数据模型。
