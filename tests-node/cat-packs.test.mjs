import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { listCats, findCat, selectedPack } from '../lib/cat-packs.mjs';

test('cat selection is ordered, persistent, and contained in the known library', async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'pet-cats-'));
  try {
    for (const number of ['12', '03']) {
      const directory = path.join(root, 'packs', `cat-${number}-example`);
      await fs.mkdir(directory, { recursive: true });
      await fs.writeFile(path.join(directory, 'manifest.json'), JSON.stringify({ name: `${number} · Example` }));
    }
    assert.deepEqual((await listCats(root)).map(cat => cat.number), ['03', '12']);
    assert.equal((await findCat(root, '3')).number, '03');
    await assert.rejects(findCat(root, '../12'));
    await assert.rejects(findCat(root, '99'));
    assert.equal(await selectedPack(root, root), path.join(root, 'packs/cat-01-calico'));
    await fs.writeFile(path.join(root, 'cat-selection.json'), JSON.stringify({ number: '12' }));
    assert.equal(await selectedPack(root, root), path.join(root, 'packs/cat-12-example'));
    assert.equal(await selectedPack(root, root, '/tmp/custom-pet'), '/tmp/custom-pet');
    await fs.writeFile(path.join(root, 'cat-selection.json'), JSON.stringify({ number: '../../escape' }));
    await assert.rejects(selectedPack(root, root));
  } finally { await fs.rm(root, { recursive: true, force: true }); }
});
