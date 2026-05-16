#!/usr/bin/env node
import { listTargets, runStatus } from '../../web/server/harness.js';

const targetArg = process.argv.find((arg) => arg.startsWith('--target='));
const linesArg = process.argv.find((arg) => arg.startsWith('--lines='));
const targetFilter = targetArg ? targetArg.slice('--target='.length) : '';
const lines = linesArg ? Number(linesArg.slice('--lines='.length)) : 120;

const registry = await listTargets();
const targets = targetFilter ? registry.targets.filter((target) => target.id === targetFilter) : registry.targets;

if (targetFilter && !targets.length) {
  console.error(`Unknown target: ${targetFilter}`);
  process.exit(1);
}

const results = [];
for (const target of targets) {
  const status = await runStatus(lines, target.id);
  results.push({
    target_id: target.id,
    name: target.name,
    host_alias: target.hostAlias,
    health: status.health,
    ok: status.ok,
    exit_code: status.exit_code,
    timed_out: status.timed_out,
    duration_ms: status.duration_ms,
    checked_at: status.targetState?.checked_at,
    failure_hint: status.targetState?.failure_hint || '',
    status_path: `result/targets/${target.id}/status.json`,
  });
}

console.log(JSON.stringify({ schema: 'autodl-agent-target-check/v1', targets: results }, null, 2));
process.exit(results.every((result) => result.ok) ? 0 : 1);
