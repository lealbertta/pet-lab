import fs from 'node:fs';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { listCats } from '../lib/cat-packs.mjs';

const native = 'native/Pet Lab.app/Contents/MacOS/pet-lab';
execFileSync('swiftc', ['-O', '-module-cache-path', '.build/preview-cache', 'tools/check-dog-registration.swift', '-o', '.build/check-dog-registration'], { stdio: 'inherit' });
execFileSync('.build/check-dog-registration', [], { stdio: 'inherit' });
const dogs = (await listCats('.')).filter(pet => pet.directory.split('/').at(-1).startsWith('dog-'));
assert.equal(dogs.length, 4);
const results = [];
for (const dog of dogs) {
  const validation = JSON.parse(execFileSync(native, ['--validate', '--pack', dog.directory], { encoding: 'utf8' }));
  assert.equal(validation.valid, true);
  assert.equal(validation.animations, 9);
  assert.equal(validation.referencedFrames, 72);
  const output = `artifacts/dogs/${dog.directory.split('/').at(-1)}/native-preview`;
  const raw = execFileSync(native, ['--pack', dog.directory, '--duration', '8', '--hold-working', '--output', output], { encoding: 'utf8', timeout: 20000 });
  const samples = raw.trim().split('\n').map(line => JSON.parse(line));
  const working = samples.flatMap(sample => sample.pets ?? []).filter(pet => pet.animation === 'working');
  assert.ok(working.length >= 2 && working.at(-1).frameChanges > working[0].frameChanges, `${dog.name}: working frames must advance`);
  assert.ok(working.every(pet => pet.visible));
  results.push({ name: dog.name, validation, workingPlayback: true, samples });
  console.log(`${dog.name}: valid; nine states; working playback advances`);
}
fs.mkdirSync('evidence', { recursive: true });
fs.writeFileSync('evidence/dog-library-check.json', JSON.stringify({ passed: true, results }, null, 2) + '\n');
