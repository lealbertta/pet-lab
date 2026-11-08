import fs from 'node:fs/promises';
import path from 'node:path';

export async function listCats(root) {
  const entries = await fs.readdir(path.join(root, 'packs'), { withFileTypes: true });
  const cats = [];
  for (const entry of entries) {
    if (!entry.isDirectory() || !/^cat-\d{2}-[a-z-]+$/.test(entry.name)) continue;
    const directory = path.join(root, 'packs', entry.name);
    const manifest = JSON.parse(await fs.readFile(path.join(directory, 'manifest.json'), 'utf8'));
    cats.push({ number: entry.name.slice(4, 6), name: manifest.name, directory });
  }
  return cats.sort((a, b) => a.number.localeCompare(b.number));
}

export async function findCat(root, number) {
  if (!/^\d{1,2}$/.test(number ?? '')) throw new Error('Choose a cat number from pet-lab cats');
  const cat = (await listCats(root)).find(cat => cat.number === number.padStart(2, '0'));
  if (!cat) throw new Error(`Cat ${number} is unavailable. Use pet-lab cats.`);
  return cat;
}

export async function selectedPack(root, stateRoot, override) {
  if (override) return path.resolve(override);
  let saved;
  try { saved = JSON.parse(await fs.readFile(path.join(stateRoot, 'cat-selection.json'), 'utf8')); }
  catch (error) { if (error.code === 'ENOENT') return path.join(root, 'packs/cat-01-calico'); throw error; }
  return (await findCat(root, saved.number)).directory;
}
