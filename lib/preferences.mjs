import fs from 'node:fs/promises';
import { atomicJSON } from './control.mjs';

export async function readPreferences(filename) {
  try {
    const data = await fs.readFile(filename, 'utf8');
    if (Buffer.byteLength(data) > 4096) return {};
    const value = JSON.parse(data);
    return value && typeof value === 'object' && !Array.isArray(value) ? value : {};
  } catch (error) {
    if (error.code === 'ENOENT' || error instanceof SyntaxError) return {};
    throw error;
  }
}

export async function saveMulticats(filename, enabled) {
  const preferences = await readPreferences(filename);
  await atomicJSON(filename, { ...preferences, multicats: enabled });
}
