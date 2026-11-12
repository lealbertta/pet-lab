#!/usr/bin/env node
import path from 'node:path';
import fs from 'node:fs/promises';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const packageInfo = JSON.parse(await fs.readFile(path.join(root, 'package.json'), 'utf8'));
if (process.platform !== 'darwin') throw new Error('Pet Lab currently requires macOS');
await fs.mkdir(path.join(root, '.build/clang-module-cache'), { recursive: true });
const environment = { ...process.env, CLANG_MODULE_CACHE_PATH: path.join(root, '.build/clang-module-cache') };
const common = ['--configuration', 'release', '--disable-sandbox', '--cache-path', '.build/cache', '--config-path', '.build/config', '--security-path', '.build/security'];
let result = spawnSync('swift', ['build', ...common], { cwd: root, stdio: 'inherit', env: environment });
if (result.status !== 0) process.exit(result.status ?? 1);
result = spawnSync('swift', ['build', ...common, '--show-bin-path'], { cwd: root, encoding: 'utf8', env: environment });
if (result.status !== 0) throw new Error(result.stderr);
const binaryDirectory = result.stdout.trim().split('\n').at(-1);
const app = path.join(root, 'native/Pet Lab.app/Contents');
await fs.mkdir(path.join(app, 'MacOS'), { recursive: true });
await fs.mkdir(path.join(app, 'Resources'), { recursive: true });
// Replace rather than overwrite: macOS caches a binary's signature by file, and an in-place
// overwrite of a recently run binary gets killed at launch with "Code Signature Invalid".
await fs.rm(path.join(app, 'MacOS/pet-lab'), { force: true });
await fs.copyFile(path.join(binaryDirectory, 'pet-lab'), path.join(app, 'MacOS/pet-lab'));
await fs.chmod(path.join(app, 'MacOS/pet-lab'), 0o755);
await fs.cp(path.join(root, 'packs/starter'), path.join(app, 'Resources/packs/starter'), { recursive: true });
await fs.writeFile(path.join(app, 'Info.plist'), `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.petlab.companion</string>
<key>CFBundleName</key><string>Pet Lab</string><key>CFBundleExecutable</key><string>pet-lab</string>
<key>CFBundlePackageType</key><string>APPL</string><key>CFBundleShortVersionString</key><string>${packageInfo.version}</string>
<key>LSUIElement</key><true/><key>NSHighResolutionCapable</key><true/>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSAppleEventsUsageDescription</key><string>Pet Lab switches Terminal or iTerm to the tab running the Claude session you open.</string>
</dict></plist>\n`);
console.log(`Built ${path.dirname(app)}`);
