import test from 'node:test';
import assert from 'node:assert/strict';
import net from 'node:net';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { pathsFor, request, atomicJSON } from '../lib/control.mjs';

test('runtime control paths are stable and fit Unix socket limits', () => {
  const root = '/tmp/' + 'very-long-directory/'.repeat(15);
  const a = pathsFor(root), b = pathsFor(root);
  assert.equal(a.socket, b.socket); assert.ok(a.socket.length < 100);
});
test('status uses local control endpoint and snapshot replacement is valid JSON', async t => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'petlab-control-'));
  const paths = pathsFor(root);
  const server = net.createServer(socket => socket.once('data', () => socket.end('{"running":true}\n')));
  await new Promise(resolve => server.listen(paths.socket, resolve));
  t.after(async () => { await new Promise(resolve => server.close(resolve)); await fs.rm(root, { recursive: true, force: true }); });
  assert.equal((await request(paths.socket)).running, true);
  await atomicJSON(paths.snapshot, { sessions: [] });
  assert.deepEqual(JSON.parse(await fs.readFile(paths.snapshot, 'utf8')), { sessions: [] });
});
