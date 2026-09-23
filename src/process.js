import { spawn } from 'node:child_process';
import path from 'node:path';

const BATCH_BRIDGE = [
  "$ErrorActionPreference = 'Stop'",
  "$exe = $env:WCA_BATCH_EXECUTABLE",
  "$json = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($env:WCA_BATCH_ARGS_B64))",
  "$argv = @((ConvertFrom-Json -InputObject $json))",
  "& $exe @argv",
  "if ($null -ne $LASTEXITCODE) { exit $LASTEXITCODE }",
].join('; ');

function commandFor(executable, args, env) {
  if (process.platform !== 'win32' || !/\.(?:cmd|bat)$/i.test(executable)) {
    return { executable, args, env };
  }
  const powershell = env.SystemRoot
    ? path.join(env.SystemRoot, 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe')
    : 'powershell.exe';
  return {
    executable: powershell,
    args: ['-NoProfile', '-NonInteractive', '-Command', BATCH_BRIDGE],
    env: {
      ...env,
      WCA_BATCH_EXECUTABLE: executable,
      WCA_BATCH_ARGS_B64: Buffer.from(JSON.stringify(args), 'utf8').toString('base64'),
    },
  };
}

function terminateProcessTree(child) {
  if (!child?.pid) return;
  if (process.platform === 'win32') {
    try {
      const killer = spawn('taskkill.exe', ['/PID', String(child.pid), '/T', '/F'], {
        windowsHide: true,
        stdio: 'ignore',
      });
      killer.unref?.();
      return;
    } catch {}
  }
  try { child.kill(); } catch {}
}

export async function runProcess(executable, args, options = {}) {
  const env = options.env ?? process.env;
  const bridged = commandFor(executable, args, env);
  const timeout = options.timeout ?? 120_000;
  const maxBuffer = options.maxBuffer ?? 20 * 1024 * 1024;
  const input = options.input ?? null;

  return new Promise((resolve) => {
    let settled = false;
    let stdout = '';
    let stderr = '';
    let buffered = 0;
    let timer = null;

    const finish = (result) => {
      if (settled) return;
      settled = true;
      if (timer) clearTimeout(timer);
      resolve(result);
    };

    let child;
    try {
      child = spawn(bridged.executable, bridged.args, {
        cwd: options.cwd,
        env: bridged.env,
        windowsHide: true,
        shell: false,
        stdio: ['pipe', 'pipe', 'pipe'],
      });
    } catch (error) {
      finish({ ok: false, exitCode: -1, stdout, stderr, error: error.message });
      return;
    }

    const append = (kind, chunk) => {
      const text = String(chunk ?? '');
      buffered += Buffer.byteLength(text);
      if (buffered > maxBuffer) {
        stderr += '\nProcess output exceeded controller buffer limit.';
        terminateProcessTree(child);
        return;
      }
      if (kind === 'stdout') stdout += text;
      else stderr += text;
    };

    child.stdout.on('data', (chunk) => append('stdout', chunk));
    child.stderr.on('data', (chunk) => append('stderr', chunk));
    child.on('error', (error) => finish({ ok: false, exitCode: -1, stdout, stderr, error: error.message }));
    child.on('close', (code, signal) => {
      finish({
        ok: code === 0 && buffered <= maxBuffer,
        exitCode: typeof code === 'number' ? code : -1,
        stdout,
        stderr,
        signal: signal ?? null,
        error: code === 0 ? null : `Process exited with code ${code ?? 'unknown'}`,
      });
    });

    timer = setTimeout(() => {
      stderr += `\nProcess timed out after ${timeout} ms.`;
      terminateProcessTree(child);
    }, timeout);
    timer.unref?.();

    if (input != null) child.stdin.end(String(input));
    else child.stdin.end();
  });
}
