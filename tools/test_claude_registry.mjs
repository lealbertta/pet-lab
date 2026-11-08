import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { classify, watch } from './watch_claude_sessions.mjs';

const session = { version: '2.1.311', kind: 'interactive', pid: 123, sessionId: 'fixture', status: 'busy' };
test('an already-busy live session bootstraps to working without a new event', () => {
  assert.equal(classify(session, true), 'working');
});
test('idle and terminated sessions do not count as working', () => {
  assert.equal(classify({ ...session, status: 'idle' }, true), 'idle');
  assert.equal(classify(session, false), 'retired');
});
test('unknown status, unsupported versions and inaccessible liveness remain uncertain', () => {
  assert.equal(classify({ ...session, status: 'new-status' }, true), 'uncertain');
  assert.equal(classify({ ...session, version: '9.0.0' }, true), 'uncertain');
  assert.equal(classify(session, null), 'uncertain');
});

test('fresh watcher discovers work already in progress and follows its idle transition', async t => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'petlab-registry-'));
  t.after(() => fs.rm(root, { recursive: true, force: true }));
  const registry = path.join(root, 'sessions'); const out = path.join(root, 'events');
  await fs.mkdir(registry);
  const filename = path.join(registry, 'fixture.json');
  const record = { ...session, pid: process.pid, updatedAt: 1, name: 'PRIVATE_NAME', cwd: 'PRIVATE_PATH' };
  await fs.writeFile(filename, JSON.stringify(record));
  const snapshots = [];
  await watch({ registry, out, duration: 0.08, intervalMs: 10, report: async snapshot => {
    snapshots.push(snapshot);
    if (snapshots.length === 1) {
      await fs.writeFile(filename + '.tmp', JSON.stringify({ ...record, status: 'idle', updatedAt: 2 }));
      await fs.rename(filename + '.tmp', filename);
    }
  } });
  assert.equal(snapshots[0].counts.working, 1);
  assert.ok(snapshots.some(snapshot => snapshot.counts.idle === 1));
  const files = (await fs.readdir(out)).filter(name => name.endsWith('.json')).sort();
  const events = await Promise.all(files.map(async name => JSON.parse(await fs.readFile(path.join(out, name), 'utf8'))));
  assert.deepEqual(events.map(event => event.kind), ['sessionStart', 'turnStart', 'idle']);
  assert.ok(!JSON.stringify(events).includes('PRIVATE_'));
});
