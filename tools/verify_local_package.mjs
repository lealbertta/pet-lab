#!/usr/bin/env node
import fs from 'node:fs/promises';
import path from 'node:path';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
const execute = promisify(execFile);
const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const directory = path.join(root, '.lab/package-check');
const registry = path.join(directory, 'registry');
await fs.mkdir(registry, { recursive: true });
for (const filename of await fs.readdir(registry)) await fs.rm(path.join(registry, filename));
const env = { ...process.env, PET_LAB_STATE_DIR: path.join(directory, 'state'), PET_LAB_CLAUDE_REGISTRY: registry };
const cli = async command => JSON.parse((await execute(process.execPath, [path.join(root, 'bin/pet-lab.mjs'), command, '--json'], { env, timeout: 25000 })).stdout);
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
async function until(predicate, timeoutMs = 12000) {
  const deadline = Date.now()+timeoutMs;
  let current;
  while (Date.now()<deadline) { current = await cli('status'); if (predicate(current)) return current; await sleep(150); }
  throw new Error(`Timed out waiting for expected pet state: ${JSON.stringify(current)}`);
}
const { stdout } = await execute('/bin/ps', ['-p', String(process.pid), '-o', 'lstart='], { env: { ...process.env, TZ: 'UTC', LC_ALL: 'C' } });
const record = { version: '2.1.311', kind: 'interactive', sessionId: 'fixture-a', pid: process.pid, procStart: stdout.trim(), status: 'busy', name: 'Fixture task', updatedAt: Date.now() };
async function save(name, value) {
  const file = path.join(registry, `${name}.json`);
  await fs.writeFile(file+'.tmp', JSON.stringify(value)); await fs.rename(file+'.tmp', file);
}
const checks = {};
const measurements = {};
try {
  await cli('stop');
  const starts = await Promise.all(Array.from({ length: 4 }, () => cli('start')));
  assert.equal(new Set(starts.map(s => s.pid)).size, 1);
  checks.concurrentLaunchesUseOneMonitor = true;
  let status = await until(s => s.ready && s.sessionCount === 0 && s.pet?.visible && ['walk', 'idle'].includes(s.pet.animation));
  checks.noSessionsHasOneVisibleIdlePet = true;
  assert.equal(status.pet.activityBarVisible, true);
  assert.equal(status.pet.barSessionCount, 0);
  checks.emptyActivityBarVisible = true;
  assert.equal(status.pet.animation, 'idle', 'Idle roaming starts with a rest');
  const restingX = status.pet.windowX;
  await sleep(1300);
  status = await cli('status');
  assert.equal(status.pet.animation, 'idle');
  assert.equal(status.pet.windowX, restingX);
  checks.idleRestIsStationary = true;
  status = await until(s => s.pet?.animation === 'walk', 55000);
  const idleX = status.pet.windowX;
  await sleep(1500);
  status = await cli('status');
  console.log(JSON.stringify({ idleRoamingCheck: { beforeX: idleX, afterX: status.pet.windowX,
    roaming: status.pet.roaming, animation: status.pet.animation } }));
  measurements.idleWindow = { beforeX: idleX, afterX: status.pet.windowX, waitMs: 1500 };
  assert.ok(Math.abs(status.pet.windowX-idleX) >= 5, 'Idle roaming must move the window, not only play walking frames');
  checks.idleRoamingMovesWindow = true;
  status = await until(s => s.pet?.animation === 'idle');
  checks.shortWalkReturnsToRest = true;
  await save('a', record);
  status = await until(s => s.activity === 'working' && s.pet?.animation === 'working');
  assert.equal(status.pet.barSessionCount, 1);
  assert.equal(status.pet.activityBarVisible, true);
  checks.activityBarTracksSessions = true;
  const frame = status.pet.frameChanges, workingX = status.pet.windowX; await sleep(1300);
  status = await cli('status'); assert.ok(status.pet.frameChanges > frame);
  assert.ok(Math.abs(status.pet.windowX-workingX) < 1, 'Working should animate in place');
  checks.workingAnimationContinues = true;
  await save('b', { ...record, sessionId: 'fixture-b' });
  await until(s => s.counts.working === 2);
  await save('a', { ...record, status: 'idle', updatedAt: Date.now() });
  await until(s => s.counts.working === 1 && s.activity === 'working');
  checks.finishingOneSessionKeepsOtherWorking = true;
  await fs.rm(path.join(registry, 'a.json')); await fs.rm(path.join(registry, 'b.json'));
  status = await until(s => s.sessionCount === 0 && s.activity === 'idle' && s.pet?.visible && s.pet.animation === 'idle');
  checks.removingAllSessionsKeepsIdlePet = true;
  const monitor = status.pid, renderer = status.rendererPid;
  process.kill(monitor, 'SIGKILL');
  let childGone = false;
  for (let i = 0; i < 60; i++) {
    await sleep(100);
    try { process.kill(renderer, 0); } catch (error) { if (error.code === 'ESRCH') { childGone = true; break; } throw error; }
  }
  assert.ok(childGone, 'Renderer must exit when its own monitor dies');
  checks.monitorCrashDoesNotOrphanPet = true;
  status = await cli('start'); assert.notEqual(status.pid, monitor);
  checks.staleSocketAndLockRecover = true;
  await cli('stop'); assert.equal((await cli('status')).running, false);
  checks.stopCleansUp = true;
  await cli('stop'); checks.stopIsIdempotent = true;
  await fs.mkdir(path.join(root, 'evidence'), { recursive: true });
  await fs.writeFile(path.join(root, 'evidence/local-package-check.json'), JSON.stringify({ passed: true, fixtureOnly: true, checks, measurements }, null, 2)+'\n');
  console.log(JSON.stringify({ passed: true, checks }, null, 2));
} finally { await cli('stop').catch(() => {}); }
