import fs from 'node:fs/promises';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { createInterface } from 'node:readline';
import assert from 'node:assert/strict';

const root = process.cwd(), directory = path.join(root,'.lab/cat-transitions');
await fs.mkdir(directory,{recursive:true});
for(const file of await fs.readdir(directory)) if(file.endsWith('.json')) await fs.rm(path.join(directory,file));
const native = path.join(root,'native/Pet Lab.app/Contents/MacOS/pet-lab');
let latest, sequence=0, exited=false;
const samples=[];
async function event(kind) {
  sequence++;
  await fs.writeFile(path.join(directory,`${String(sequence).padStart(3,'0')}.json`),JSON.stringify({id:String(sequence),provider:'fixture',session:'cat',kind,observedNs:sequence}));
}
await event('sessionStart');
const child=spawn(native,['--events',directory,'--per-session','--pack',path.join(root,'packs/cat-01-calico'),'--duration','155','--output',path.join(directory,'preview')],{stdio:['ignore','pipe','pipe']});
let diagnostic='';
child.stderr.on('data',chunk=>{diagnostic=(diagnostic+chunk).slice(-2000)});
child.once('exit',()=>{exited=true});
createInterface({input:child.stdout}).on('line',line=>{try{const value=JSON.parse(line);if(value.pets?.[0]){latest=value.pets[0];samples.push({elapsed:value.elapsed,...latest})}}catch{}});
const delay=ms=>new Promise(resolve=>setTimeout(resolve,ms));
async function until(predicate,timeout=10000){const deadline=Date.now()+timeout;while(Date.now()<deadline){if(latest&&predicate(latest))return latest;if(exited)throw new Error('Renderer exited: '+diagnostic);await delay(100)}throw new Error('Timed out waiting for animation: '+JSON.stringify(latest));}
const checks={};
try {
  await until(p=>p.animation==='spawn');checks.startup=true;
  await event('turnStart');await until(p=>p.animation==='working');checks.workInterruptsStartup=true;
  await event('completed');await until(p=>p.animation==='success');await until(p=>p.animation==='idle');checks.successPlaysOnce=true;
  await event('failed');await until(p=>p.animation==='error');await until(p=>p.animation==='idle');checks.errorRecovers=true;
  await event('idle');
  await until(p=>p.animation==='sleep',130000);checks.sleepsAfterIdle=true;
  await event('turnStart');await until(p=>p.animation==='working');checks.workWakesSleep=true;
  await event('attention');await until(p=>p.animation==='attention');checks.attention=true;
  await event('sessionEnd');await until(p=>p.animation==='retire'&&!p.visible);checks.retirementHidesSession=true;
  assert.equal(Object.keys(checks).length,8);
  await fs.writeFile('evidence/cat-transition-check.json',JSON.stringify({passed:true,fixtureOnly:true,checks,samples},null,2)+'\n');
  console.log(JSON.stringify({passed:true,checks}));
} finally {child.kill('SIGTERM');}
