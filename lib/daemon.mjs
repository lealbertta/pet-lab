import net from 'node:net';
import fs from 'node:fs/promises';
import { fstatSync, statSync } from 'node:fs';
import { spawn } from 'node:child_process';
import { createInterface } from 'node:readline';
import { randomUUID } from 'node:crypto';
import path from 'node:path';
import { readRegistry, activityOf, supportedVersions } from './claude-registry.mjs';
import { atomicJSON } from './control.mjs';
import { CatAssignments } from './cat-assignments.mjs';
import { readPreferences } from './preferences.mjs';

export async function runDaemon({ paths, registry, nativeExecutable, pack, cats = null, multicats = false }) {
  const descriptor = Number(process.env.PET_LAB_LOCK_FD);
  if (!Number.isInteger(descriptor) || descriptor < 3 || fstatSync(descriptor).ino !== statSync(paths.lock).ino) {
    throw new Error('Start the monitor with pet-lab, not the internal daemon command');
  }
  delete process.env.PET_LAB_LOCK_FD;
  let assignments = multicats ? new CatAssignments(cats ?? []) : null;
  await fs.rm(paths.socket, { force: true }); // Only this process holds the OS lock.
  let sessions = [], health = 'starting', renderer = null, renderStatus = null, stopping = false, timer;
  let rendererReady = false, rejectStartup;
  const status = () => ({ running: true, ready: rendererReady, pid: process.pid, rendererPid: renderer?.pid,
    activity: activityOf(sessions), sessionCount: sessions.length,
    counts: sessions.reduce((all, session) => { all[session.activity] = (all[session.activity] ?? 0)+1; return all; }, {}),
    providerHealth: health, supportedClaudeVersions: supportedVersions, mode: assignments ? 'multicats' : 'shared', pack: assignments ? null : path.basename(pack),
    pet: renderStatus?.pets?.[0] ?? null, pets: renderStatus?.pets ?? [], petCount: renderStatus?.petCount ?? renderStatus?.pets?.length ?? 0,
    preferences: renderStatus?.preferences ?? null, settingsVisible: renderStatus?.settingsVisible ?? false,
    menuBarIconVisible: renderStatus?.menuBarIconVisible ?? false,
    codex: 'not-connected' });
  const server = net.createServer(socket => {
    let input = '';
    socket.setTimeout(2000, () => socket.destroy());
    socket.on('error', () => {});
    socket.on('data', chunk => {
      input += chunk;
      if (input.length > 4096) return socket.destroy();
      if (!input.includes('\n')) return;
      try {
        const { op } = JSON.parse(input.split('\n')[0]);
        if (op === 'status') socket.end(JSON.stringify(status())+'\n');
        else if (op === 'settings') {
          if (!rendererReady || !renderer?.kill('SIGUSR1')) socket.end(JSON.stringify({ error: 'Pet renderer is not ready' })+'\n');
          else socket.end(JSON.stringify({ opened: true })+'\n');
        }
        else if (op === 'stop') { socket.end(JSON.stringify({ stopping: true })+'\n'); setImmediate(() => void shutdown()); }
        else socket.end(JSON.stringify({ error: 'Unknown command' })+'\n');
      } catch { socket.destroy(); }
    });
  });
  async function poll() {
    const saved = await readPreferences(path.join(paths.root, 'preferences.json'));
    const wanted = typeof saved.multicats === 'boolean' ? saved.multicats : multicats;
    if (wanted && !assignments) assignments = new CatAssignments(cats ?? []);
    else if (!wanted) assignments = null;
    const snapshot = await readRegistry(registry, sessions);
    sessions = snapshot.sessions; health = snapshot.health;
    await atomicJSON(paths.snapshot, { schemaVersion: 1, generation: randomUUID(), mode: assignments ? 'multicats' : 'shared', sharedPack: pack,
      sessions: assignments ? assignments.reconcile(sessions) : sessions });
  }
  async function shutdown(code = 0) {
    if (stopping) return;
    stopping = true; clearTimeout(timer);
    if (server.listening) server.close();
    if (renderer && renderer.exitCode === null && renderer.signalCode === null) {
      renderer.kill('SIGTERM');
      await Promise.race([new Promise(resolve => renderer.once('exit', resolve)), new Promise(resolve => setTimeout(resolve, 2000))]);
      if (renderer.exitCode === null && renderer.signalCode === null) renderer.kill('SIGKILL');
    }
    await fs.rm(paths.socket, { force: true });
    await fs.rm(paths.snapshot, { force: true });
    process.exit(code);
  }
  process.once('SIGTERM', () => void shutdown()); process.once('SIGINT', () => void shutdown());
  try {
    await poll();
    await new Promise((resolve, reject) => { server.once('error', reject); server.listen(paths.socket, resolve); });
    await fs.chmod(paths.socket, 0o600);
    const ready = new Promise((resolve, reject) => {
      rejectStartup = reject;
      renderer = spawn(nativeExecutable, ['--state-file', paths.snapshot, '--pack', pack, '--duration', '0', '--parent-pid', String(process.pid),
        '--preferences-file', path.join(paths.root, 'preferences.json'),
        ...(assignments ? ['--multicats'] : []),
        '--output', path.join(paths.root, 'previews')], { stdio: ['ignore', 'pipe', 'pipe'] });
      createInterface({ input: renderer.stdout }).on('line', line => {
        try {
          const value = JSON.parse(line);
          if (value.started) { rendererReady = true; resolve(); }
          if (value.pets) renderStatus = value;
        } catch { /* native diagnostic, not a control message */ }
      });
      let errors = '';
      renderer.stderr.on('data', chunk => { errors = (errors + chunk.toString()).slice(-2048); });
      renderer.once('error', reject);
      renderer.once('exit', code => {
        if (!rendererReady) reject(new Error(`Pet window could not start (exit ${code}). ${errors.slice(-500)}`));
        else if (!stopping) void shutdown(code === 0 ? 0 : 1);
      });
    });
    const startupTimer = setTimeout(() => rejectStartup(new Error('Pet window startup timed out')), 12000);
    try { await ready; } finally { clearTimeout(startupTimer); }
    const loop = async () => {
      if (stopping) return;
      try { await poll(); }
      catch { health = 'monitor-error'; }
      if (!stopping) timer = setTimeout(loop, 1000);
    };
    void loop();
  } catch (error) {
    console.error(error.message);
    await shutdown(1);
  }
}
