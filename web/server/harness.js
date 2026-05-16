import { spawn } from 'node:child_process';
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
export const repoRoot = path.resolve(__dirname, '..', '..');
export const runsRoot = path.join(repoRoot, 'result', 'agent-runs');
export const harnessScript = path.join(repoRoot, 'scripts', 'autodl', 'agent.ps1');
export const agentConfig = path.join(repoRoot, 'scripts', 'autodl', 'autodl.agent.config.ps1');
export const targetsLocalPath = path.join(repoRoot, 'web', 'config', 'targets.local.json');
export const targetsExamplePath = path.join(repoRoot, 'web', 'config', 'targets.example.json');
export const rootTargetsLocalPath = path.join(repoRoot, 'config', 'targets.local.json');
export const rootTargetsExamplePath = path.join(repoRoot, 'config', 'targets.example.json');
export const targetStatusRoot = path.join(repoRoot, 'result', 'targets');

const safeNamePattern = /^[A-Za-z0-9_.-]+$/;
const stdoutNamePattern = /^[A-Za-z0-9_.-]+\.txt$/;

export function assertSafeName(label, value) {
  if (!safeNamePattern.test(value)) {
    const error = new Error(`Invalid ${label}`);
    error.statusCode = 400;
    throw error;
  }
}

export function assertSafeStdoutName(value) {
  if (!stdoutNamePattern.test(value)) {
    const error = new Error('Invalid stdout file name');
    error.statusCode = 400;
    throw error;
  }
}

async function pathExists(filePath) {
  try {
    await fs.access(filePath);
    return true;
  } catch {
    return false;
  }
}

async function readJson(filePath, fallback = null) {
  try {
    return JSON.parse(await readText(filePath));
  } catch {
    return fallback;
  }
}

async function readText(filePath) {
  const buffer = await fs.readFile(filePath);
  const hasManyNulls = buffer.subarray(0, Math.min(buffer.length, 200)).includes(0);
  return buffer.toString(hasManyNulls ? 'utf16le' : 'utf8').replace(/^\uFEFF/, '');
}

async function readJsonl(filePath) {
  try {
    const text = await readText(filePath);
    return text
      .split(/\r?\n/)
      .filter((line) => line.trim().length > 0)
      .map((line, index) => {
        try {
          return JSON.parse(line);
        } catch (error) {
          return {
            seq: index + 1,
            kind: 'parse-error',
            command: line,
            exit_code: 1,
            parse_error: error.message,
          };
        }
      });
  } catch {
    return [];
  }
}

function seqText(seq) {
  const value = Number(seq);
  if (!Number.isFinite(value)) return '----';
  return String(value).padStart(4, '0');
}

function statusForCommand(record) {
  if (record.kind === 'background') return 'background';
  if (record.kind === 'parse-error') return 'parse-error';
  if (typeof record.exit_code === 'number') return record.exit_code === 0 ? 'ok' : 'failed';
  if (record.exit_code !== undefined && Number(record.exit_code) === 0) return 'ok';
  return 'unknown';
}

function normalizeCommand(record) {
  const seq = record.seq ?? null;
  const text = seqText(seq);
  return {
    ...record,
    seq_text: text,
    status: statusForCommand(record),
    stdout_name: record.local_stdout ? `${text}.txt` : null,
  };
}

function sanitizeTargetId(value, fallback) {
  const candidate = String(value || fallback || 'target').trim();
  const sanitized = candidate.replace(/[^A-Za-z0-9_.-]+/g, '-').replace(/^-+|-+$/g, '');
  return sanitized || fallback || 'target';
}

function resolveRepoPath(value) {
  const resolved = path.resolve(repoRoot, value || '');
  const relative = path.relative(repoRoot, resolved);
  if (relative.startsWith('..') || path.isAbsolute(relative)) {
    const error = new Error(`Target config path must stay inside the repository: ${value}`);
    error.statusCode = 400;
    throw error;
  }
  return resolved;
}

function toRepoRelative(filePath) {
  return path.relative(repoRoot, filePath).replaceAll(path.sep, '/');
}

async function inspectAgentConfig(configPathAbs) {
  try {
    const text = await fs.readFile(configPathAbs, 'utf8');
    const readStringVar = (name) => {
      const regex = new RegExp(`\\$${name}\\s*=\\s*[\"']([^\"']+)[\"']`);
      return text.match(regex)?.[1] || '';
    };
    return {
      hostAlias: readStringVar('AutoDLAgentHostAlias'),
      remoteRoot: readStringVar('AutoDLAgentRemoteRoot'),
      defaultCondaEnv: readStringVar('AutoDLAgentDefaultCondaEnv'),
      remoteMultiplexer: readStringVar('AutoDLAgentRemoteMultiplexer'),
    };
  } catch {
    return {
      hostAlias: '',
      remoteRoot: '',
      defaultCondaEnv: '',
      remoteMultiplexer: '',
    };
  }
}

async function readTargetsRegistry() {
  const webLocal = await readJson(targetsLocalPath, null);
  if (webLocal?.targets?.length) {
    return { source: 'web-local', registryPath: targetsLocalPath, targets: webLocal.targets };
  }

  const rootLocal = await readJson(rootTargetsLocalPath, null);
  if (rootLocal?.targets?.length) {
    return { source: 'root-local', registryPath: rootTargetsLocalPath, targets: rootLocal.targets };
  }

  const inspected = await inspectAgentConfig(agentConfig);
  return {
    source: 'default-agent-config',
    registryPath: rootTargetsLocalPath,
    targets: [
      {
        id: sanitizeTargetId(inspected.hostAlias || 'autodl-main', 'autodl-main'),
        name: 'Default AutoDL',
        hostAlias: inspected.hostAlias || 'autodl-main',
        configPath: toRepoRelative(agentConfig),
        capacity: 1,
        tags: ['default'],
        notes: 'Fallback target from scripts/autodl/autodl.agent.config.ps1. Copy web/config/targets.example.json to targets.local.json to add more targets.',
      },
    ],
  };
}

function publicTarget(target) {
  const { configPathAbs, ...safeTarget } = target;
  return safeTarget;
}

function classifySshStatus(status) {
  const output = `${status.stdout || ''}\n${status.stderr || ''}`.toLowerCase();
  if (status.ok) return 'online';
  if (status.timed_out || output.includes('connection timed out') || output.includes('operation timed out')) return 'timeout';
  if (output.includes('connection refused')) return 'connection-refused';
  if (output.includes('permission denied') || output.includes('authentication failed')) return 'auth-failed';
  if (output.includes('could not resolve hostname') || output.includes('name or service not known')) return 'offline';
  if (status.exit_code === 1 && String(status.stderr || '').includes('Missing target config')) return 'config-missing';
  return 'unknown';
}

async function readTargetStatus(targetId) {
  if (!targetId) return null;
  const status = await readJson(path.join(targetStatusRoot, targetId, 'status.json'), null);
  if (!status) return null;
  const lease = status.lease || null;
  const leaseExpiresAt = lease?.expires_at ? Date.parse(lease.expires_at) : NaN;
  return {
    ...status,
    lease: lease
      ? {
          ...lease,
          stale: Number.isFinite(leaseExpiresAt) ? Date.now() > leaseExpiresAt : Boolean(lease.stale),
        }
      : null,
  };
}

async function writeTargetStatus(target, probe) {
  const classified = classifySshStatus(probe);
  const existing = await readTargetStatus(target.id);
  const payload = {
    schema: 'autodl-agent-target-status/v1',
    target_id: target.id,
    name: target.name,
    host_alias: target.hostAlias,
    config_path: target.configPath,
    health: classified,
    ok: probe.ok,
    exit_code: probe.exit_code,
    timed_out: probe.timed_out,
    duration_ms: probe.duration_ms,
    checked_at: new Date().toISOString(),
    last_seen_at: probe.ok ? new Date().toISOString() : existing?.last_seen_at || null,
    command: probe.command,
    lease: existing?.lease || null,
    failure_hint: classified === 'online' ? '' : statusFailureHint(classified),
  };
  await fs.mkdir(path.join(targetStatusRoot, target.id), { recursive: true });
  await fs.writeFile(path.join(targetStatusRoot, target.id, 'status.json'), JSON.stringify(payload, null, 2) + '\n', 'utf8');
  return payload;
}

function statusFailureHint(classified) {
  const hints = {
    'connection-refused': 'AutoDL instance may be stopped or SSH port changed; update the SSH alias/config before retrying workloads.',
    timeout: 'Network path or instance is unavailable; run bounded status probes only.',
    'auth-failed': 'SSH key, username, IdentityFile, or authorized_keys may be wrong.',
    offline: 'Host alias cannot be resolved or target is offline.',
    'config-missing': 'Target config file is missing locally.',
    unknown: 'Read the raw status output before changing execution strategy.',
  };
  return hints[classified] || hints.unknown;
}

async function normalizeTarget(raw, index) {
  const id = sanitizeTargetId(raw.id, `target-${index + 1}`);
  assertSafeName('target id', id);

  const configPathAbs = resolveRepoPath(raw.configPath || toRepoRelative(agentConfig));
  const [configExists, inspected] = await Promise.all([pathExists(configPathAbs), inspectAgentConfig(configPathAbs)]);

  return {
    id,
    name: String(raw.name || id),
    hostAlias: String(raw.hostAlias || inspected.hostAlias || ''),
    configPath: toRepoRelative(configPathAbs),
    configPathAbs,
    configExists,
    remoteRoot: String(raw.remoteRoot || inspected.remoteRoot || ''),
    defaultCondaEnv: String(raw.defaultCondaEnv || inspected.defaultCondaEnv || ''),
    remoteMultiplexer: String(raw.remoteMultiplexer || inspected.remoteMultiplexer || ''),
    capacity: Number(raw.capacity || 1),
    tags: Array.isArray(raw.tags) ? raw.tags.map(String) : [],
    notes: raw.notes ? String(raw.notes) : '',
  };
}

async function loadTargetsInternal() {
  const registry = await readTargetsRegistry();
  const targets = await Promise.all(registry.targets.map((target, index) => normalizeTarget(target, index)));
  return {
    source: registry.source,
    registryPath: toRepoRelative(registry.registryPath),
    examplePath: toRepoRelative(rootTargetsExamplePath),
    webExamplePath: toRepoRelative(targetsExamplePath),
    targets,
  };
}

export async function listTargets() {
  const registry = await loadTargetsInternal();
  const targets = await Promise.all(
    registry.targets.map(async (target) => ({
      ...publicTarget(target),
      lastStatus: await readTargetStatus(target.id),
    })),
  );
  return {
    ...registry,
    targets,
  };
}

async function getTargetInternal(targetId) {
  const registry = await loadTargetsInternal();
  const target = targetId ? registry.targets.find((item) => item.id === targetId) : registry.targets[0];
  if (!target) {
    const error = new Error(`Unknown target: ${targetId}`);
    error.statusCode = 404;
    throw error;
  }
  return target;
}

export async function getTarget(targetId) {
  const target = await getTargetInternal(targetId);
  return {
    ...publicTarget(target),
    lastStatus: await readTargetStatus(target.id),
  };
}

export async function getCurrentRunId() {
  try {
    return (await fs.readFile(path.join(runsRoot, 'CURRENT'), 'utf8')).trim() || null;
  } catch {
    return null;
  }
}

export async function getHealth() {
  const [configExists, harnessExists, runsExists, currentRun, targetRegistry] = await Promise.all([
    pathExists(agentConfig),
    pathExists(harnessScript),
    pathExists(runsRoot),
    getCurrentRunId(),
    listTargets(),
  ]);

  return {
    repo_root: repoRoot,
    harness_script: harnessScript,
    agent_config_exists: configExists,
    harness_script_exists: harnessExists,
    runs_dir_exists: runsExists,
    current_run: currentRun,
    target_count: targetRegistry.targets.length,
    target_registry_source: targetRegistry.source,
    target_registry_path: targetRegistry.registryPath,
    node: process.version,
    pid: process.pid,
  };
}

export async function listRuns() {
  let entries = [];
  try {
    entries = await fs.readdir(runsRoot, { withFileTypes: true });
  } catch {
    return [];
  }

  const currentRun = await getCurrentRunId();
  const runs = await Promise.all(
    entries
      .filter((entry) => entry.isDirectory() && safeNamePattern.test(entry.name))
      .map(async (entry) => {
        const runDir = path.join(runsRoot, entry.name);
        const [manifest, commands, state, stat] = await Promise.all([
          readJson(path.join(runDir, 'run.json'), {}),
          readJsonl(path.join(runDir, 'commands.jsonl')),
          readJson(path.join(runDir, 'state.json'), null),
          fs.stat(runDir).catch(() => null),
        ]);
        const normalized = commands.map(normalizeCommand);
        const latest = state?.latest_job || normalized.at(-1) || null;
        const failed_count = state?.counts?.failed ?? normalized.filter((command) => command.status === 'failed' || command.status === 'parse-error').length;
        const background_count = state?.counts?.background ?? normalized.filter((command) => command.kind === 'background').length;

        return {
          run_id: entry.name,
          status: state?.status || latest?.status || 'unknown',
          target_id: state?.target_id || manifest.target_id || '',
          worker_id: manifest.worker_id || '',
          repo_name: state?.repo_name || manifest.repo_name || '',
          repo_url: manifest.repo_url || '',
          ref: manifest.ref || '',
          host_alias: manifest.host_alias || '',
          remote_root: manifest.remote_root || '',
          remote_run_dir: manifest.remote_run_dir || '',
          local_run_dir: manifest.local_run_dir || runDir,
          created_at: manifest.created_at || stat?.birthtime?.toISOString() || null,
          updated_at: stat?.mtime?.toISOString() || null,
          command_count: state?.counts?.jobs ?? normalized.length,
          failed_count,
          background_count,
          policy_warning_count: state?.counts?.policy_warnings ?? 0,
          artifact_count: state?.counts?.artifacts ?? 0,
          latest,
          is_current: entry.name === currentRun,
        };
      }),
  );

  return runs.sort((a, b) => new Date(b.created_at || b.updated_at || 0) - new Date(a.created_at || a.updated_at || 0));
}

export async function getRun(runId) {
  assertSafeName('run id', runId);
  const runDir = path.join(runsRoot, runId);
  const [manifest, commands, jobs, events, state, stdoutEntries] = await Promise.all([
    readJson(path.join(runDir, 'run.json'), {}),
    readJsonl(path.join(runDir, 'commands.jsonl')),
    readJsonl(path.join(runDir, 'jobs.jsonl')),
    readJsonl(path.join(runDir, 'events.jsonl')),
    readJson(path.join(runDir, 'state.json'), null),
    fs.readdir(path.join(runDir, 'stdout'), { withFileTypes: true }).catch(() => []),
  ]);

  const stdout_files = stdoutEntries
    .filter((entry) => entry.isFile() && stdoutNamePattern.test(entry.name))
    .map((entry) => entry.name)
    .sort();

  return {
    run_id: runId,
    manifest,
    state,
    commands: commands.map(normalizeCommand),
    jobs,
    events,
    stdout_files,
  };
}

export async function readStdout(runId, fileName) {
  assertSafeName('run id', runId);
  assertSafeStdoutName(fileName);
  const stdoutPath = path.join(runsRoot, runId, 'stdout', fileName);
  const normalized = path.normalize(stdoutPath);
  const allowedRoot = path.normalize(path.join(runsRoot, runId, 'stdout'));
  if (!normalized.startsWith(allowedRoot)) {
    const error = new Error('Invalid stdout path');
    error.statusCode = 400;
    throw error;
  }
  return fs.readFile(stdoutPath, 'utf8');
}

export async function runStatus(lines = 80, targetId = null) {
  const target = await getTargetInternal(targetId);
  const lineCount = Math.max(20, Math.min(Number(lines) || 80, 400));
  const shell = process.platform === 'win32' ? 'powershell.exe' : 'pwsh';
  const args = [
    '-ExecutionPolicy',
    'Bypass',
    '-File',
    harnessScript,
    '-ConfigPath',
    target.configPathAbs,
    '-Action',
    'status',
    '-Lines',
    String(lineCount),
  ];

  if (!target.configExists) {
    const probe = {
      ok: false,
      exit_code: 1,
      timed_out: false,
      duration_ms: 0,
      stdout: '',
      stderr: `Missing target config: ${target.configPath}`,
      command: `${shell} ${args.join(' ')}`,
      target: publicTarget(target),
    };
    const targetState = await writeTargetStatus(target, probe);
    return { ...probe, health: targetState.health, targetState };
  }

  return new Promise((resolve) => {
    const startedAt = Date.now();
    const child = spawn(shell, args, {
      cwd: repoRoot,
      windowsHide: true,
      env: process.env,
    });

    let stdout = '';
    let stderr = '';
    let timedOut = false;

    const timer = setTimeout(() => {
      timedOut = true;
      child.kill('SIGTERM');
    }, 120_000);

    child.stdout.on('data', (chunk) => {
      stdout += chunk.toString();
    });
    child.stderr.on('data', (chunk) => {
      stderr += chunk.toString();
    });
    child.on('error', async (error) => {
      clearTimeout(timer);
      const probe = {
        ok: false,
        exit_code: 1,
        timed_out: timedOut,
        duration_ms: Date.now() - startedAt,
        stdout,
        stderr: `${stderr}${error.message}`,
        command: `${shell} ${args.join(' ')}`,
        target: publicTarget(target),
      };
      const targetState = await writeTargetStatus(target, probe);
      resolve({ ...probe, health: targetState.health, targetState });
    });
    child.on('close', async (code) => {
      clearTimeout(timer);
      const probe = {
        ok: code === 0 && !timedOut,
        exit_code: timedOut ? 124 : code,
        timed_out: timedOut,
        duration_ms: Date.now() - startedAt,
        stdout,
        stderr,
        command: `${shell} ${args.join(' ')}`,
        target: publicTarget(target),
      };
      const targetState = await writeTargetStatus(target, probe);
      resolve({ ...probe, health: targetState.health, targetState });
    });
  });
}
