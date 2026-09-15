import { loadConfig } from './config.js';
import { createPrompt, interactiveAddRepository } from './setup-common.js';
import { getAgentHome } from './paths.js';

console.log('Windows Coding Agent Setup');
console.log('==========================');
console.log(`Local data directory: ${getAgentHome()}`);
console.log('Only directories you explicitly authorize here become visible to MCP clients.\n');

const rl = createPrompt();
try {
  const config = await loadConfig();
  await interactiveAddRepository(rl, config);
  console.log('Setup complete. Run Start-Agent.cmd to manage repositories, or configure an MCP client to run `npm run server`.');
} catch (error) {
  console.error(`Setup failed: ${error.message}`);
  process.exitCode = 1;
} finally {
  rl.close();
}
