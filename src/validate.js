import { readdir } from 'node:fs/promises';
import path from 'node:path';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';

const execFileAsync = promisify(execFile);
async function walk(root) {
  const out = [];
  for (const entry of await readdir(root, { withFileTypes: true })) {
    const p = path.join(root, entry.name);
    if (entry.isDirectory()) out.push(...await walk(p));
    else if (entry.isFile() && entry.name.endsWith('.js')) out.push(p);
  }
  return out;
}

const srcRoot = path.dirname(new URL(import.meta.url).pathname.replace(/^\/(.:)/, '$1'));
const files = [...await walk(srcRoot), ...await walk(path.resolve('test'))];
for (const file of files) {
  try { await execFileAsync(process.execPath, ['--check', file], { windowsHide: true }); }
  catch (error) { console.error(error.stderr || error.message); process.exit(1); }
}
console.log(`Validated ${files.length} JavaScript files.`);
