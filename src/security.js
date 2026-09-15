import path from 'node:path';
import { realpath, stat } from 'node:fs/promises';

const WINDOWS_DEVICE_NAME = /^(CON|PRN|AUX|NUL|CLOCK\$|COM[1-9]|LPT[1-9])$/i;

export function validateRepositoryId(value) {
  if (typeof value !== 'string' || !/^[a-z0-9][a-z0-9_-]{0,63}$/i.test(value)) {
    throw new Error('Repository ID must contain only letters, numbers, underscores, and hyphens.');
  }
  return value;
}

export function validateWorkspaceId(value) {
  if (typeof value !== 'string' || !/^[a-z0-9][a-z0-9_-]{0,127}$/i.test(value)) {
    throw new Error('Invalid workspace ID.');
  }
  return value;
}

export function validateRelativePath(relativePath, { allowDot = false } = {}) {
  if (typeof relativePath !== 'string' || relativePath.includes('\0')) throw new Error('Invalid relative path.');
  const raw = relativePath.trim();
  if (!raw) throw new Error('Relative path must not be empty.');
  if (/^[A-Za-z]:/.test(raw) || raw.startsWith('\\\\') || raw.startsWith('//') || raw.startsWith('/') || raw.startsWith('\\')) {
    throw new Error('Absolute, UNC, and device paths are forbidden.');
  }
  const normalized = raw.replace(/\//g, path.sep).replace(/\\/g, path.sep);
  if (normalized === '.') {
    if (allowDot) return normalized;
    throw new Error('A concrete path is required.');
  }
  for (const segment of normalized.split(path.sep)) {
    if (!segment || segment === '.' || segment === '..') throw new Error('Traversal and empty path segments are forbidden.');
    if (segment.includes(':')) throw new Error('Alternate data streams and drive-qualified segments are forbidden.');
    if (segment.endsWith('.') || segment.endsWith(' ')) throw new Error('Trailing dot/space aliases are forbidden.');
    if (segment.toLowerCase() === '.git') throw new Error('Direct .git access is forbidden.');
    if (WINDOWS_DEVICE_NAME.test(segment.split('.')[0])) throw new Error(`Windows device path segment '${segment}' is forbidden.`);
  }
  return normalized;
}

export function assertPathInside(root, target) {
  const rootResolved = path.resolve(root);
  const targetResolved = path.resolve(target);
  const rel = path.relative(rootResolved, targetResolved);
  if (rel === '') return;
  if (rel.startsWith('..') || path.isAbsolute(rel)) throw new Error('Path escapes the allowed root.');
}

export async function securePath(root, relativePath, { allowMissingLeaf = false, allowDot = false } = {}) {
  const normalized = validateRelativePath(relativePath, { allowDot });
  const rootReal = await realpath(root);
  const candidate = path.resolve(rootReal, normalized);
  assertPathInside(rootReal, candidate);
  if (allowMissingLeaf) {
    try {
      const targetReal = await realpath(candidate);
      assertPathInside(rootReal, targetReal);
      return targetReal;
    } catch (error) {
      if (error?.code !== 'ENOENT') throw error;
      const parentReal = await realpath(path.dirname(candidate));
      assertPathInside(rootReal, parentReal);
      return candidate;
    }
  }
  const targetReal = await realpath(candidate);
  assertPathInside(rootReal, targetReal);
  return targetReal;
}

export async function assertDirectory(directory) {
  const info = await stat(directory);
  if (!info.isDirectory()) throw new Error(`Not a directory: ${directory}`);
  return directory;
}
