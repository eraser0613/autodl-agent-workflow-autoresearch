import http from 'node:http';
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { getHealth, getRun, getTarget, listRuns, listTargets, readStdout, runStatus } from './harness.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const staticRoot = path.resolve(__dirname, '..', 'public');
const host = '127.0.0.1';
const port = Number(process.env.AUTODL_DECK_PORT || 3766);

const contentTypes = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.svg': 'image/svg+xml; charset=utf-8',
};

function sendJson(response, statusCode, payload) {
  response.writeHead(statusCode, {
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store',
  });
  response.end(JSON.stringify(payload, null, 2));
}

function sendText(response, statusCode, text, contentType = 'text/plain; charset=utf-8') {
  response.writeHead(statusCode, {
    'content-type': contentType,
    'cache-control': 'no-store',
  });
  response.end(text);
}

async function parseJsonBody(request) {
  let raw = '';
  for await (const chunk of request) raw += chunk;
  if (!raw.trim()) return {};
  return JSON.parse(raw);
}

async function serveStatic(requestPath, response) {
  const normalizedPath = requestPath === '/' ? '/index.html' : requestPath;
  const decoded = decodeURIComponent(normalizedPath);
  const filePath = path.normalize(path.join(staticRoot, decoded));

  if (!filePath.startsWith(staticRoot)) {
    sendText(response, 403, 'Forbidden');
    return;
  }

  try {
    const data = await fs.readFile(filePath);
    const ext = path.extname(filePath);
    response.writeHead(200, {
      'content-type': contentTypes[ext] || 'application/octet-stream',
      'cache-control': 'no-cache',
    });
    response.end(data);
  } catch {
    sendText(response, 404, 'Not found');
  }
}

async function routeApi(request, response, url) {
  const segments = url.pathname.split('/').filter(Boolean).map(decodeURIComponent);

  if (request.method === 'GET' && url.pathname === '/api/health') {
    sendJson(response, 200, await getHealth());
    return;
  }

  if (request.method === 'GET' && url.pathname === '/api/targets') {
    sendJson(response, 200, await listTargets());
    return;
  }

  if (request.method === 'GET' && segments[0] === 'api' && segments[1] === 'targets' && segments.length === 3) {
    sendJson(response, 200, await getTarget(segments[2]));
    return;
  }

  if (
    request.method === 'POST' &&
    segments[0] === 'api' &&
    segments[1] === 'targets' &&
    segments[3] === 'status' &&
    segments.length === 4
  ) {
    const body = await parseJsonBody(request);
    sendJson(response, 200, await runStatus(body.lines, segments[2]));
    return;
  }

  if (request.method === 'GET' && url.pathname === '/api/runs') {
    sendJson(response, 200, { runs: await listRuns() });
    return;
  }

  if (request.method === 'GET' && segments[0] === 'api' && segments[1] === 'runs' && segments.length === 3) {
    sendJson(response, 200, await getRun(segments[2]));
    return;
  }

  if (
    request.method === 'GET' &&
    segments[0] === 'api' &&
    segments[1] === 'runs' &&
    segments[3] === 'stdout' &&
    segments.length === 5
  ) {
    sendText(response, 200, await readStdout(segments[2], segments[4]));
    return;
  }

  if (request.method === 'POST' && url.pathname === '/api/status') {
    const body = await parseJsonBody(request);
    sendJson(response, 200, await runStatus(body.lines, body.targetId));
    return;
  }

  sendJson(response, 404, { error: 'Unknown API route' });
}

const server = http.createServer(async (request, response) => {
  try {
    const remote = request.socket.remoteAddress;
    if (!['127.0.0.1', '::1', '::ffff:127.0.0.1'].includes(remote)) {
      sendText(response, 403, 'Local access only');
      return;
    }

    const url = new URL(request.url, `http://${host}:${port}`);
    if (url.pathname.startsWith('/api/')) {
      await routeApi(request, response, url);
      return;
    }

    await serveStatic(url.pathname, response);
  } catch (error) {
    sendJson(response, error.statusCode || 500, {
      error: error.message || 'Internal server error',
    });
  }
});

server.listen(port, host, () => {
  console.log(`AutoDL Control Deck listening on http://${host}:${port}`);
  console.log('Local-only API. Keep Claude Code as the command executor.');
});
