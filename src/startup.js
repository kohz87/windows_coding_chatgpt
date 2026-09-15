import { loadConfig, saveConfig } from './config.js';
import { createPrompt, interactiveAddRepository } from './setup-common.js';
import { getConfigPath } from './paths.js';

function printHeader() {
  console.log('+----------------------------------------------------------+');
  console.log('|              WINDOWS CODING AGENT                      |');
  console.log('|              Repository Manager                        |');
  console.log('+----------------------------------------------------------+');
}

function printRepositories(config) {
  const entries = Object.entries(config.repositories);
  console.log('');
  console.log('  Authorized repositories');
  console.log('  --------------------------------------------------------');
  if (!entries.length) {
    console.log('  [--] None configured');
    return;
  }
  for (const [id, repo] of entries) {
    const publish = repo.permissions.publish ? '[OK] fast-forward only' : '[--] disabled';
    console.log(`  [OK] ${id}`);
    console.log(`       Path    : ${repo.path}`);
    console.log(`       GitHub  : ${repo.github ?? '(local only)'}`);
    console.log(`       Publish : ${publish}`);
    console.log('');
  }
}

const rl = createPrompt();
try {
  let config = await loadConfig();
  while (true) {
    console.clear?.();
    printHeader();
    console.log(`\n  Config: ${getConfigPath()}`);
    printRepositories(config);
    console.log('  --------------------------------------------------------');
    console.log('');
    console.log('     [A] Add repository');
    console.log('     [R] Remove authorization');
    console.log('     [P] Toggle GitHub publish');
    console.log('     [Q] Quit');
    console.log('');
    const answer = (await rl.question('  Select > ')).trim().toLowerCase();
    if (!answer || answer === 'q') break;
    if (answer === 'a') {
      ({ config } = await interactiveAddRepository(rl, config));
      await rl.question('\n  Press Enter to continue...');
      continue;
    }
    if (answer === 'r') {
      const id = (await rl.question('  Repository ID to remove: ')).trim();
      if (!config.repositories[id]) throw new Error(`Unknown repository '${id}'.`);
      delete config.repositories[id];
      await saveConfig(config);
      continue;
    }
    if (answer === 'p') {
      const id = (await rl.question('  Repository ID: ')).trim();
      const repo = config.repositories[id];
      if (!repo) throw new Error(`Unknown repository '${id}'.`);
      repo.permissions.publish = !repo.permissions.publish;
      await saveConfig(config);
      continue;
    }
  }
} catch (error) {
  console.error(`\n  [X] Repository manager error: ${error.message}`);
  process.exitCode = 1;
} finally {
  rl.close();
}
