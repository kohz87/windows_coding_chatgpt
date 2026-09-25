import path from 'node:path';
import { access, copyFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';

const requiredLaunchers = ['Windows-Coding-Agent.cmd', 'Windows-Coding-Agent.ps1'];

async function exists(filePath) {
  try {
    await access(filePath);
    return true;
  } catch {
    return false;
  }
}

export async function ensureLegacyStageCompatibility(root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')) {
  const missing = [];
  for (const name of requiredLaunchers) {
    if (!(await exists(path.join(root, name)))) missing.push(name);
  }
  if (missing.length === 0) return { repaired: false, files: [] };

  const compatibilityRoot = path.join(root, 'scripts');
  for (const name of missing) {
    const source = path.join(compatibilityRoot, `compat-${name}`);
    if (!(await exists(source))) {
      throw new Error(
        `Managed staging is missing ${name}, and the v0.1.9 compatibility payload is unavailable at ${source}.`,
      );
    }
    await copyFile(source, path.join(root, name));
  }

  process.stdout.write(`Repaired legacy managed staging: ${missing.join(', ')}\n`);
  return { repaired: true, files: missing };
}

const invokedDirectly = process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (invokedDirectly) {
  await ensureLegacyStageCompatibility();
}
