import fs from 'node:fs/promises';
import path from 'node:path';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
const execute = promisify(execFile);
// Claude Code 2.x keeps the same session-record format across patch releases, so any 2.x version
// from the first verified one onward is accepted; the record's fields are still validated below.
export const minimumVersion = '2.1.311';
export const supportedVersions = [`>=${minimumVersion} <3.0.0`];
export function isSupportedVersion(version) {
  const parse = v => typeof v === 'string' && /^\d+\.\d+\.\d+$/.test(v) ? v.split('.').map(Number) : null;
  const value = parse(version), minimum = parse(minimumVersion);
  if (!value || value[0] !== minimum[0]) return false;
  for (let i = 1; i < 3; i++) if (value[i] !== minimum[i]) return value[i] > minimum[i];
  return true;
}
const canonical = value => typeof value === 'string' ? value.trim().replace(/\s+/g, ' ') : null;

export function classifyRecord(record, identity) {
  if (!record || !isSupportedVersion(record.version) || record.kind !== 'interactive'
      || typeof record.sessionId !== 'string' || !Number.isSafeInteger(record.pid) || record.pid <= 0) return 'uncertain';
  if (identity === false) return 'retired';
  if (typeof identity !== 'string' || !canonical(record.procStart) || canonical(identity) !== canonical(record.procStart)) return 'uncertain';
  return ({ busy: 'working', idle: 'idle', waiting: 'attention' })[record.status] ?? 'uncertain';
}

export async function processIdentities(pids) {
  if (!pids.length) return new Map();
  let stdout;
  try { ({ stdout } = await execute('/bin/ps', ['-p', [...new Set(pids)].join(','), '-o', 'pid=,lstart='],
    { env: { ...process.env, LC_ALL: 'C', TZ: 'UTC' }, timeout: 3000, maxBuffer: 256 * 1024 })); }
  catch (error) { if (error.code === 1 && typeof error.stdout === 'string') stdout = error.stdout; else return null; }
  const identities = new Map();
  for (const line of stdout.split('\n')) {
    const match = line.match(/^\s*(\d+)\s+(.+)$/);
    if (match) identities.set(Number(match[1]), canonical(match[2]));
  }
  return identities;
}

const processAlive = pid => {
  try { process.kill(pid, 0); return true; } catch (error) { return error.code === 'EPERM'; }
};

/**
 * Wraps processIdentities so `ps` runs only for new PIDs and re-verifies known ones every
 * verifyEveryMs; in between, a cheap signal-0 liveness check catches exited processes.
 * A PID reused within that window can look alive for at most verifyEveryMs.
 */
export function cachedProcessIdentities({ verifyEveryMs = 10000, now = Date.now, alive = processAlive, lookup = processIdentities } = {}) {
  const cache = new Map();
  return async pids => {
    const unique = [...new Set(pids)], time = now(), result = new Map(), stale = [];
    for (const pid of cache.keys()) if (!unique.includes(pid)) cache.delete(pid);
    for (const pid of unique) {
      const known = cache.get(pid);
      if (!known || time - known.checkedAt >= verifyEveryMs) stale.push(pid);
      else if (alive(pid)) result.set(pid, known.identity);
      else cache.delete(pid);
    }
    if (stale.length) {
      const fresh = await lookup(stale);
      if (fresh === null) return null;
      for (const pid of stale) {
        cache.delete(pid);
        if (fresh.has(pid)) { cache.set(pid, { identity: fresh.get(pid), checkedAt: time }); result.set(pid, fresh.get(pid)); }
      }
    }
    return result;
  };
}

export async function readRegistry(registry, previous = [], identify = processIdentities) {
  let names;
  try { names = await fs.readdir(registry); }
  catch (error) {
    if (error.code === 'ENOENT') return { sessions: [], health: 'not-found', rejected: 0 };
    return { sessions: previous.map(s => ({ ...s, activity: 'uncertain' })), health: 'unavailable', rejected: 0 };
  }
  const records = []; let rejected = 0;
  for (const name of names.filter(n => n.endsWith('.json')).slice(0, 512)) {
    try {
      const filename = path.join(registry, name);
      const stat = await fs.lstat(filename);
      if (!stat.isFile() || stat.size > 64 * 1024) { rejected++; continue; }
      const record = JSON.parse(await fs.readFile(filename, 'utf8'));
      if (typeof record.sessionId !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/.test(record.sessionId)) { rejected++; continue; }
      records.push(record);
    } catch { rejected++; }
  }
  const pids = records.map(r => r.pid).filter(p => Number.isSafeInteger(p) && p > 0);
  const identities = await identify(pids);
  const selected = new Map();
  for (const record of records) {
    const activity = classifyRecord(record, identities === null ? null : identities.get(record.pid) ?? false);
    if (activity === 'retired') continue;
    const current = selected.get(record.sessionId);
    const updated = Number.isFinite(record.updatedAt) ? record.updatedAt : 0;
    const title = typeof record.name === 'string' ? record.name.replace(/[\u0000-\u001f\u007f]/g, ' ').trim().slice(0, 160) || null : null;
    if (!current || updated > current.updated) selected.set(record.sessionId,
      { key: `claude:${record.sessionId}`, activity, title, updated });
  }
  if (rejected) for (const old of previous) {
    const id = old.key.replace(/^claude:/, '');
    if (!selected.has(id)) selected.set(id, { ...old, activity: 'uncertain' });
  }
  return { sessions: [...selected.values()].map(({ key, activity, title }) => ({ key, activity, title: title ?? null })),
    health: identities === null ? 'process-check-unavailable' : rejected ? 'partial' : 'ok', rejected };
}

export function activityOf(sessions) {
  for (const state of ['attention', 'working', 'uncertain']) if (sessions.some(s => s.activity === state)) return state;
  return 'idle';
}
