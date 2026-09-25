import { loadConfig } from './config.js';
import { createPrompt, interactiveAddRepository } from './setup-common.js';
import { getAgentHome } from './paths.js';

function printHeader() {
  console.log('+----------------------------------------------------------+');
  console.log('|              WINDOWS CODING AGENT                      |');
  console.log('|              Local Repository Setup                    |');
  console.log('+----------------------------------------------------------+');
}

printHeader();
console.log('');
console.log(`  Local data: ${getAgentHome()}`);
console.log('');
console.log('  Only repositories YOU authorize here become visible');
console.log('  to ChatGPT, Codex, or another MCP client.');
console.log('');

const rl = createPrompt();
try {
  const config = await loadConfig();
  await interactiveAddRepository(rl, config);
  console.log('');
  console.log('  +----------------------+');
  console.log('  |    SETUP COMPLETE    |');
  console.log('  +----------------------+');
  console.log('');
  console.log('  Control panel          : Windows-Coding-Agent.cmd');
  console.log('  [3] Local MCP clients  : npm run server');
  console.log('');
  console.log('  Run Windows-Coding-Agent.cmd next for ChatGPT, repositories, diagnostics, or maintenance.');
} catch (error) {
  console.error(`\n  [X] Setup failed: ${error.message}`);
  process.exitCode = 1;
} finally {
  rl.close();
}
