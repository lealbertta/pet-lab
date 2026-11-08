import net from 'node:net';
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import { createHash } from 'node:crypto';

export function pathsFor(directory = process.env.PET_LAB_STATE_DIR ?? path.join(os.homedir(), 'Library/Application Support/Pet Lab')) {
  const root = path.resolve(directory);
  const hash = createHash('sha256').update(root).digest('hex').slice(0, 20);
  return { root, lock: path.join(root, 'instance.lock'), snapshot: path.join(root, 'snapshot.json'),
    socket: path.join('/tmp', `pet-lab-${process.getuid?.() ?? 'user'}-${hash}.sock`), log: path.join(root, 'daemon.log') };
}

export async function atomicJSON(filename, value) {
  const temporary = `${filename}.${process.pid}.tmp`;
  await fs.writeFile(temporary, JSON.stringify(value), { mode: 0o600 });
  await fs.rename(temporary, filename);
}

export function request(socketPath, op = 'status', timeoutMs = 1500) {
  return new Promise((resolve, reject) => {
    const socket = net.createConnection(socketPath); let buffer = '';
    const finish = (error, result) => { socket.destroy(); error ? reject(error) : resolve(result); };
    socket.setTimeout(timeoutMs, () => finish(Object.assign(new Error('Pet Lab control request timed out'), { code: 'ETIMEDOUT' })));
    socket.on('error', error => finish(error));
    socket.on('connect', () => socket.write(JSON.stringify({ op })+'\n'));
    socket.on('data', chunk => {
      buffer += chunk;
      if (buffer.length > 65536) return finish(new Error('Invalid control response'));
      if (buffer.includes('\n')) {
        try { finish(null, JSON.parse(buffer.split('\n')[0])); } catch (error) { finish(error); }
      }
    });
  });
}
