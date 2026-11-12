import fs from 'node:fs';
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
const native='native/Pet Lab.app/Contents/MacOS/pet-lab';
const folders=['shiba-16-red','shiba-17-black-tan','shiba-18-sesame','shiba-19-cream'];
const results=[];
for(const folder of folders){
  const pack='packs/'+folder;
  execFileSync('swift',['-module-cache-path','.build/preview-cache','tools/align-shiba-ground.swift',pack,'--check'],{stdio:'inherit'});
  const validation=JSON.parse(execFileSync(native,['--validate','--pack',pack],{encoding:'utf8'}));
  assert.equal(validation.valid,true); assert.equal(validation.animations,9);
  const output='artifacts/shibas/'+folder+'/native-preview';
  const raw=execFileSync(native,['--pack',pack,'--duration','8','--hold-working','--output',output],{encoding:'utf8',timeout:20000});
  const samples=raw.trim().split('\n').map(line=>JSON.parse(line));
  const work=samples.flatMap(s=>s.pets??[]).filter(p=>p.animation==='working');
  assert.ok(work.length>=2&&work.at(-1).frameChanges>work[0].frameChanges,folder+' must animate');
  assert.ok(work.every(p=>p.visible));
  results.push({folder,validation,workingPlayback:true,samples});
  console.log(folder+': valid, nine animations, working frames advance');
}
fs.writeFileSync('evidence/shiba-library-check.json',JSON.stringify({passed:true,results},null,2)+'\n');
