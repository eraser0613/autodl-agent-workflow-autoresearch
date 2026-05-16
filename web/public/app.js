const state = {
  health: null,
  targets: [],
  targetRegistry: null,
  selectedTargetId: null,
  targetStatusById: {},
  statusLoadingTargetId: null,
  runs: [],
  selectedRunId: null,
  selectedRun: null,
  selectedCommand: null,
  stdout: '',
  loading: false,
  error: '',
};

const app = document.querySelector('#app');

const escapeHtml = (value = '') =>
  String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#039;');

const formatDate = (value) => {
  if (!value) return 'unknown';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return date.toLocaleString('zh-CN', { hour12: false });
};

const formatDuration = (value) => {
  if (!value && value !== 0) return '—';
  if (value < 1000) return `${value}ms`;
  return `${(value / 1000).toFixed(1)}s`;
};

const statusLabel = (status) => {
  const labels = {
    ok: 'OK',
    succeeded: 'OK',
    failed: 'FAIL',
    background: 'BG',
    running: 'RUN',
    'stale-candidate': 'STALE',
    unknown: 'UNK',
    'parse-error': 'BAD',
  };
  return labels[status] || status || 'UNK';
};

const statusTone = (status) => {
  if (status === 'ok' || status === 'succeeded') return 'ok';
  if (status === 'failed' || status === 'parse-error') return 'bad';
  if (status === 'background' || status === 'running' || status === 'stale-candidate') return 'warn';
  return 'muted';
};

const selectedTarget = () => state.targets.find((target) => target.id === state.selectedTargetId) || state.targets[0] || null;
const selectedStatus = () => (selectedTarget() ? state.targetStatusById[selectedTarget().id] || null : null);

function statusOutput(status = selectedStatus()) {
  if (!status) return '';
  return `${status.stdout || ''}${status.stderr || ''}`.trim();
}

function statusProblem(status = selectedStatus(), target = selectedTarget()) {
  if (!target) {
    return {
      tone: 'bad',
      title: '未配置 Target',
      detail: '没有可用 SSH target。请创建 web/config/targets.local.json，或保留 scripts/autodl/autodl.agent.config.ps1 作为默认 target。',
    };
  }

  if (!target.configExists) {
    return {
      tone: 'bad',
      title: 'Target 配置文件缺失',
      detail: `${target.name} 指向的配置不存在：${target.configPath}`,
    };
  }

  if (!status) return null;
  if (status.ok) {
    return {
      tone: 'ok',
      title: 'AutoDL SSH 可用',
      detail: `${target.name} (${target.hostAlias || target.id}) status probe 已成功返回。`,
    };
  }

  const output = statusOutput(status);
  const lower = output.toLowerCase();
  const alias = target.hostAlias || target.id;

  if (lower.includes('connection refused')) {
    return {
      tone: 'bad',
      title: 'AutoDL SSH 连接被拒绝',
      detail: `${target.name} (${alias}) 连接被拒绝：远端实例可能已关机、SSH 端口已变化，或本地 SSH alias 指向旧实例。这个状态只代表连接层失败，不等同于远端训练失败。`,
    };
  }
  if (lower.includes('connection timed out') || lower.includes('operation timed out')) {
    return {
      tone: 'bad',
      title: 'AutoDL SSH 连接超时',
      detail: `${target.name} (${alias}) 网络不可达、实例未启动，或当前端口无法访问。`,
    };
  }
  if (lower.includes('permission denied')) {
    return {
      tone: 'bad',
      title: 'AutoDL SSH 认证失败',
      detail: `${target.name} (${alias}) SSH key、用户名或 authorized_keys 可能不匹配。`,
    };
  }
  if (lower.includes('could not resolve hostname') || lower.includes('name or service not known')) {
    return {
      tone: 'bad',
      title: 'SSH 主机名无法解析',
      detail: `${target.name} (${alias}) 的 HostName 无法解析。检查 C:\\Users\\15981\\.ssh\\config。`,
    };
  }

  return {
    tone: 'bad',
    title: 'AutoDL status probe 失败',
    detail: `${target.name} (${alias}) 返回 exit ${status.exit_code ?? '?'}。请查看 Remote Status Raw Output。`,
  };
}

async function api(path, options = {}) {
  const response = await fetch(path, {
    headers: { 'content-type': 'application/json' },
    ...options,
  });
  const contentType = response.headers.get('content-type') || '';
  const payload = contentType.includes('application/json') ? await response.json() : await response.text();
  if (!response.ok) {
    throw new Error(payload.error || payload || `HTTP ${response.status}`);
  }
  return payload;
}

async function loadInitial() {
  state.loading = true;
  render();
  try {
    const [health, targetPayload, runPayload] = await Promise.all([api('/api/health'), api('/api/targets'), api('/api/runs')]);
    state.health = health;
    state.targets = targetPayload.targets || [];
    state.targetRegistry = targetPayload;
    state.runs = runPayload.runs || [];
    state.selectedTargetId = state.targets[0]?.id || null;
    state.selectedRunId = health.current_run || state.runs[0]?.run_id || null;
    if (state.selectedRunId) await loadRun(state.selectedRunId, false);
    state.error = '';
  } catch (error) {
    state.error = error.message;
  } finally {
    state.loading = false;
    render();
  }
}

async function refreshRuns() {
  try {
    const runPayload = await api('/api/runs');
    state.runs = runPayload.runs || [];
    if (state.selectedRunId) await loadRun(state.selectedRunId, false);
    render();
  } catch (error) {
    state.error = error.message;
    render();
  }
}

async function refreshTargets() {
  try {
    const targetPayload = await api('/api/targets');
    state.targets = targetPayload.targets || [];
    state.targetRegistry = targetPayload;
    if (!state.targets.some((target) => target.id === state.selectedTargetId)) {
      state.selectedTargetId = state.targets[0]?.id || null;
    }
    render();
  } catch (error) {
    state.error = error.message;
    render();
  }
}

async function loadRun(runId, shouldRender = true) {
  state.selectedRunId = runId;
  state.selectedRun = await api(`/api/runs/${encodeURIComponent(runId)}`);
  const commands = state.selectedRun.jobs?.length ? state.selectedRun.jobs : state.selectedRun.commands || [];
  state.selectedCommand = commands.at(-1) || null;
  state.stdout = '';
  if (state.selectedCommand?.stdout_name) await loadStdout(state.selectedCommand.stdout_name, false);
  if (shouldRender) render();
}

async function selectCommand(seq) {
  const timeline = state.selectedRun?.jobs?.length ? state.selectedRun.jobs : state.selectedRun?.commands || [];
  const command = timeline.find((item) => String(item.seq) === String(seq));
  state.selectedCommand = command || null;
  state.stdout = '';
  if (command?.stdout_name) await loadStdout(command.stdout_name, false);
  render();
}

async function loadStdout(fileName, shouldRender = true) {
  if (!state.selectedRunId || !fileName) return;
  try {
    state.stdout = await api(`/api/runs/${encodeURIComponent(state.selectedRunId)}/stdout/${encodeURIComponent(fileName)}`);
  } catch (error) {
    state.stdout = `Unable to read stdout: ${error.message}`;
  }
  if (shouldRender) render();
}

async function runStatusCheck(targetId = state.selectedTargetId) {
  if (!targetId) return;
  state.statusLoadingTargetId = targetId;
  render();
  try {
    const status = await api(`/api/targets/${encodeURIComponent(targetId)}/status`, {
      method: 'POST',
      body: JSON.stringify({ lines: 120 }),
    });
    state.targetStatusById = {
      ...state.targetStatusById,
      [targetId]: status,
    };
  } catch (error) {
    state.targetStatusById = {
      ...state.targetStatusById,
      [targetId]: {
        ok: false,
        exit_code: 1,
        stdout: '',
        stderr: error.message,
        duration_ms: 0,
        target: selectedTarget(),
      },
    };
  } finally {
    state.statusLoadingTargetId = null;
    render();
  }
}

function claudePrompt() {
  const target = selectedTarget();
  const status = selectedStatus();
  const runId = state.selectedRunId || '<run-id>';
  const command = state.selectedCommand;
  const problem = statusProblem(status, target);
  const targetLine = target
    ? `你被分配到 target ${target.id} (${target.name})。调用 harness 时使用 -ConfigPath "${target.configPath}"。`
    : '当前未配置 target。';

  if (problem && problem.tone === 'bad') {
    return `${targetLine}\n请继续使用本项目 AutoDL harness 诊断 SSH/status 失败。当前界面识别到：${problem.title}。先阅读 CLAUDE.md 和 result/agent-runs/${runId}/commands.jsonl，再解释根因。不要绕过 scripts/autodl/agent.ps1，不要直接启动训练。`;
  }
  if (command) {
    return `${targetLine}\n请基于 result/agent-runs/${runId}/commands.jsonl 中 seq=${command.seq_text} 的记录继续分析。先读取对应 stdout/log，判断失败根因或下一步最小可逆 probe。所有远端命令必须通过 scripts/autodl/agent.ps1。`;
  }
  return `${targetLine}\n请使用 AutoDL harness 检查当前远端状态。若 SSH 不通先解释连接失败原因，不要直接启动训练。`;
}

async function copyText(text) {
  await navigator.clipboard.writeText(text);
  const toast = document.createElement('div');
  toast.className = 'toast';
  toast.textContent = 'Copied';
  document.body.appendChild(toast);
  setTimeout(() => toast.remove(), 1400);
}

function renderHeader() {
  const health = state.health || {};
  const target = selectedTarget();
  const status = selectedStatus();
  const problem = statusProblem(status, target);
  const statusText = state.statusLoadingTargetId === target?.id ? '检测中' : problem ? problem.title : 'Target 未检测';
  const statusToneClass = state.statusLoadingTargetId === target?.id ? 'warn' : problem ? problem.tone : 'muted';

  return `
    <header class="topbar">
      <div>
        <h1>AutoDL Control Deck</h1>
        <p>多 SSH target 只读面板。远端操作仍通过 Claude Code + scripts/autodl/agent.ps1。</p>
      </div>
      <div class="header-actions">
        <div class="status-pill ${statusToneClass}">${escapeHtml(statusText)}</div>
        <button class="primary" ${state.statusLoadingTargetId ? 'disabled' : ''} data-action="status-selected">${state.statusLoadingTargetId ? '检查中...' : '检查所选 Target'}</button>
      </div>
    </header>
    <section class="summary-grid compact">
      <article><span>targets</span><strong>${state.targets.length}</strong><small>${escapeHtml(state.targetRegistry?.source || 'unknown registry')}</small></article>
      <article><span>selected target</span><strong>${escapeHtml(target?.id || 'none')}</strong><small>${escapeHtml(target?.hostAlias || 'no alias')}</small></article>
      <article><span>current run</span><strong>${escapeHtml(health.current_run || 'none')}</strong></article>
      <article><span>runs</span><strong>${state.runs.length}</strong><small>local records</small></article>
    </section>
  `;
}

function renderConnectionAlert() {
  const target = selectedTarget();
  if (state.statusLoadingTargetId === target?.id) {
    return `
      <section class="connection-alert warn">
        <strong>正在检查 ${escapeHtml(target.name)}</strong>
        <p>调用 scripts/autodl/agent.ps1 -ConfigPath ${escapeHtml(target.configPath)} -Action status。</p>
      </section>
    `;
  }

  const problem = statusProblem(selectedStatus(), target);
  if (!problem) {
    return `
      <section class="connection-alert muted">
        <strong>所选 Target 尚未检测</strong>
        <p>点击“检查所选 Target”后，这里会明确显示该 SSH 是否可达。</p>
      </section>
    `;
  }

  return `
    <section class="connection-alert ${problem.tone}">
      <strong>${escapeHtml(problem.title)}</strong>
      <p>${escapeHtml(problem.detail)}</p>
      ${selectedStatus()?.command ? `<code>${escapeHtml(selectedStatus().command)}</code>` : ''}
    </section>
  `;
}

function targetStatusTone(target) {
  if (state.statusLoadingTargetId === target.id) return 'warn';
  const problem = statusProblem(state.targetStatusById[target.id], target);
  if (!problem) return target.configExists ? 'muted' : 'bad';
  return problem.tone;
}

function renderTargets() {
  const targets = state.targets || [];
  if (!targets.length) return '<section class="targets-panel"><div class="empty">没有 target 配置。</div></section>';

  return `
    <section class="targets-panel">
      <div class="panel-title">
        <span>SSH Targets</span>
        <button class="mini" data-action="refresh-targets">刷新配置</button>
      </div>
      <div class="target-grid">
        ${targets
          .map((target) => {
            const selected = target.id === state.selectedTargetId ? 'selected' : '';
            const tone = targetStatusTone(target);
            const status = state.targetStatusById[target.id];
            const statusText = state.statusLoadingTargetId === target.id ? 'checking' : status ? (status.ok ? 'online' : 'failed') : target.configExists ? 'unchecked' : 'config missing';
            return `
              <article class="target-card ${selected} ${tone}">
                <div class="target-row">
                  <button class="target-select" data-action="select-target" data-target-id="${escapeHtml(target.id)}">
                    <span class="dot ${tone}"></span>
                    <strong>${escapeHtml(target.name)}</strong>
                  </button>
                  <button class="mini" ${state.statusLoadingTargetId ? 'disabled' : ''} data-action="status-target" data-target-id="${escapeHtml(target.id)}">status</button>
                </div>
                <dl>
                  <div><dt>id</dt><dd>${escapeHtml(target.id)}</dd></div>
                  <div><dt>alias</dt><dd>${escapeHtml(target.hostAlias || '—')}</dd></div>
                  <div><dt>config</dt><dd class="${target.configExists ? 'ok-text' : 'bad-text'}">${escapeHtml(target.configPath)}</dd></div>
                  <div><dt>state</dt><dd class="${tone}-text">${escapeHtml(statusText)}</dd></div>
                </dl>
                <div class="tags">${(target.tags || []).map((tag) => `<span>${escapeHtml(tag)}</span>`).join('')}</div>
              </article>
            `;
          })
          .join('')}
      </div>
      <p class="registry-note">registry: ${escapeHtml(state.targetRegistry?.registryPath || 'web/config/targets.local.json')} (${escapeHtml(state.targetRegistry?.source || 'unknown')})</p>
    </section>
  `;
}

function renderMetricCards() {
  const failed = state.runs.reduce((sum, run) => sum + (run.failed_count || 0), 0);
  const commands = state.runs.reduce((sum, run) => sum + (run.command_count || 0), 0);
  const background = state.runs.reduce((sum, run) => sum + (run.background_count || 0), 0);
  const latest = state.runs[0]?.latest;
  return `
    <section class="summary-grid">
      <article><span>commands</span><strong>${commands}</strong><small>所有记录命令</small></article>
      <article><span>failed commands</span><strong class="${failed ? 'bad-text' : ''}">${failed}</strong><small>需要优先查看</small></article>
      <article><span>background jobs</span><strong>${background}</strong><small>tmux / screen</small></article>
      <article><span>latest command</span><strong>${latest?.seq_text || '—'}</strong><small>${escapeHtml(latest?.status || 'no command')}</small></article>
    </section>
  `;
}

function renderRunList() {
  if (!state.runs.length) {
    return '<div class="empty">还没有 result/agent-runs 记录。</div>';
  }
  return state.runs
    .map((run) => {
      const latest = run.latest;
      const selected = run.run_id === state.selectedRunId ? 'selected' : '';
      const tone = statusTone(latest?.status);
      return `
        <button class="run-card ${selected}" data-action="select-run" data-run-id="${escapeHtml(run.run_id)}">
          <div class="run-main">
            <span class="dot ${tone}"></span>
            <strong>${escapeHtml(run.repo_name || run.run_id)}</strong>
            ${run.is_current ? '<em>CURRENT</em>' : ''}
          </div>
          <code>${escapeHtml(run.run_id)}</code>
          <div class="run-meta">
            <span>${run.command_count} cmds</span>
            <span>${run.failed_count} failed</span>
            <span>${formatDate(run.created_at)}</span>
          </div>
        </button>
      `;
    })
    .join('');
}

function renderTimeline() {
  const commands = state.selectedRun?.jobs?.length ? state.selectedRun.jobs : state.selectedRun?.commands || [];
  if (!commands.length) return '<div class="empty">这个 run 还没有 commands.jsonl。</div>';
  return `
    <div class="timeline-head">
      <span>seq</span><span>status</span><span>duration</span><span>command</span>
    </div>
    ${commands
      .map((command) => {
        const selected = command.seq === state.selectedCommand?.seq ? 'selected' : '';
        const tone = statusTone(command.status);
        return `
          <button class="timeline-row ${selected}" data-action="select-command" data-seq="${escapeHtml(command.seq)}">
            <span class="seq">${escapeHtml(command.seq_text)}</span>
            <span class="badge ${tone}">${statusLabel(command.status)}</span>
            <span class="duration">${formatDuration(command.duration_ms)}</span>
            <span class="cmd">${escapeHtml((command.command || '').replace(/\s+/g, ' ').slice(0, 180))}</span>
          </button>
        `;
      })
      .join('')}
  `;
}

function renderInspector() {
  const command = state.selectedCommand;
  if (!command) {
    return '<aside class="inspector"><div class="empty">选择一条命令查看详情。</div></aside>';
  }
  const prompt = claudePrompt();
  return `
    <aside class="inspector">
      <div class="panel-title">
        <span>Command Detail</span>
        <b>#${escapeHtml(command.seq_text)}</b>
      </div>
      <dl class="facts">
        <div><dt>status</dt><dd class="${statusTone(command.status)}-text">${statusLabel(command.status)}</dd></div>
        <div><dt>cwd</dt><dd>${escapeHtml(command.cwd || '—')}</dd></div>
        <div><dt>conda</dt><dd>${escapeHtml(command.conda_env || 'none')}</dd></div>
        <div><dt>remote log</dt><dd>${escapeHtml(command.remote_log || '—')}</dd></div>
        <div><dt>error</dt><dd>${escapeHtml(command.error_signature?.id || '—')}</dd></div>
        <div><dt>warnings</dt><dd>${escapeHtml(command.policy_warnings?.length || 0)}</dd></div>
        <div><dt>artifacts</dt><dd>${escapeHtml(command.artifacts?.length || 0)}</dd></div>
      </dl>
      ${(command.policy_warnings || []).length ? `<label class="label">policy warnings</label><pre class="code small">${escapeHtml(command.policy_warnings.map((warning) => `${warning.id}: ${warning.message}`).join('\n'))}</pre>` : ''}
      ${command.error_signature ? `<label class="label">error classification</label><pre class="code small">${escapeHtml(`${command.error_signature.id}\n${command.error_signature.suggestedNextAction || ''}`)}</pre>` : ''}
      <label class="label">command</label>
      <pre class="code small">${escapeHtml(command.command || '')}</pre>
      ${command.replayable ? `<label class="label">replay hint</label><pre class="code small">${escapeHtml(`powershell -ExecutionPolicy Bypass -File .\\scripts\\autodl\\replay_agent_run.ps1 -RunId ${state.selectedRunId} -DryRun`)}</pre>` : ''}
      <div class="copy-row">
        <button class="ghost" data-action="copy-command">复制命令</button>
        <button class="ghost" data-action="copy-prompt">复制 Claude prompt</button>
      </div>
      <label class="label">Claude Code prompt</label>
      <pre class="prompt">${escapeHtml(prompt)}</pre>
      <label class="label">stdout ${command.stdout_name ? escapeHtml(command.stdout_name) : ''}</label>
      <pre class="code stdout">${escapeHtml(state.stdout || 'No stdout file for this command.')}</pre>
    </aside>
  `;
}

function renderStatusPanel() {
  const target = selectedTarget();
  const status = selectedStatus();
  if (!status && state.statusLoadingTargetId !== target?.id) {
    return `
      <section class="status-panel">
        <div class="panel-title"><span>Remote Status</span><b>not checked</b></div>
        <p class="muted-copy">点击 target 的 status 按钮后，这里显示 agent.ps1 -ConfigPath ... -Action status 的完整输出。</p>
      </section>
    `;
  }

  const problem = statusProblem(status, target);
  return `
    <section class="status-panel ${problem?.tone || 'muted'}">
      <div class="panel-title">
        <span>Remote Status Raw Output</span>
        <b class="${status?.ok ? 'ok-text' : 'bad-text'}">${state.statusLoadingTargetId === target?.id ? 'running' : status?.ok ? 'exit 0' : `exit ${status?.exit_code ?? '?'}`}</b>
      </div>
      <pre class="code status-output">${escapeHtml(state.statusLoadingTargetId === target?.id ? 'Running agent.ps1 -ConfigPath ... -Action status ...' : statusOutput(status))}</pre>
    </section>
  `;
}

function renderMain() {
  return `
    ${renderHeader()}
    ${state.error ? `<div class="error-banner">${escapeHtml(state.error)}</div>` : ''}
    ${renderTargets()}
    ${renderConnectionAlert()}
    ${renderMetricCards()}
    <section class="deck-grid">
      <aside class="run-list">
        <div class="panel-title"><span>Runs</span><button class="mini" data-action="refresh">刷新</button></div>
        ${renderRunList()}
      </aside>
      <section class="timeline">
        <div class="panel-title"><span>Command Timeline</span><b>${escapeHtml(state.selectedRunId || 'no run')}</b></div>
        ${renderTimeline()}
      </section>
      ${renderInspector()}
    </section>
    ${renderStatusPanel()}
  `;
}

function render() {
  if (state.loading && !state.health) {
    app.innerHTML = `
      <section class="boot-panel">
        <h1>AutoDL Control Deck</h1>
        <p>扫描 targets、result/agent-runs 与 scripts/autodl/agent.ps1 ...</p>
      </section>
    `;
    return;
  }
  app.innerHTML = renderMain();
}

app.addEventListener('click', async (event) => {
  const target = event.target.closest('[data-action]');
  if (!target) return;
  const action = target.dataset.action;

  if (action === 'status-selected') await runStatusCheck(state.selectedTargetId);
  if (action === 'status-target') await runStatusCheck(target.dataset.targetId);
  if (action === 'refresh') await refreshRuns();
  if (action === 'refresh-targets') await refreshTargets();
  if (action === 'select-target') {
    state.selectedTargetId = target.dataset.targetId;
    render();
  }
  if (action === 'select-run') await loadRun(target.dataset.runId);
  if (action === 'select-command') await selectCommand(target.dataset.seq);
  if (action === 'copy-command' && state.selectedCommand) await copyText(state.selectedCommand.command || '');
  if (action === 'copy-prompt') await copyText(claudePrompt());
});

loadInitial();
