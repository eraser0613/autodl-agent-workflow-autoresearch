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
    return JSON.parse(await fs.readFile(filePath, 'utf8'));
  } catch {
    return fallback;
  }
}

async function readJsonl(filePath) {
  try {
    const text = await fs.readFile(filePath, 'utf8');
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
  const local = await readJson(targetsLocalPath, null);
  if (local?.targets?.length) {
    return { source: 'local', registryPath: targetsLocalPath, targets: local.targets };
  }

  const inspected = await inspectAgentConfig(agentConfig);
  return {
    source: 'default',
    registryPath: targetsLocalPath,
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
    examplePath: toRepoRelative(targetsExamplePath),
    targets,
  };
}

export async function listTargets() {
  const registry = await loadTargetsInternal();
  return {
    ...registry,
    targets: registry.targets.map(publicTarget),
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
  return publicTarget(await getTargetInternal(targetId));
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
        const [manifest, commands, stat] = await Promise.all([
          readJson(path.join(runDir, 'run.json'), {}),
          readJsonl(path.join(runDir, 'commands.jsonl')),
          fs.stat(runDir).catch(() => null),
        ]);
        const normalized = commands.map(normalizeCommand);
        const latest = normalized.at(-1) ?? null;
        const failed_count = normalized.filter((command) => command.status === 'failed' || command.status === 'parse-error').length;
        const background_count = normalized.filter((command) => command.kind === 'background').length;

        return {
          run_id: entry.name,
          target_id: manifest.target_id || '',
          worker_id: manifest.worker_id || '',
          repo_name: manifest.repo_name || '',
          repo_url: manifest.repo_url || '',
          ref: manifest.ref || '',
          host_alias: manifest.host_alias || '',
          remote_root: manifest.remote_root || '',
          remote_run_dir: manifest.remote_run_dir || '',
          local_run_dir: manifest.local_run_dir || runDir,
          created_at: manifest.created_at || stat?.birthtime?.toISOString() || null,
          updated_at: stat?.mtime?.toISOString() || null,
          command_count: normalized.length,
          failed_count,
          background_count,
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
  const [manifest, commands, stdoutEntries] = await Promise.all([
    readJson(path.join(runDir, 'run.json'), {}),
    readJsonl(path.join(runDir, 'commands.jsonl')),
    fs.readdir(path.join(runDir, 'stdout'), { withFileTypes: true }).catch(() => []),
  ]);

  const stdout_files = stdoutEntries
    .filter((entry) => entry.isFile() && stdoutNamePattern.test(entry.name))
    .map((entry) => entry.name)
    .sort();

  return {
    run_id: runId,
    manifest,
    commands: commands.map(normalizeCommand),
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
    return {
      ok: false,
      exit_code: 1,
      timed_out: false,
      duration_ms: 0,
      stdout: '',
      stderr: `Missing target config: ${target.configPath}`,
      command: `${shell} ${args.join(' ')}`,
      target: publicTarget(target),
    };
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
    child.on('error', (error) => {
      clearTimeout(timer);
      resolve({
        ok: false,
        exit_code: 1,
        timed_out: timedOut,
        duration_ms: Date.now() - startedAt,
        stdout,
        stderr: `${stderr}${error.message}`,
        command: `${shell} ${args.join(' ')}`,
        target: publicTarget(target),
      });
    });
    child.on('close', (code) => {
      clearTimeout(timer);
      resolve({
        ok: code === 0 && !timedOut,
        exit_code: timedOut ? 124 : code,
        timed_out: timedOut,
        duration_ms: Date.now() - startedAt,
        stdout,
        stderr,
        command: `${shell} ${args.join(' ')}`,
        target: publicTarget(target),
      });
    });
  });
}
