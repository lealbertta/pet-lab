#!/usr/bin/env node
// Read-only feasibility adapter for the locally observed Claude 2.1.311 registry.
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { randomUUID } from 'node:crypto';
import { pathToFileURL } from 'node:url';

export function classify(record, processPresent) {
  if (!record || record.version !== '2.1.311' || record.kind !== 'interactive'
      || typeof record.sessionId !== 'string' || !Number.isSafeInteger(record.pid)) return 'uncertain';
  if (processPresent === false) return 'retired';
  if (processPresent !== true) return 'uncertain';
  if (record.status === 'busy') return 'working';
  if (record.status === 'idle') return 'idle';
  return 'uncertain';
}

function processPresent(pid) {
  if (!Number.isSafeInteger(pid) || pid <= 0) return null;
  try { process.kill(pid, 0); return true; }
  catch (error) { return error.code === 'ESRCH' ? false : null; }
}

async function writeEvent(directory, session, kind) {
  // A fresh queue avoids mixing clocks with other prototype producers.
  const observedNs = Number(process.hrtime.bigint());
  const event = { id: randomUUID(), provider: 'claude-registry', session, kind, observedNs };
  const name = `${String(observedNs).padStart(20, '0')}-${event.id}`;
  await fs.mkdir(directory, { recursive: true, mode: 0o700 });
  const temporary = path.join(directory, `${name}.tmp`);
  await fs.writeFile(temporary, JSON.stringify(event), { mode: 0o600, flag: 'wx' });
  await fs.rename(temporary, path.join(directory, `${name}.json`));
}

export async function watch({ registry, out, duration = 30, evidence, intervalMs = 1000,
  report = snapshot => console.log(JSON.stringify(snapshot)) }) {
  const previous = new Map();
  const snapshots = [];
  const started = Date.now();
  let stopping = false;
  const stop = () => { stopping = true; };
  process.on('SIGINT', stop); process.on('SIGTERM', stop);
  try {
    while (!stopping && Date.now() - started < duration * 1000) {
      let names;
      try { names = await fs.readdir(registry); }
      catch (error) {
        // Losing the registry is not proof that all sessions ended.
        for (const [session, state] of previous) {
          if (state !== 'uncertain') await writeEvent(out, session, 'disconnected');
          previous.set(session, 'uncertain');
        }
        const snapshot = { elapsedSeconds: Math.floor((Date.now() - started)/1000), registryReadable: false, errorCode: error.code };
        snapshots.push(snapshot); await report(snapshot);
        await new Promise(resolve => setTimeout(resolve, intervalMs)); continue;
      }
      const found = new Map();
      let unreadable = false;
      for (const name of names.filter(name => name.endsWith('.json'))) {
        let record;
        try { record = JSON.parse(await fs.readFile(path.join(registry, name), 'utf8')); }
        catch { unreadable = true; continue; }
        if (typeof record.sessionId !== 'string') { unreadable = true; continue; }
        const activity = classify(record, processPresent(record.pid));
        const existing = found.get(record.sessionId);
        if (!existing || (record.updatedAt ?? 0) > existing.updatedAt) {
          found.set(record.sessionId, { activity, updatedAt: record.updatedAt ?? 0 });
        }
      }
      for (const [session, { activity }] of found) {
        if (previous.get(session) !== activity) {
          if (!previous.has(session) || (previous.get(session) === 'retired' && activity !== 'retired')) {
            await writeEvent(out, session, 'sessionStart');
          }
          await writeEvent(out, session, ({ working: 'turnStart', idle: 'idle', retired: 'sessionEnd', uncertain: 'disconnected' })[activity]);
          previous.set(session, activity);
        }
      }
      for (const session of previous.keys()) {
        if (!found.has(session)) {
          const kind = unreadable ? 'disconnected' : 'sessionEnd';
          await writeEvent(out, session, kind);
          if (unreadable) previous.set(session, 'uncertain'); else previous.delete(session);
        }
      }
      const counts = {};
      for (const { activity } of found.values()) counts[activity] = (counts[activity] ?? 0) + 1;
      const snapshot = { elapsedSeconds: Math.floor((Date.now() - started)/1000), registryReadable: true,
        sessionCount: found.size, counts, unreadableRecords: unreadable };
      snapshots.push(snapshot); await report(snapshot);
      await new Promise(resolve => setTimeout(resolve, intervalMs));
    }
  } finally {
    process.off('SIGINT', stop); process.off('SIGTERM', stop);
    if (evidence) {
      await fs.mkdir(path.dirname(evidence), { recursive: true });
      await fs.writeFile(evidence, JSON.stringify({ source: 'Read-only local Claude session registry',
        supportedVersion: '2.1.311', processIdentityVerified: false,
        limitations: ['PID presence checked; PID start identity not yet verified', 'Internal registry format, not a documented compatibility promise',
          'One-second polling can miss transitions shorter than the interval'], snapshots }, null, 2) + '\n');
    }
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  const args = process.argv.slice(2);
  const option = (name, fallback) => { const index = args.indexOf(name); return index >= 0 ? args[index+1] : fallback; };
  const out = option('--out', path.resolve('.lab/registry-events'));
  const duration = Number(option('--duration', '30'));
  if (!Number.isFinite(duration) || duration <= 0) throw new Error('Duration must be positive');
  await watch({ registry: option('--registry', path.join(os.homedir(), '.claude/sessions')), out, duration,
    evidence: option('--evidence', path.resolve('evidence/claude-existing-session-discovery.json')) });
}
