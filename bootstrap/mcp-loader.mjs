import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const agentHome = process.env.WINDOWS_CODING_AGENT_HOME
  ? path.resolve(process.env.WINDOWS_CODING_AGENT_HOME)
  : path.join(os.homedir(), '.windows-coding-agent');
const versionsRoot = path.resolve(agentHome, 'versions');
const statePath = path.join(agentHome, 'active-version.json');

function insideVersions(candidate) {
  const full = path.resolve(candidate);
  const root = versionsRoot.endsWith(path.sep) ? versionsRoot : versionsRoot + path.sep;
  return full.toLowerCase().startsWith(root.toLowerCase());
}

function usable(candidate) {
  return Boolean(candidate && insideVersions(candidate) && fs.existsSync(path.join(candidate, 'src', 'index.js')));
}

let state;
try {
  state = JSON.parse(fs.readFileSync(statePath, 'utf8'));
} catch (error) {
  console.error('Windows Coding Agent bootstrap could not read active-version.json.');
  console.error('Run Setup.cmd or Update.cmd locally to repair the managed installation.');
  throw error;
}

let root = state.path;
if (!usable(root)) {
  if (usable(state.lastKnownGoodPath)) {
    root = state.lastKnownGoodPath;
    console.error('Windows Coding Agent: active version is unavailable; using last-known-good ' + (state.lastKnownGoodVersion || 'version') + '.');
  } else {
    throw new Error('No valid managed Windows Coding Agent installation is available under ' + versionsRoot);
  }
}

await import(pathToFileURL(path.join(root, 'src', 'index.js')).href);
