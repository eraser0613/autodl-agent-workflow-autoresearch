#!/usr/bin/env node
import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(__dirname, '..', '..');
const runsRoot = path.join(repoRoot, 'result', 'agent-runs');
const policiesRoot = path.join(repoRoot, 'policies');
const skillCandidatesRoot = path.join(repoRoot, 'result', 'skill-candidates');

const args = new Set(process.argv.slice(2));
const getArg = (name) => {
  const prefix = `${name}=`;
  const found = process.argv.slice(2).find((arg) => arg.startsWith(prefix));
  return found ? found.slice(prefix.length) : null;
};

const requestedRunId = getArg('--run-id');
const dryRun = args.has('--dry-run');
const stdoutReadLimit = Number(getArg('--stdout-limit') || 250_000);

function isoNow() {
  return new Date().toISOString();
}

function stableStringify(value) {
  return JSON.stringify(sortObject(value), null, 2) + '\n';
}

function sortObject(value) {
  if (Array.isArray(value)) return value.map(sortObject);
  if (!value || typeof value !== 'object') return value;
  return Object.fromEntries(Object.keys(value).sort().map((key) => [key, sortObject(value[key])]));
}

async function pathExists(filePath) {
  try {
    await fs.access(filePath);
    return true;
  } catch {
    return false;
  }
}

async function readText(filePath) {
  const buffer = await fs.readFile(filePath);
  const hasManyNulls = buffer.subarray(0, Math.min(buffer.length, 200)).includes(0);
  const text = buffer.toString(hasManyNulls ? 'utf16le' : 'utf8');
  return text.replace(/^\uFEFF/, '');
}

async function readJson(filePath, fallback = null) {
  try {
    return JSON.parse(await readText(filePath));
  } catch {
    return fallback;
  }
}

async function readJsonl(filePath) {
  try {
    const text = await readText(filePath);
    return text
      .split(/\r?\n/)
      .filter((line) => line.trim())
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

async function writeIfChanged(filePath, content) {
  if (dryRun) return false;
  await fs.mkdir(path.dirname(filePath), { recursive: true });
  let previous = null;
  try {
    previous = await fs.readFile(filePath, 'utf8');
  } catch {
    // absent
  }
  if (previous === content) return false;
  await fs.writeFile(filePath, content, 'utf8');
  return true;
}

function hashCommand(record) {
  const parts = [record.cwd || '', record.conda_env || '', record.command || ''];
  return crypto.createHash('sha256').update(parts.join('\n---\n')).digest('hex').slice(0, 16);
}

function seqText(seq) {
  const value = Number(seq);
  if (!Number.isFinite(value)) return '----';
  return String(value).padStart(4, '0');
}

function inferStatus(record) {
  if (record.kind === 'parse-error') return 'parse-error';
  if (typeof record.exit_code === 'number') return record.exit_code === 0 ? 'succeeded' : 'failed';
  if (record.exit_code !== undefined && Number(record.exit_code) === 0) return 'succeeded';
  if (record.kind === 'background') {
    const started = record.started_at ? Date.parse(record.started_at) : NaN;
    if (Number.isFinite(started) && Date.now() - started > 12 * 60 * 60 * 1000) return 'stale-candidate';
    return 'running';
  }
  return 'unknown';
}

function isLongForegroundTraining(record) {
  if (record.kind === 'background') return false;
  const command = String(record.command || '').toLowerCase();
  if (!/(python\s+train\.py|\btrain_\w*|--iterations)/.test(command)) return false;
  const match = command.match(/--iterations\s+([0-9]+)/);
  if (match && Number(match[1]) >= 1000) return true;
  return /python\s+train\.py/.test(command) && !/--iterations\s+1(\D|$)/.test(command);
}

async function readStdoutSnippet(runDir, record) {
  const localStdout = record.local_stdout ? path.resolve(String(record.local_stdout)) : '';
  const fallback = path.join(runDir, 'stdout', `${seqText(record.seq)}.txt`);
  const stdoutPath = localStdout && (await pathExists(localStdout)) ? localStdout : fallback;
  try {
    const stat = await fs.stat(stdoutPath);
    const handle = await fs.open(stdoutPath, 'r');
    try {
      const length = Math.min(stat.size, stdoutReadLimit);
      const buffer = Buffer.alloc(length);
      await handle.read(buffer, 0, length, 0);
      return {
        path: stdoutPath,
        truncated: stat.size > stdoutReadLimit,
        text: buffer.toString('utf8'),
      };
    } finally {
      await handle.close();
    }
  } catch {
    return { path: '', truncated: false, text: '' };
  }
}

function loadSignaturesSync(signaturesFileText) {
  try {
    const parsed = JSON.parse(signaturesFileText);
    return Array.isArray(parsed.signatures) ? parsed.signatures : [];
  } catch {
    return [];
  }
}

async function loadSignatures() {
  try {
    return loadSignaturesSync(await fs.readFile(path.join(policiesRoot, 'error-signatures.json'), 'utf8'));
  } catch {
    return [];
  }
}

function classifyError(record, stdoutText, signatures) {
  const status = inferStatus(record);
  if (status === 'succeeded') return null;
  const haystack = `${record.command || ''}\n${record.parse_error || ''}\n${stdoutText || ''}`.toLowerCase();
  if (!haystack.trim()) return null;
  for (const signature of signatures) {
    const patterns = Array.isArray(signature.patterns) ? signature.patterns : [];
    if (!patterns.length) continue;
    if (patterns.some((pattern) => haystack.includes(String(pattern).toLowerCase()))) {
      return {
        id: signature.id,
        category: signature.category || 'unknown',
        severity: signature.severity || 'unknown',
        likelyCause: signature.likelyCause || '',
        suggestedNextAction: signature.suggestedNextAction || '',
        skillType: signature.skillType || '',
      };
    }
  }
  if (inferStatus(record) === 'failed' || record.kind === 'parse-error') {
    return {
      id: 'unknown-failure',
      category: 'unknown',
      severity: 'needs-review',
      likelyCause: 'No known error signature matched this job output.',
      suggestedNextAction: 'Read stdout and remote log before retrying or changing strategy.',
      skillType: 'review',
    };
  }
  return null;
}

function extractArtifacts(text) {
  const artifacts = [];
  const seen = new Set();
  const push = (kind, value, source) => {
    const normalized = value.trim().replace(/[),.;]+$/, '');
    if (!normalized || seen.has(`${kind}:${normalized}`)) return;
    seen.add(`${kind}:${normalized}`);
    artifacts.push({ kind, path: normalized, source, verified: false });
  };

  for (const line of String(text || '').split(/\r?\n/)) {
    const marker = line.match(/\b([A-Z_]*(?:OUT|DIR|PATH|JSON|PLY|LOG)[A-Z_]*)=([^\s]+)/);
    if (marker) push(marker[1].toLowerCase(), marker[2].replace(/^['"]|['"]$/g, ''), 'marker');

    const pathMatches = line.match(/(?:\/root|\/autodl-[^\s]+|outputs\/|result\/)[^\s'"`]+/g) || [];
    for (const value of pathMatches) push('path', value, 'text');
  }
  return artifacts.slice(0, 40);
}

function commandSummary(record, stdoutInfo, signatures, duplicateSeqs) {
  const status = inferStatus(record);
  const commandHash = hashCommand(record);
  const stdoutName = record.local_stdout ? `${seqText(record.seq)}.txt` : null;
  const error = classifyError(record, stdoutInfo.text, signatures);
  const artifacts = extractArtifacts(`${record.command || ''}\n${stdoutInfo.text || ''}`);
  const policyWarnings = [];

  if (duplicateSeqs.length) {
    policyWarnings.push({
      id: 'duplicate-command',
      severity: 'warn',
      message: `Command hash already appeared in seq ${duplicateSeqs.join(', ')}.`,
      previousSeqs: duplicateSeqs,
    });
  }
  if (isLongForegroundTraining(record)) {
    policyWarnings.push({
      id: 'long-foreground-training',
      severity: 'warn',
      message: 'Long training appears to be running as a foreground command; use -Action start for detachable logging.',
    });
  }
  if (status === 'stale-candidate') {
    policyWarnings.push({
      id: 'stale-background-job',
      severity: 'warn',
      message: 'Background job has no finish record and is older than the stale threshold; inspect remote session/log before replacing it.',
    });
  }

  if (error?.category === 'connection') {
    policyWarnings.push({
      id: 'connection-failure-not-workload',
      severity: 'info',
      message: 'Connection failure is tracked separately from workload success/failure.',
    });
  }

  return {
    job_id: `seq-${seqText(record.seq)}`,
    seq: record.seq ?? null,
    seq_text: seqText(record.seq),
    kind: record.kind || 'foreground',
    status,
    command_hash: commandHash,
    duplicate_of: duplicateSeqs,
    started_at: record.started_at || null,
    finished_at: record.finished_at || null,
    duration_ms: record.duration_ms ?? null,
    cwd: record.cwd || '',
    conda_env: record.conda_env || '',
    command: record.command || '',
    exit_code: record.exit_code ?? null,
    remote_log: record.remote_log || '',
    local_stdout: record.local_stdout || '',
    stdout_name: stdoutName,
    stdout_truncated: stdoutInfo.truncated,
    local_launcher: record.local_launcher || '',
    launcher: record.launcher || '',
    session: record.session || '',
    replayable: Boolean(record.replayable),
    destructive: Boolean(record.destructive),
    artifacts,
    error_signature: error,
    policy_warnings: policyWarnings,
  };
}

function latestObservedAt(manifest, jobs) {
  const candidates = [manifest.created_at, ...jobs.flatMap((job) => [job.finished_at, job.started_at])]
    .filter(Boolean)
    .map((value) => Date.parse(value))
    .filter(Number.isFinite);
  if (!candidates.length) return null;
  return new Date(Math.max(...candidates)).toISOString();
}

function makeEvents(runId, jobs, observedAt) {
  const events = [];
  for (const job of jobs) {
    if (job.started_at) {
      events.push({ type: 'job_started', at: job.started_at, run_id: runId, job_id: job.job_id, seq: job.seq, command_hash: job.command_hash });
    }
    if (job.finished_at || job.exit_code !== null) {
      events.push({ type: 'job_finished', at: job.finished_at || null, run_id: runId, job_id: job.job_id, seq: job.seq, status: job.status, exit_code: job.exit_code });
    }
    for (const artifact of job.artifacts) {
      events.push({ type: 'artifact_found', at: job.finished_at || job.started_at || null, run_id: runId, job_id: job.job_id, seq: job.seq, artifact });
    }
    if (job.error_signature) {
      events.push({ type: 'error_classified', at: job.finished_at || job.started_at || null, run_id: runId, job_id: job.job_id, seq: job.seq, signature: job.error_signature });
    }
    for (const warning of job.policy_warnings) {
      events.push({ type: 'policy_warning', at: job.finished_at || job.started_at || null, run_id: runId, job_id: job.job_id, seq: job.seq, warning });
    }
  }
  events.push({ type: 'summary_generated', at: observedAt, run_id: runId, job_count: jobs.length });
  return events;
}

function summarizeRunState(runId, runDir, manifest, jobs, observedAt) {
  const failed = jobs.filter((job) => ['failed', 'parse-error'].includes(job.status)).length;
  const succeeded = jobs.filter((job) => job.status === 'succeeded').length;
  const running = jobs.filter((job) => job.status === 'running').length;
  const stale = jobs.filter((job) => job.status === 'stale-candidate').length;
  const unknown = jobs.filter((job) => job.status === 'unknown').length;
  const background = jobs.filter((job) => job.kind === 'background').length;
  const connectionFailures = jobs.filter((job) => job.error_signature?.category === 'connection').length;
  const policyWarnings = jobs.reduce((sum, job) => sum + job.policy_warnings.length, 0);
  const latest = jobs.at(-1) || null;
  const status = running ? 'running' : failed ? 'failed' : stale ? 'stale-candidate' : jobs.length && succeeded === jobs.length ? 'succeeded' : jobs.length ? 'partial' : 'unknown';
  return {
    schema: 'autodl-agent-run-state/v1',
    run_id: runId,
    repo_name: manifest.repo_name || '',
    repo_url: manifest.repo_url || '',
    ref: manifest.ref || '',
    target_id: manifest.target_id || manifest.host_alias || '',
    host_alias: manifest.host_alias || '',
    remote_root: manifest.remote_root || '',
    remote_run_dir: manifest.remote_run_dir || '',
    local_run_dir: manifest.local_run_dir || runDir,
    created_at: manifest.created_at || null,
    summarized_at: observedAt,
    status,
    counts: {
      jobs: jobs.length,
      succeeded,
      failed,
      running,
      stale,
      unknown,
      background,
      connection_failures: connectionFailures,
      policy_warnings: policyWarnings,
      artifacts: jobs.reduce((sum, job) => sum + job.artifacts.length, 0),
    },
    latest_job: latest
      ? {
          job_id: latest.job_id,
          seq: latest.seq,
          status: latest.status,
          command_hash: latest.command_hash,
          error_signature_id: latest.error_signature?.id || '',
        }
      : null,
  };
}

async function writeSkillCandidates(runSummaries) {
  const bySignature = new Map();
  for (const summary of runSummaries) {
    for (const job of summary.jobs) {
      const signature = job.error_signature;
      if (!signature || signature.id === 'unknown-failure') continue;
      if (!bySignature.has(signature.id)) {
        bySignature.set(signature.id, { signature, examples: [] });
      }
      bySignature.get(signature.id).examples.push({
        run_id: summary.runId,
        job_id: job.job_id,
        seq: job.seq,
        stdout: job.local_stdout,
        remote_log: job.remote_log,
      });
    }
  }

  const written = [];
  for (const [id, candidate] of bySignature) {
    if (candidate.examples.length < 2 && !['ssh-connection-refused', 'cuda-oom', 'cudnn-symbol-mismatch'].includes(id)) continue;
    const payload = {
      schema: 'autodl-agent-skill-candidate/v1',
      id,
      title: `Skill candidate: ${id}`,
      category: candidate.signature.category,
      skillType: candidate.signature.skillType,
      likelyCause: candidate.signature.likelyCause,
      suggestedNextAction: candidate.signature.suggestedNextAction,
      exampleCount: candidate.examples.length,
      examples: candidate.examples.slice(0, 12),
      review: 'Promote to skills/ only if this is generic and reusable; keep project-specific lessons in profiles.',
    };
    const out = path.join(skillCandidatesRoot, `${id}.json`);
    await writeIfChanged(out, stableStringify(payload));
    written.push(out);
  }
  return written;
}

async function summarizeRun(runId, signatures) {
  const runDir = path.join(runsRoot, runId);
  const manifest = await readJson(path.join(runDir, 'run.json'), {});
  const records = await readJsonl(path.join(runDir, 'commands.jsonl'));
  const seenHashes = new Map();
  const jobs = [];

  for (const record of records) {
    const commandHash = hashCommand(record);
    const duplicateSeqs = seenHashes.get(commandHash) || [];
    const stdoutInfo = await readStdoutSnippet(runDir, record);
    const job = commandSummary(record, stdoutInfo, signatures, duplicateSeqs);
    jobs.push(job);
    seenHashes.set(commandHash, [...duplicateSeqs, record.seq].filter((seq) => seq !== undefined));
  }

  const observedAt = latestObservedAt(manifest, jobs);
  const state = summarizeRunState(runId, runDir, manifest, jobs, observedAt);
  const events = makeEvents(runId, jobs, observedAt);

  await writeIfChanged(path.join(runDir, 'jobs.jsonl'), jobs.map((job) => JSON.stringify(job)).join('\n') + (jobs.length ? '\n' : ''));
  await writeIfChanged(path.join(runDir, 'state.json'), stableStringify(state));
  await writeIfChanged(path.join(runDir, 'events.jsonl'), events.map((event) => JSON.stringify(event)).join('\n') + '\n');

  return { runId, state, jobs, events };
}

async function listRunIds() {
  if (requestedRunId) return [requestedRunId];
  const entries = await fs.readdir(runsRoot, { withFileTypes: true }).catch(() => []);
  return entries.filter((entry) => entry.isDirectory() && /^[A-Za-z0-9_.-]+$/.test(entry.name)).map((entry) => entry.name).sort();
}

async function main() {
  const signatures = await loadSignatures();
  const runIds = await listRunIds();
  const summaries = [];
  for (const runId of runIds) {
    summaries.push(await summarizeRun(runId, signatures));
  }
  const candidates = await writeSkillCandidates(summaries);
  const overviewObservedAt = summaries
    .map(({ state }) => Date.parse(state.summarized_at || state.created_at || ''))
    .filter(Number.isFinite)
    .sort((a, b) => b - a)[0];
  const overview = {
    schema: 'autodl-agent-runs-overview/v1',
    summarized_at: Number.isFinite(overviewObservedAt) ? new Date(overviewObservedAt).toISOString() : null,
    run_count: summaries.length,
    runs: summaries.map(({ state }) => ({
      run_id: state.run_id,
      repo_name: state.repo_name,
      status: state.status,
      counts: state.counts,
      latest_job: state.latest_job,
    })),
    skill_candidates: candidates.map((filePath) => path.relative(repoRoot, filePath).replaceAll(path.sep, '/')),
  };
  await writeIfChanged(path.join(runsRoot, 'SUMMARY.json'), stableStringify(overview));
  console.log(JSON.stringify(overview, null, 2));
}

main().catch((error) => {
  console.error(error.stack || error.message);
  process.exit(1);
});
