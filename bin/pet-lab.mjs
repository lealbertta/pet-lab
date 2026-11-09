#!/usr/bin/env node
import fs from 'node:fs/promises';
import { openSync, closeSync } from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { fileURLToPath } from 'node:url';
import { spawn } from 'node:child_process';
import { pathsFor, request, atomicJSON } from '../lib/control.mjs';
import { listCats, findCat, selectedPack } from '../lib/cat-packs.mjs';
import { readPreferences, saveMulticats } from '../lib/preferences.mjs';

const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const args = process.argv.slice(2);
const command = args[0]?.startsWith('-') ? 'start' : args[0] ?? 'start';
const multicats = args.includes('-multicats') || args.includes('--multicats');
const paths = pathsFor();
const nativeExecutable = path.join(root, 'native/Pet Lab.app/Contents/MacOS/pet-lab');
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
const isStopped = error => ['ENOENT', 'ECONNREFUSED'].includes(error.code);
const print = value => {
  if (args.includes('--json')) console.log(JSON.stringify(value));
  else if (!value.running) console.log('Pet Lab is stopped.');
  else console.log(`Pet Lab is ${value.activity === 'attention' ? 'waiting for you' : value.activity}${value.ready ? '' : ' (starting)'} — ${value.sessionCount} Claude session(s)${value.mode === 'multicats' ? ` · ${value.petCount} cats` : ''}.`);
};

async function stopMonitor() {
  try {
    await request(paths.socket, 'stop');
    for (let i = 0; i < 60; i++) {
      await delay(100);
      try { await request(paths.socket); } catch (error) { if (isStopped(error)) return; throw error; }
    }
    throw new Error('Pet Lab has not finished stopping');
  } catch (error) { if (!isStopped(error)) throw error; }
}

try {
  if (args.includes('--help') || command === 'help') {
    console.log('pet-lab             Start or reconnect to the pet\npet-lab -multicats  One random cat per Claude session, unused cats first\npet-lab settings    Open settings (size, wandering, session labels)\npet-lab status      Show pet and Claude session status\npet-lab stop        Stop the monitor and pets\npet-lab cats        List the finished cats\npet-lab cat 03      Return to one selected cat and remember the choice\n\nOptions: --json, -multicats (also --multicats). Environment: PET_LAB_STATE_DIR, PET_LAB_CLAUDE_REGISTRY, PET_LAB_PACK.');
  } else if (command === 'settings') {
    await new Promise((resolve, reject) => {
      const child = spawn(process.execPath, [fileURLToPath(import.meta.url), 'start', ...(multicats ? ['--multicats'] : []), '--json'], { stdio: ['ignore', 'ignore', 'pipe'], env: process.env });
      let errorText = ''; child.stderr.on('data', chunk => { errorText += chunk; });
      child.once('error', reject); child.once('exit', code => code === 0 ? resolve() : reject(new Error(errorText.trim() || 'Could not start Pet Lab')));
    });
    const result = await request(paths.socket, 'settings');
    if (result.error) throw new Error(result.error);
    console.log(args.includes('--json') ? JSON.stringify(result) : 'Opened Pet Lab Settings.');
  } else if (command === 'cats') {
    const cats = (await listCats(root)).map(({ number, name }) => ({ number, name }));
    console.log(args.includes('--json') ? JSON.stringify(cats) : cats.map(cat => `${cat.number}  ${cat.name.replace(/^\d+ · /, '')}`).join('\n'));
  } else if (command === 'cat') {
    const cat = await findCat(root, args[1]);
    await fs.mkdir(paths.root, { recursive: true, mode: 0o700 });
    await atomicJSON(path.join(paths.root, 'cat-selection.json'), { number: cat.number });
    await saveMulticats(path.join(paths.root, 'preferences.json'), false);
    // Use the existing lifecycle commands so switching never creates a second monitor.
    for (const operation of ['stop', 'start']) {
      await new Promise((resolve, reject) => {
        const child = spawn(process.execPath, [fileURLToPath(import.meta.url), operation, ...(args.includes('--json') ? ['--json'] : [])],
          { stdio: 'inherit', env: { ...process.env, PET_LAB_PACK: cat.directory } });
        child.once('error', reject);
        child.once('exit', code => code === 0 ? resolve() : reject(new Error(`Could not ${operation} the selected pet`)));
      });
    }
    if (!args.includes('--json')) console.log(`Selected ${cat.name}.`);
  } else if (command === '_daemon') {
    const { runDaemon } = await import('../lib/daemon.mjs');
    const cats = await listCats(root);
    const saved = await readPreferences(path.join(paths.root, 'preferences.json'));
    const mode = typeof saved.multicats === 'boolean' ? saved.multicats : multicats;
    await runDaemon({ paths, nativeExecutable,
      registry: process.env.PET_LAB_CLAUDE_REGISTRY ?? path.join(os.homedir(), '.claude/sessions'),
      pack: await selectedPack(root, paths.root, process.env.PET_LAB_PACK), cats, multicats: mode });
  } else if (command === 'status') {
    try { print(await request(paths.socket)); }
    catch (error) { if (isStopped(error)) print({ running: false }); else throw error; }
  } else if (command === 'stop') {
    await stopMonitor();
    print({ running: false });
  } else if (command === 'start') {
    if (multicats) {
      await fs.mkdir(paths.root, { recursive: true, mode: 0o700 });
      await saveMulticats(path.join(paths.root, 'preferences.json'), true);
    }
    try {
      const existing = await request(paths.socket);
      if (existing.ready && (!multicats || existing.mode === 'multicats')) { print(existing); process.exit(0); }
      if (multicats && existing.mode !== 'multicats') await stopMonitor();
    } catch (error) { if (!isStopped(error)) throw error; }
    await fs.access(nativeExecutable);
    await fs.mkdir(paths.root, { recursive: true, mode: 0o700 });
    await fs.chmod(paths.root, 0o700);
    try { if ((await fs.stat(paths.log)).size > 1024*1024) await fs.rename(paths.log, `${paths.log}.previous`); } catch {}
    const log = openSync(paths.log, 'a', 0o600);
    const child = spawn(nativeExecutable, ['--lock-run', paths.lock, '--', process.execPath, fileURLToPath(import.meta.url), '_daemon', ...(multicats ? ['--multicats'] : [])],
      { detached: true, stdio: ['ignore', log, log], cwd: root, env: process.env });
    closeSync(log);
    let launchError;
    child.on('error', error => { launchError = error; }); child.unref();
    for (let i = 0; i < 160; i++) {
      if (launchError) throw launchError;
      try {
        const current = await request(paths.socket);
        if (current.ready && (!multicats || current.mode === 'multicats')) { print(current); process.exit(0); }
      } catch (error) { if (!isStopped(error)) throw error; }
      await delay(100);
    }
    const diagnostic = (await fs.readFile(paths.log, 'utf8').catch(() => '')).slice(-1500);
    throw new Error(`Pet Lab did not become ready. ${diagnostic}`);
  } else throw new Error(`Unknown command: ${command}. Use pet-lab --help.`);
} catch (error) {
  const message = error.code === 'ENOENT' && error.path === nativeExecutable ? 'Native app missing. Run npm run build:native first.' : error.message;
  console.error(`Pet Lab: ${message}`); process.exitCode = 1;
}
