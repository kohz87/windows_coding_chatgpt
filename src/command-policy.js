import path from 'node:path';
import { validateRelativePath } from './security.js';

const SAFE_GIT_REF = /^[A-Za-z0-9][A-Za-z0-9._/-]{0,199}$/;
const FULL_GIT_SHA = /^(?:[a-f0-9]{40}|[a-f0-9]{64})$/i;
const NPM_NAME = /^(?:@[a-z0-9][a-z0-9._-]*\/[a-z0-9][a-z0-9._-]*|[a-z0-9][a-z0-9._-]*)$/i;
const NPM_SELECTOR = /^[A-Za-z0-9*^~<>=|.+_-]+$/;
const NPM_FIELD = /^[A-Za-z0-9_.-]+$/;

export const SAFE_GIT_OPERATIONS = Object.freeze([
  'status',
  'diff',
  'log',
  'show',
  'ls_files',
  'branch_list',
  'tag_list',
  'fetch',
  'pull_ff',
  'restore',
  'restore_staged',
  'cherry_pick_no_commit',
  'cherry_pick_abort',
  'revert_no_commit',
  'revert_abort',
]);

export const SAFE_NPM_OPERATIONS = Object.freeze([
  'ci',
  'install',
  'install_packages',
  'uninstall_packages',
  'update',
  'dedupe',
  'prune',
  'audit',
  'audit_fix',
  'outdated',
  'list',
  'view',
]);

export function validateSafeGitRef(value) {
  const ref = String(value ?? '').trim();
  if (!ref || ref.startsWith('-') || !SAFE_GIT_REF.test(ref)) throw new Error('Invalid Git ref.');
  if (ref.includes('..') || ref.includes('@{') || ref.includes('//') || ref.endsWith('/') || ref.endsWith('.') || ref.endsWith('.lock')) {
    throw new Error('Unsafe Git ref syntax is forbidden.');
  }
  return ref;
}

export function validateFullGitSha(value) {
  const sha = String(value ?? '').trim();
  if (!FULL_GIT_SHA.test(sha)) throw new Error('A full Git commit SHA is required.');
  return sha;
}

export function validateGitPaths(values, { defaultDot = false } = {}) {
  const items = Array.isArray(values) ? values : [];
  if (items.length > 100) throw new Error('Too many Git paths.');
  const effective = items.length ? items : (defaultDot ? ['.'] : []);
  return effective.map((value) => validateRelativePath(value, { allowDot: true }).split(path.sep).join('/'));
}

export function validateNpmPackageSpec(value) {
  const spec = String(value ?? '').trim();
  if (!spec || spec.startsWith('-') || /[\s\\:#?]/.test(spec)) throw new Error(`Unsafe npm package spec '${spec}' is forbidden.`);

  let name = spec;
  let selector = '';
  if (spec.startsWith('@')) {
    const slash = spec.indexOf('/');
    if (slash < 2) throw new Error(`Invalid npm package spec '${spec}'.`);
    const selectorAt = spec.indexOf('@', slash + 1);
    if (selectorAt >= 0) {
      name = spec.slice(0, selectorAt);
      selector = spec.slice(selectorAt + 1);
    }
  } else {
    const selectorAt = spec.indexOf('@');
    if (selectorAt >= 0) {
      name = spec.slice(0, selectorAt);
      selector = spec.slice(selectorAt + 1);
    }
  }

  if (!NPM_NAME.test(name)) throw new Error(`Invalid npm package name '${name}'.`);
  if (selector && !NPM_SELECTOR.test(selector)) throw new Error(`Unsafe npm selector '${selector}' is forbidden.`);
  return spec;
}

export function buildGitOperationArgs(operation, options = {}) {
  if (!SAFE_GIT_OPERATIONS.includes(operation)) throw new Error(`Unsupported Git operation '${operation}'.`);
  const paths = validateGitPaths(options.paths, { defaultDot: false });

  switch (operation) {
    case 'status':
      return ['status', '--short', '--branch'];
    case 'diff': {
      const args = ['diff', '--no-ext-diff'];
      if (options.staged) args.push('--cached');
      if (options.ref) args.push(validateSafeGitRef(options.ref));
      if (paths.length) args.push('--', ...paths);
      return args;
    }
    case 'log': {
      const maxCount = Number.isInteger(options.maxCount) ? options.maxCount : 30;
      if (maxCount < 1 || maxCount > 200) throw new Error('Git log maxCount must be between 1 and 200.');
      const args = ['log', `--max-count=${maxCount}`, '--decorate=short', '--oneline'];
      if (options.ref) args.push(validateSafeGitRef(options.ref));
      return args;
    }
    case 'show':
      return ['show', '--no-ext-diff', '--stat', '--oneline', '--decorate=short', validateSafeGitRef(options.ref ?? 'HEAD')];
    case 'ls_files':
      return ['ls-files', ...(paths.length ? ['--', ...paths] : [])];
    case 'branch_list':
      return ['branch', '--list', '-vv'];
    case 'tag_list':
      return ['tag', '--list'];
    case 'restore':
      return ['restore', '--worktree', '--', ...validateGitPaths(options.paths, { defaultDot: true })];
    case 'restore_staged':
      return ['restore', '--staged', '--', ...validateGitPaths(options.paths, { defaultDot: true })];
    case 'cherry_pick_no_commit':
      return ['cherry-pick', '--no-commit', validateFullGitSha(options.ref)];
    case 'cherry_pick_abort':
      return ['cherry-pick', '--abort'];
    case 'revert_no_commit':
      return ['revert', '--no-commit', validateFullGitSha(options.ref)];
    case 'revert_abort':
      return ['revert', '--abort'];
    default:
      return null;
  }
}

export function buildNpmOperationArgs(operation, options = {}) {
  if (!SAFE_NPM_OPERATIONS.includes(operation)) throw new Error(`Unsupported npm operation '${operation}'.`);
  const packages = (options.packages ?? []).map(validateNpmPackageSpec);
  if (packages.length > 50) throw new Error('Too many npm package specs.');

  switch (operation) {
    case 'ci':
      if (packages.length) throw new Error('npm ci does not accept package specs here.');
      return ['ci', '--ignore-scripts'];
    case 'install':
      if (packages.length) throw new Error('Use install_packages when package specs are supplied.');
      return ['install', '--ignore-scripts'];
    case 'install_packages': {
      if (!packages.length) throw new Error('install_packages requires at least one package.');
      const args = ['install', '--ignore-scripts'];
      if (options.dev) args.push('--save-dev');
      if (options.exact) args.push('--save-exact');
      args.push(...packages);
      return args;
    }
    case 'uninstall_packages':
      if (!packages.length) throw new Error('uninstall_packages requires at least one package.');
      return ['uninstall', '--ignore-scripts', ...packages];
    case 'update':
      return ['update', '--ignore-scripts', ...packages];
    case 'dedupe':
      if (packages.length) throw new Error('npm dedupe does not accept package specs here.');
      return ['dedupe', '--ignore-scripts'];
    case 'prune':
      if (packages.length) throw new Error('npm prune does not accept package specs here.');
      return ['prune', '--ignore-scripts'];
    case 'audit':
      return ['audit'];
    case 'audit_fix':
      return ['audit', 'fix', '--ignore-scripts'];
    case 'outdated':
      return ['outdated', '--long'];
    case 'list': {
      const depth = Number.isInteger(options.depth) ? options.depth : 0;
      if (depth < 0 || depth > 10) throw new Error('npm list depth must be between 0 and 10.');
      return ['list', `--depth=${depth}`];
    }
    case 'view': {
      if (packages.length !== 1) throw new Error('npm view requires exactly one package.');
      const args = ['view', packages[0]];
      if (options.field != null) {
        const field = String(options.field).trim();
        if (!NPM_FIELD.test(field)) throw new Error('Invalid npm view field.');
        args.push(field);
      }
      args.push('--json');
      return args;
    }
    default:
      throw new Error(`Unsupported npm operation '${operation}'.`);
  }
}
