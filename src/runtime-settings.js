import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { getAgentHome } from './paths.js';

export const DEFAULT_PROCESS_OUTPUT_LIMIT_MB = 20;
export const PROCESS_OUTPUT_LIMIT_PRESETS_MB = Object.freeze([20, 64, 128, 256]);

export function normalizeProcessOutputLimitMb(value) {
  const numeric = Number(value);
  return PROCESS_OUTPUT_LIMIT_PRESETS_MB.includes(numeric)
    ? numeric
    : DEFAULT_PROCESS_OUTPUT_LIMIT_MB;
}

export async function getRuntimeSettings(env = process.env) {
  const file = path.join(getAgentHome(env), 'runtime-settings.json');
  try {
    const parsed = JSON.parse(await readFile(file, 'utf8'));
    if (!parsed || parsed.schemaVersion !== 1) {
      return { schemaVersion: 1, processOutputLimitMb: DEFAULT_PROCESS_OUTPUT_LIMIT_MB };
    }
    return {
      schemaVersion: 1,
      processOutputLimitMb: normalizeProcessOutputLimitMb(parsed.processOutputLimitMb),
    };
  } catch (error) {
    if (error?.code === 'ENOENT') {
      return { schemaVersion: 1, processOutputLimitMb: DEFAULT_PROCESS_OUTPUT_LIMIT_MB };
    }
    throw new Error(`Could not read runtime-settings.json: ${error?.message ?? error}`);
  }
}

export async function getProcessOutputLimitBytes(env = process.env) {
  const settings = await getRuntimeSettings(env);
  return settings.processOutputLimitMb * 1024 * 1024;
}
