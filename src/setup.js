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
  console.log('\nSetup complete.');
  console.log('Local management: run Start-Agent.cmd.');
  console.log('Local MCP clients: configure them to run `npm run server`.');
  console.log('ChatGPT: run Connect-ChatGPT.cmd to configure OpenAI Secure MCP Tunnel and follow the custom app steps.');
  console.log('Full ChatGPT guide: docs\\CHATGPT.md');
} catch (error) {
  console.error(`Setup failed: ${error.message}`);
  process.exitCode = 1;
} finally {
  rl.close();
}
