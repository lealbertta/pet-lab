// Standalone visual demo: no provider discovery and no changes to the real monitor.
import fs from 'node:fs/promises';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { listCats } from '../lib/cat-packs.mjs';
import { atomicJSON } from '../lib/control.mjs';

const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const count = Number(process.argv[2] ?? 10), seconds = Number(process.argv[3] ?? 300);
if (!Number.isInteger(count) || count < 1 || count > 12 || !Number.isFinite(seconds) || seconds <= 0) {
  throw new Error('Usage: node tools/simulate-cats.mjs COUNT(1–12) SECONDS');
}
const cats = await listCats(root);
for (let i = cats.length-1; i > 0; i--) {
  const j = Math.floor(Math.random()*(i+1)); [cats[i],cats[j]] = [cats[j],cats[i]];
}
if (cats.length < count) throw new Error('Not enough distinct cat packs');
await fs.mkdir(path.join(root,'.lab'), { recursive: true });
const directory = await fs.mkdtemp(path.join(root,'.lab/cat-simulation-'));
const filename = path.join(directory,'snapshot.json');
const sessions = cats.slice(0,count).map((cat,index) => ({ key:`simulation:${index}`, title:`Demo · ${cat.name}`, activity:'working', pack:cat.directory }));
const save = () => atomicJSON(filename,{schemaVersion:1,generation:'simulation',sessions});
await save();
const native = path.join(root,'native/Pet Lab.app/Contents/MacOS/pet-lab');
const child = spawn(native,['--state-file',filename,'--multicats','--pack',cats[0].directory,'--duration',String(seconds),'--parent-pid',String(process.pid),'--output',directory],{stdio:['ignore','inherit','inherit']});
const timer = setInterval(()=>void save().catch(error=>{console.error(error.message);child.kill('SIGTERM')}),1000);
const stop = () => child.kill('SIGTERM');
process.once('SIGTERM',stop);process.once('SIGINT',stop);
child.once('error',error=>{clearInterval(timer);console.error(error.message);process.exitCode=1});
child.once('exit',code=>{clearInterval(timer);process.exitCode=code??0});
console.log(JSON.stringify({simulation:true,cats:count,seconds,output:directory}));
