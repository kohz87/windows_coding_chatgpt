import { loadConfig, saveConfig } from './config.js';
import { createPrompt, interactiveAddRepository } from './setup-common.js';
import { getConfigPath } from './paths.js';

function printRepositories(config) {
  const entries = Object.entries(config.repositories);
  console.log('\nAuthorized repositories');
  console.log('-----------------------');
  if (!entries.length) console.log('(none)');
  for (const [id, repo] of entries) {
    console.log(`${id}\n  ${repo.path}\n  GitHub: ${repo.github ?? '(local only)'}\n  Publish: ${repo.permissions.publish ? 'enabled, fast-forward only' : 'disabled'}`);
  }
}

const rl = createPrompt();
try {
  let config = await loadConfig();
  while (true) {
    console.clear?.();
    console.log('Windows Coding Agent');
    console.log(`Config: ${getConfigPath()}`);
    printRepositories(config);
    console.log('\n[A] Add repository  [R] Remove repository  [P] Toggle publish  [Q] Quit');
    const answer = (await rl.question('> ')).trim().toLowerCase();
    if (!answer || answer === 'q') break;
    if (answer === 'a') {
      ({ config } = await interactiveAddRepository(rl, config));
      await rl.question('Press Enter to continue...');
      continue;
    }
    if (answer === 'r') {
      const id = (await rl.question('Repository ID to remove: ')).trim();
      if (!config.repositories[id]) throw new Error(`Unknown repository '${id}'.`);
      delete config.repositories[id];
      await saveConfig(config);
      continue;
    }
    if (answer === 'p') {
      const id = (await rl.question('Repository ID: ')).trim();
      const repo = config.repositories[id];
      if (!repo) throw new Error(`Unknown repository '${id}'.`);
      repo.permissions.publish = !repo.permissions.publish;
      await saveConfig(config);
      continue;
    }
  }
} catch (error) {
  console.error(`Startup manager error: ${error.message}`);
  process.exitCode = 1;
} finally {
  rl.close();
}
