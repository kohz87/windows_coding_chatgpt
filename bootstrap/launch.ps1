param(
  [Parameter(Mandatory = $true)]
  [ValidateSet('Connect','Manage','Setup','Doctor','Update','Dependencies')]
  [string]$Mode,
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$RemainingArgs
)

$ErrorActionPreference = 'Stop'

function Get-LauncherHome {
  if (-not [string]::IsNullOrWhiteSpace($env:WINDOWS_CODING_AGENT_HOME)) {
    return [IO.Path]::GetFullPath($env:WINDOWS_CODING_AGENT_HOME)
  }
  $userHome = [Environment]::GetFolderPath('UserProfile')
  if ([string]::IsNullOrWhiteSpace($userHome)) { $userHome = $env:USERPROFILE }
  return (Join-Path $userHome '.windows-coding-agent')
}

$launcherHome = Get-LauncherHome
$statePath = Join-Path $launcherHome 'active-version.json'
if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
  throw "No managed Windows Coding Agent installation was found. Run Setup.cmd first. Expected: $statePath"
}

$state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
$root = [string]$state.path
$versionsRoot = [IO.Path]::GetFullPath((Join-Path $launcherHome 'versions')).TrimEnd('\') + '\'
if ([string]::IsNullOrWhiteSpace($root)) { throw 'active-version.json does not contain an installation path.' }
$root = [IO.Path]::GetFullPath($root)
if (-not $root.StartsWith($versionsRoot, [StringComparison]::OrdinalIgnoreCase)) {
  throw 'Managed installation path escaped the versions directory.'
}
if (-not (Test-Path -LiteralPath (Join-Path $root 'package.json') -PathType Leaf)) {
  throw "Managed installation is incomplete: $root"
}

$toolchainPath = Join-Path $launcherHome 'toolchain.json'
$node = $null
if (Test-Path -LiteralPath $toolchainPath -PathType Leaf) {
  try {
    $toolchain = Get-Content -LiteralPath $toolchainPath -Raw | ConvertFrom-Json
    $candidate = [string]$toolchain.tools.node.path
    if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate -PathType Leaf)) { $node = $candidate }
  } catch {}
}
if (-not $node) {
  $command = Get-Command node.exe -ErrorAction SilentlyContinue
  if (-not $command) { $command = Get-Command node -ErrorAction SilentlyContinue }
  if ($command) { $node = $command.Source }
}

switch ($Mode) {
  'Connect' { & (Join-Path $root 'Connect-ChatGPT.ps1') @RemainingArgs; exit $(if ($?) { 0 } else { 1 }) }
  'Update' { & (Join-Path $root 'Update.ps1') @RemainingArgs; exit $(if ($?) { 0 } else { 1 }) }
  'Dependencies' { & (Join-Path $root 'Install-Dependencies.ps1') @RemainingArgs; exit $(if ($?) { 0 } else { 1 }) }
}

if (-not $node) { throw 'Node.js is unavailable. Run Install-Dependencies.cmd.' }
$entry = switch ($Mode) {
  'Manage' { Join-Path $root 'src\startup.js' }
  'Setup' { Join-Path $root 'src\setup.js' }
  'Doctor' { Join-Path $root 'src\doctor.js' }
}
& $node $entry @RemainingArgs
exit $LASTEXITCODE
