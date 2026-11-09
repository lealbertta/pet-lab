import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { classifyRecord, readRegistry, activityOf, processIdentities, cachedProcessIdentities } from '../lib/claude-registry.mjs';

const started = 'Fri Nov  6 18:05:13 2026';
const record = { version: '2.1.311', kind: 'interactive', sessionId: 'test', pid: 123, procStart: started, status: 'busy' };
test('process creation identity prevents PID reuse from appearing busy', () => {
  assert.equal(classifyRecord(record, started), 'working');
  assert.equal(classifyRecord(record, 'Fri Nov 6 18:05:14 2026'), 'uncertain');
  assert.equal(classifyRecord(record, false), 'retired');
  assert.equal(classifyRecord({ ...record, version: 'new' }, started), 'uncertain');
});
test('shared pet is idle without sessions and keeps working across idle sessions', () => {
  assert.equal(activityOf([]), 'idle');
  assert.equal(activityOf([{ activity: 'idle' }, { activity: 'working' }]), 'working');
  assert.equal(activityOf([{ activity: 'working' }, { activity: 'attention' }]), 'attention');
});
test('process identity is independent of the launching shell timezone', async () => {
  const previous = process.env.TZ;
  try {
    process.env.TZ = 'America/Toronto';
    const local = await processIdentities([process.pid]);
    process.env.TZ = 'UTC';
    const utc = await processIdentities([process.pid]);
    assert.ok(local?.get(process.pid));
    assert.equal(local.get(process.pid), utc.get(process.pid));
  } finally { if (previous === undefined) delete process.env.TZ; else process.env.TZ = previous; }
});
test('snapshot discovers busy sessions, drops dead records and excludes private metadata', async t => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'petlab-registry-'));
  t.after(() => fs.rm(root, { recursive: true, force: true }));
  await fs.writeFile(path.join(root, 'live.json'), JSON.stringify({ ...record, name: 'Fixture task', cwd: 'PRIVATE_PATH' }));
  await fs.writeFile(path.join(root, 'dead.json'), JSON.stringify({ ...record, sessionId: 'dead', pid: 124 }));
  const snapshot = await readRegistry(root, [], async () => new Map([[123, started]]));
  assert.deepEqual(snapshot.sessions, [{ key: 'claude:test', activity: 'working', title: 'Fixture task' }]);
  assert.equal(snapshot.health, 'ok');
  assert.ok(!JSON.stringify(snapshot).includes('PRIVATE'));
  await fs.writeFile(path.join(root, 'live.json'), '{invalid');
  const lost = await readRegistry(root, snapshot.sessions, async () => new Map());
  assert.equal(lost.sessions[0].activity, 'uncertain');
});
test('desktop app 2.1.317 sessions are classified, and waiting maps to attention', () => {
  assert.equal(classifyRecord({ ...record, version: '2.1.317' }, started), 'working');
  assert.equal(classifyRecord({ ...record, version: '2.1.317', status: 'waiting' }, started), 'attention');
});
test('cached identities call ps only for new or stale PIDs and drop exited processes', async () => {
  let time = 0, lookups = []; const living = new Set([1, 2]);
  const identify = cachedProcessIdentities({ verifyEveryMs: 10000, now: () => time, alive: pid => living.has(pid),
    lookup: async pids => { lookups.push(pids); return new Map(pids.filter(p => living.has(p)).map(p => [p, `start-${p}`])); } });
  assert.deepEqual([...await identify([1, 2])], [[1, 'start-1'], [2, 'start-2']]);
  time = 5000; living.delete(2);
  assert.deepEqual([...await identify([1, 2])], [[1, 'start-1']]);
  assert.equal(lookups.length, 1);
  assert.deepEqual([...await identify([1, 3])].map(([p]) => p), [1]);
  assert.deepEqual(lookups.at(-1), [3]);
  time = 15000;
  await identify([1]);
  assert.deepEqual(lookups.at(-1), [1]);
  lookups = []; const failing = cachedProcessIdentities({ lookup: async () => null });
  assert.equal(await failing([1]), null);
});
