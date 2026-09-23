import { loadConfig, saveConfig } from './config.js';
import { createPrompt, interactiveAddRepository } from './setup-common.js';
import { getConfigPath } from './paths.js';
import { discoverAgentCli, probeAgentCli, validateAgentName } from './agent-cli.js';

function printHeader() {
  console.log('+----------------------------------------------------------+');
  console.log('|              WINDOWS CODING AGENT                      |');
  console.log('|              Repository Manager                        |');
  console.log('+----------------------------------------------------------+');
}

function printAgentCli(config) {
  console.log('');
  console.log('  Coding-agent CLI launchers');
  console.log('  --------------------------------------------------------');
  for (const [name, label] of [['codex', 'Codex CLI'], ['agy', 'Antigravity CLI (agy)']]) {
    const entry = config.agentCli?.[name] ?? { enabled: false, path: '' };
    console.log(`  ${entry.enabled ? '[OK]' : '[--]'} ${label}: ${entry.enabled ? 'enabled' : 'disabled'}`);
    if (entry.path) console.log(`       Path    : ${entry.path}`);
  }
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
    console.log(`       Package : ${repo.packageManager ?? 'npm'}`);
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
    printAgentCli(config);
    console.log('  --------------------------------------------------------');
    console.log('');
    console.log('     [A] Add repository');
    console.log('     [R] Remove authorization');
    console.log('     [P] Toggle GitHub publish');
    console.log('     [C] Toggle coding-agent CLI');
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

    if (answer === 'c') {
      const name = validateAgentName((await rl.question('  Agent CLI [codex/agy]: ')).trim());
      const entry = config.agentCli[name];

      if (entry.enabled) {
        entry.enabled = false;
        await saveConfig(config);
        console.log(`\n  [--] ${name} disabled.`);
      } else {
        const executable = await discoverAgentCli(name);
        if (!executable) throw new Error(`${name} CLI was not found on PATH.`);
        const probe = await probeAgentCli(name, executable);
        if (!probe.available) throw new Error(`${name} CLI could not be started: ${probe.error}`);

        entry.path = executable;
        entry.enabled = true;
        await saveConfig(config);

        console.log(`\n  [OK] ${name} enabled at ${executable}`);
        if (probe.version) console.log(`       Version : ${probe.version}`);
      }

      await rl.question('\n  Press Enter to continue...');
      continue;
    }
  }
} catch (error) {
  console.error(`\n  [X] Repository manager error: ${error.message}`);
  process.exitCode = 1;
} finally {
  rl.close();
}
