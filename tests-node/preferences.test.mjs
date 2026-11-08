import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { readPreferences, saveMulticats } from '../lib/preferences.mjs';

test('mode changes preserve size and behavior, and survive missing or malformed files', async () => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'pet-mode-'));
  const file = path.join(directory,'preferences.json');
  try {
    assert.deepEqual(await readPreferences(file),{});
    await fs.writeFile(file,JSON.stringify({sizeScale:1.5,allowWandering:false,showSessionLabels:true}));
    await saveMulticats(file,true);
    assert.deepEqual(await readPreferences(file),{sizeScale:1.5,allowWandering:false,showSessionLabels:true,multicats:true});
    await saveMulticats(file,false); assert.equal((await readPreferences(file)).multicats,false);
    assert.equal((await fs.stat(file)).mode & 0o777,0o600);
    await fs.writeFile(file,'not json'); await saveMulticats(file,true);
    assert.deepEqual(await readPreferences(file),{multicats:true});
  } finally { await fs.rm(directory,{recursive:true,force:true}); }
});
