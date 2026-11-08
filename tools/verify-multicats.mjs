import fs from 'node:fs/promises';
import path from 'node:path';
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
const execute = promisify(execFile), root = process.cwd();
const directory = path.join(root, '.lab/multicats-check'), registry = path.join(directory, 'registry'), stateRoot = path.join(directory, 'state');
await fs.mkdir(registry, { recursive: true });
for (const filename of await fs.readdir(registry)) await fs.rm(path.join(registry, filename));
const env = { ...process.env, PET_LAB_STATE_DIR: stateRoot, PET_LAB_CLAUDE_REGISTRY: registry };
delete env.PET_LAB_PACK;
const cli = async (...args) => (await execute(process.execPath, ['bin/pet-lab.mjs', ...args], { env, timeout: 25000 })).stdout;
const status = async () => JSON.parse(await cli('status', '--json'));
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
async function until(predicate, timeout = 15000) {
  let latest; const deadline = Date.now() + timeout;
  while (Date.now() < deadline) { latest = await status(); if (predicate(latest)) return latest; await delay(200); }
  throw new Error('Expected state not reached: ' + JSON.stringify(latest));
}
const { stdout } = await execute('/bin/ps', ['-p', String(process.pid), '-o', 'lstart='], { env: { ...env, TZ: 'UTC', LC_ALL: 'C' } });
async function session(index, activity = 'busy') {
  const record = { version: '2.1.311', kind: 'interactive', sessionId: `fixture-cat-${index}`, pid: process.pid,
    procStart: stdout.trim(), status: activity, name: `Fixture session ${index}`, updatedAt: Date.now() };
  const filename = path.join(registry, `${String(index).padStart(2,'0')}.json`);
  await fs.writeFile(filename+'.tmp', JSON.stringify(record)); await fs.rename(filename+'.tmp', filename);
}
const snapshot = async () => JSON.parse(await fs.readFile(path.join(stateRoot,'snapshot.json'), 'utf8'));
const assignments = snap => new Map(snap.sessions.map(s => [s.key, path.basename(s.pack)]));
const checks = {};
try {
  await cli('stop'); await cli('start');
  const shared = await until(s => s.ready && s.mode === 'shared');
  await cli('-multicats');
  const empty = await until(s => s.ready && s.mode === 'multicats' && s.petCount === 0);
  assert.notEqual(shared.pid, empty.pid); checks.switchesExistingSharedMonitor = true;
  assert.equal(empty.pets.length, 0); checks.noSessionsMeansNoCats = true;
  await session(0); await session(1,'idle'); await session(2);
  let current = await until(s => s.petCount === 3 && s.pets.length === 3 && s.pets.filter(p => p.animation === 'working').length === 2 && s.pets.some(p => p.animation === 'idle'));
  assert.equal(new Set(current.pets.map(p => p.pack)).size, 3);
  assert.ok(current.pets.every(p => p.activityBarVisible && p.barSessionCount === 1 && p.visible), JSON.stringify(current));
  checks.independentCatsAndSessionBars = true;
  const initial = assignments(await snapshot());
  assert.ok(!JSON.stringify(current).includes('Fixture session') && !JSON.stringify(current).includes('fixture-cat'));
  checks.statusOmitsSessionIdentityAndTitle = true;
  await session(0,'idle'); await session(1);
  await until(s => s.pets.find(p => p.pack === initial.get('claude:fixture-cat-1'))?.animation === 'working' && s.pets.find(p => p.pack === initial.get('claude:fixture-cat-0'))?.animation === 'idle');
  assert.deepEqual(assignments(await snapshot()), initial); checks.activityKeepsAssignedCat = true;
  await cli('--multicats'); assert.equal((await status()).pid, empty.pid); checks.repeatStartReusesMonitor = true;
  // Capture real native rendering with fixture-only titles and the same assigned packs.
  await execute(path.join(root,'native/Pet Lab.app/Contents/MacOS/pet-lab'), ['--state-file',path.join(stateRoot,'snapshot.json'),'--multicats','--duration','8','--capture-activity-bar','--output',path.join(root,'evidence/multicats-preview')], { timeout: 20000 });
  for (let i = 3; i < 13; i++) await session(i);
  current = await until(s => s.petCount === 13 && s.pets.length === 13 && s.pets.every(p => p.visible));
  assert.equal(new Set(current.pets.map(p => p.pack)).size,12);
  const counts = [...new Set(current.pets.map(p => p.pack))].map(pack => current.pets.filter(p => p.pack === pack).length);
  assert.equal(Math.max(...counts),2); checks.thirteenSessionsUseAllTwelveBeforeRepeating = true;
  const beforeRemoval = assignments(await snapshot());
  await fs.rm(path.join(registry,'00.json'));
  await until(s => s.petCount === 12);
  const survivors = assignments(await snapshot());
  for(const [key, pack] of survivors) assert.equal(pack,beforeRemoval.get(key));
  checks.departureRetiresOnlyOwnCat = true;
  for(const file of await fs.readdir(registry)) await fs.rm(path.join(registry,file));
  await until(s => s.sessionCount === 0 && s.petCount === 0); checks.removesDepartedCats = true;
  await cli('cat','03'); await until(s => s.ready && s.mode === 'shared' && s.pack === 'cat-03-blue-eyed-white');
  checks.canReturnToSelectedSharedCat = true;
  const report = { passed: true, fixtureOnly: true, checks };
  await fs.writeFile('evidence/multicats-check.json',JSON.stringify(report,null,2)+'\n');
  console.log(JSON.stringify(report,null,2));
} finally { await cli('stop').catch(()=>{}); }
