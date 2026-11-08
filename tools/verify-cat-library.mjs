import fs from 'node:fs/promises';
import path from 'node:path';
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { listCats } from '../lib/cat-packs.mjs';
const execute = promisify(execFile), root = process.cwd();
const native = path.join(root, 'native/Pet Lab.app/Contents/MacOS/pet-lab');
const cats = await listCats(root);
assert.deepEqual(cats.map(cat => cat.number), ['01','02','03','04','07','08','09','11','12','13','14','15']);
const results = [];
for (const cat of cats) {
  const { stdout } = await execute(native, ['--validate','--pack',cat.directory]);
  const validation = JSON.parse(stdout.trim());
  assert.equal(validation.valid, true); assert.equal(validation.animations, 9);
  const folder = path.basename(cat.directory), output = path.join(root,'artifacts/cats',folder,'native-preview');
  const { stdout: samples } = await execute(native, ['--pack',cat.directory,'--duration','8','--hold-working','--output',output], { timeout: 20000 });
  const values = samples.trim().split('\n').map(line => JSON.parse(line));
  const work = values.flatMap(value => value.pets ?? []).filter(pet => pet.animation === 'working');
  assert.ok(work.length >= 2 && work.at(-1).frameChanges > work[0].frameChanges, `${cat.name} must animate in native renderer`);
  assert.ok(work.every(pet => pet.visible));
  await fs.access(path.join(output,'pet-1-working.png'));
  results.push({ number: cat.number, name: cat.name, validation, workingPlayback: true, capture: path.relative(root,path.join(output,'pet-1-working.png')) });
  console.log(`${cat.name}: valid and animated`);
}
await fs.writeFile('evidence/cat-library-check.json', JSON.stringify({ passed:true, cats:results, animations:108 },null,2)+'\n');
console.log('All twelve packs passed native validation and working playback.');
