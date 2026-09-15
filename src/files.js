import { createHash, randomUUID } from 'node:crypto';
import { readFile, rename, rm, stat, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { securePath } from './security.js';

export async function sha256File(filePath) {
  return createHash('sha256').update(await readFile(filePath)).digest('hex');
}

export async function readWorkspaceFile(root, relativePath) {
  const target = await securePath(root, relativePath);
  const info = await stat(target);
  if (!info.isFile()) throw new Error('Requested path is not a regular file.');
  if (info.size > 2 * 1024 * 1024) throw new Error('File exceeds the 2 MiB read limit.');
  return { content: await readFile(target, 'utf8'), sha256: await sha256File(target), size: info.size };
}

export async function writeWorkspaceFile(root, relativePath, content, { expectedSha256 = null, create = false } = {}) {
  if (typeof content !== 'string' || content.includes('\0')) throw new Error('Content must be UTF-8 text without NUL bytes.');
  if (Buffer.byteLength(content, 'utf8') > 2 * 1024 * 1024) throw new Error('Content exceeds the 2 MiB write limit.');
  const target = await securePath(root, relativePath, { allowMissingLeaf: create });
  let exists = true;
  try { await stat(target); } catch (error) { if (error?.code === 'ENOENT') exists = false; else throw error; }
  if (create && exists) throw new Error('Target already exists.');
  if (!create && !exists) throw new Error('Target does not exist.');
  if (exists) {
    const current = await sha256File(target);
    if (!expectedSha256 || current !== expectedSha256) throw new Error('Target changed since it was inspected.');
  }
  const temp = path.join(path.dirname(target), `.${path.basename(target)}.${process.pid}.${randomUUID()}.tmp`);
  await writeFile(temp, content, { encoding: 'utf8', flag: 'wx' });
  if (exists) {
    const old = `${target}.${randomUUID()}.old`;
    await rename(target, old);
    try { await rename(temp, target); } catch (error) { await rename(old, target).catch(() => {}); throw error; }
    await rm(old, { force: true });
  } else {
    await rename(temp, target);
  }
  return { sha256: await sha256File(target), size: (await stat(target)).size };
}

export async function deleteWorkspaceFile(root, relativePath, expectedSha256) {
  const target = await securePath(root, relativePath);
  const info = await stat(target);
  if (!info.isFile()) throw new Error('Only regular files can be deleted.');
  const current = await sha256File(target);
  if (current !== expectedSha256) throw new Error('Target changed since it was inspected.');
  await rm(target);
  return current;
}
