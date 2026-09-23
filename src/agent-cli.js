import { access } from 'node:fs/promises';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import path from 'node:path';
import { resolveWorkspace } from './workspaces.js';
import { runProcess } from './process.js';

const execFileAsync = promisify(execFile);
const AGENTS = Object.freeze(['codex', 'agy']);
const MODEL = /^[A-Za-z0-9][A-Za-z0-9._:/-]{0,119}$/;

export function validateAgentName(value) {
  const name = String(value ?? '').toLowerCase();
  if (!AGENTS.includes(name)) throw new Error(`Unsupported coding agent '${value}'.`);
  return name;
}

function commandCandidates(agent) {
  if (agent === 'codex') return ['codex.exe', 'codex.cmd', 'codex'];
  return ['agy.exe', 'agy.cmd', 'agy'];
}

export async function discoverAgentCli(agent, env = process.env) {
  const name = validateAgentName(agent);
  const locator = process.platform === 'win32' ? 'where.exe' : 'which';
  for (const candidate of commandCandidates(name)) {
    try {
      const { stdout } = await execFileAsync(locator, [candidate], {
        windowsHide: true,
        timeout: 10_000,
        env,
      });
      const found = String(stdout ?? '').split(/\r?\n/).map((v) => v.trim()).find(Boolean);
      if (found && path.isAbsolute(found)) return found;
    } catch {}
  }
  return null;
}

export async function probeAgentCli(agent, configuredPath = '', env = process.env) {
  const name = validateAgentName(agent);
  const executable = configuredPath || await discoverAgentCli(name, env);
  if (!executable) return { agent: name, available: false, path: '', version: '', error: 'not found' };
  try {
    await access(executable);
    const result = await runProcess(executable, ['--version'], {
      timeout: 20_000,
      maxBuffer: 2 * 1024 * 1024,
      env,
    });
    if (!result.ok) {
      return { agent: name, available: false, path: executable, version: '', error: result.stderr || result.error || 'version probe failed' };
    }
    return {
      agent: name,
      available: true,
      path: executable,
      version: String(result.stdout || result.stderr || '').trim(),
      error: '',
    };
  } catch (error) {
    return { agent: name, available: false, path: executable, version: '', error: error.message };
  }
}

function validatedModel(value) {
  if (value == null || value === '') return null;
  const model = String(value).trim();
  if (!MODEL.test(model)) throw new Error('Invalid model name.');
  return model;
}

export function buildAgentArgs(agent, prompt, options, workspacePath) {
  const model = validatedModel(options.model);
  const effort = options.effort ?? null;
  if (effort != null && !['low', 'medium', 'high'].includes(effort)) throw new Error('Invalid reasoning effort.');

  if (agent === 'codex') {
    const args = ['exec', '--sandbox', 'workspace-write'];
    if (model) args.push('--model', model);
    if (effort) args.push('--config', `model_reasoning_effort="${effort}"`);
    args.push('-');
    return args;
  }

  const args = ['--input-format', 'stream-json', '--output-format', 'stream-json', '--cwd', workspacePath, '--sandbox'];
  if (model) args.push('--model', model);
  if (effort) args.push('--effort', effort);
  return args;
}

export async function agentCliStatus(config, env = process.env) {
  const result = {};
  for (const name of AGENTS) {
    const entry = config.agentCli?.[name] ?? { enabled: false, path: '' };
    const probe = await probeAgentCli(name, entry.path, env);
    result[name] = {
      enabled: Boolean(entry.enabled),
      configuredPath: entry.path || '',
      available: probe.available,
      version: probe.version,
      error: probe.error,
    };
  }
  return result;
}

export async function runAgentCli(config, workspaceId, agent, prompt, options = {}, env = process.env) {
  const name = validateAgentName(agent);
  const entry = config.agentCli?.[name];
  if (!entry?.enabled) throw new Error(`${name} CLI is disabled. Enable it locally in Start-Agent first.`);
  if (!entry.path) throw new Error(`${name} CLI has no locally authorized executable path.`);

  const ws = await resolveWorkspace(config, workspaceId, env);
  const text = String(prompt ?? '').trim();
  if (!text) throw new Error('Agent prompt must not be empty.');
  if (text.length > 100_000) throw new Error('Agent prompt is too large.');

  const probe = await probeAgentCli(name, entry.path, env);
  if (!probe.available) throw new Error(`${name} CLI is unavailable at the locally authorized path: ${probe.error}`);

  const timeoutSeconds = Number.isInteger(options.timeoutSeconds) ? options.timeoutSeconds : 1200;
  if (timeoutSeconds < 30 || timeoutSeconds > 3600) throw new Error('Agent timeout must be between 30 and 3600 seconds.');
  const args = buildAgentArgs(name, text, options, ws.path);

  const input = name === 'codex'
    ? text
    : JSON.stringify({ event: 'user', message: { content: text } }) + '\n';
  const result = await runProcess(entry.path, args, {
    cwd: ws.path,
    timeout: timeoutSeconds * 1000,
    maxBuffer: 20 * 1024 * 1024,
    env,
    input,
  });

  let response = '';
  if (name === 'agy' && result.stdout) {
    for (const line of result.stdout.split(/\r?\n/)) {
      if (!line.trim()) continue;
      try {
        const event = JSON.parse(line);
        if (event?.event === 'result' && typeof event.result?.response === 'string') response = event.result.response;
      } catch {}
    }
  }

  return {
    ok: result.ok,
    agent: name,
    version: probe.version,
    workspaceId,
    exitCode: result.exitCode,
    response: response || (name === 'codex' ? result.stdout.trim() : ''),
    stdout: result.stdout.slice(-500_000),
    stderr: result.stderr.slice(-200_000),
    error: result.error,
  };
}
