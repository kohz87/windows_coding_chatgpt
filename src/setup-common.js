import readline from 'node:readline/promises';
import { stdin as input, stdout as output } from 'node:process';
import path from 'node:path';
import { loadConfig, saveConfig } from './config.js';
import { registerRepository } from './repositories.js';

export function createPrompt() {
  return readline.createInterface({ input, output });
}

export function makeRepositoryId(repositoryPath, existing) {
  const base = path.basename(repositoryPath).toLowerCase().replace(/[^a-z0-9_-]+/g, '-').replace(/^-+|-+$/g, '') || 'repository';
  let id = base;
  let i = 2;
  while (existing[id]) id = `${base}-${i++}`;
  return id;
}

export async function interactiveAddRepository(rl, config = null) {
  config ??= await loadConfig();
  const rawPath = (await rl.question('Repository directory: ')).trim().replace(/^"|"$/g, '');
  if (!rawPath) throw new Error('No repository directory was supplied.');
  const suggested = makeRepositoryId(rawPath, config.repositories);
  const idInput = (await rl.question(`Repository ID [${suggested}]: `)).trim();
  const id = idInput || suggested;
  const allScriptsAnswer = (await rl.question('Allow all package.json scripts, including future additions? [y/N]: ')).trim().toLowerCase();
  const publishAnswer = (await rl.question('Allow guarded fast-forward publication to the configured GitHub branch? [y/N]: ')).trim().toLowerCase();
  const allowAllPackageScripts = allScriptsAnswer === 'y' || allScriptsAnswer === 'yes';
  const repo = await registerRepository(config, id, rawPath, {
    allowedPackageScripts: allowAllPackageScripts ? ['*'] : undefined,
    permissions: { publish: publishAnswer === 'y' || publishAnswer === 'yes' },
  });
  const configPath = await saveConfig(config);
  output.write(`\nAuthorized '${id}'\n  Path: ${repo.path}\n  GitHub: ${repo.github ?? '(no GitHub origin detected)'}\n  Branch: ${repo.defaultBranch}\n  Package manager: ${repo.packageManager ?? 'npm'}\n  Package scripts: ${repo.allowedPackageScripts?.includes('*') ? 'all declared scripts (including future additions)' : (repo.allowedPackageScripts || []).join(', ') || '(none)'}\n  Config: ${configPath}\n\n`);
  return { config, id, repo };
}
