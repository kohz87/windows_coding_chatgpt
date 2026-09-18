param(
  [switch]$ForChatGPT,
  [switch]$RequiredOnly,
  [switch]$ScanOnly,
  [switch]$Yes,
  [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path $PSScriptRoot).Path
. (Join-Path $root 'Toolchain.ps1')

function Show-DependencyHeader {
  Clear-Host
  Write-Host '+----------------------------------------------------------+'
  Write-Host '| WINDOWS CODING AGENT - DEPENDENCIES                     |'
  Write-Host '+----------------------------------------------------------+'
  Write-Host ''
}

function Get-DependencySnapshot {
  param([string]$TunnelHint = '')
  Refresh-WcaProcessPath
  return (Refresh-WcaToolchain -TunnelClientHint $TunnelHint)
}

function Get-DependencyTool {
  param($Snapshot, [string]$Name)
  $property = $Snapshot.tools.PSObject.Properties[$Name]
  if ($property) { return $property.Value }
  return $null
}

function Test-DependencyReady {
  param($Snapshot, [string]$Name)
  $tool = Get-DependencyTool -Snapshot $Snapshot -Name $Name
  return ($tool -and $tool.status -eq 'ok' -and -not [string]::IsNullOrWhiteSpace([string]$tool.path))
}

function Write-DependencyStatus {
  param([string]$Label, $Tool)
  if ($Tool -and $Tool.status -eq 'ok') {
    $detail = if ([string]::IsNullOrWhiteSpace([string]$Tool.version)) { '[OK]' } else { '[OK] ' + [string]$Tool.version }
    Write-Host ('  {0,-34} {1}' -f $Label, $detail)
  } elseif ($Tool -and $Tool.status -eq 'blocked') {
    Write-Host ('  {0,-34} [X] blocked by Windows' -f $Label) -ForegroundColor Red
  } else {
    Write-Host ('  {0,-34} [X] not found' -f $Label) -ForegroundColor Yellow
  }
}

function Get-MissingRequired {
  param($Snapshot)
  $missing = New-Object System.Collections.Generic.List[string]
  $node = Get-DependencyTool -Snapshot $Snapshot -Name 'node'
  if (-not (Test-DependencyReady $Snapshot 'node') -or -not (Test-WcaNodeSupported ([string]$node.version))) { $missing.Add('node') }
  if (-not (Test-DependencyReady $Snapshot 'npm')) { $missing.Add('npm') }
  if (-not (Test-DependencyReady $Snapshot 'npx')) { $missing.Add('npx') }
  if (-not (Test-DependencyReady $Snapshot 'git')) { $missing.Add('git') }
  if ($ForChatGPT -and -not (Test-DependencyReady $Snapshot 'tunnelClient')) { $missing.Add('tunnelClient') }
  return @($missing)
}

function Install-OneDependency {
  param([string]$Name)
  switch ($Name) {
    'node' { Install-WcaWingetPackage -PackageId 'OpenJS.NodeJS.LTS'; return }
    'npm' { Install-WcaWingetPackage -PackageId 'OpenJS.NodeJS.LTS'; return }
    'npx' { Install-WcaWingetPackage -PackageId 'OpenJS.NodeJS.LTS'; return }
    'git' { Install-WcaWingetPackage -PackageId 'Git.Git'; return }
    'tunnelClient' { Install-WcaTunnelClient | Out-Null; return }
  }
}

if ($SelfTest) {
  if (-not (Test-WcaApplicationControlMessage 'Application Control policy has blocked this file')) { throw 'Application Control classifier failed.' }
  if (-not (Test-Path -LiteralPath (Join-Path $root 'Toolchain.ps1') -PathType Leaf)) { throw 'Toolchain.ps1 is missing.' }
  Write-Host 'DEPENDENCY SELFTEST OK'
  exit 0
}

$snapshot = Get-DependencySnapshot
Show-DependencyHeader
Write-Host '  Required'
Write-Host ''
Write-DependencyStatus 'Node.js 20+' (Get-DependencyTool $snapshot 'node')
Write-DependencyStatus 'npm' (Get-DependencyTool $snapshot 'npm')
Write-DependencyStatus 'npx' (Get-DependencyTool $snapshot 'npx')
Write-DependencyStatus 'Git' (Get-DependencyTool $snapshot 'git')
if ($ForChatGPT) { Write-DependencyStatus 'OpenAI tunnel-client' (Get-DependencyTool $snapshot 'tunnelClient') }
Write-Host ''
if (-not $RequiredOnly) {
  Write-Host '  Optional package managers'
  Write-Host ''
  Write-DependencyStatus 'pnpm' (Get-DependencyTool $snapshot 'pnpm')
  Write-DependencyStatus 'yarn' (Get-DependencyTool $snapshot 'yarn')
  Write-Host ''
}

$missing = @(Get-MissingRequired -Snapshot $snapshot)
if ($ScanOnly) {
  if ($missing.Count -eq 0) { Write-Host '  [OK] Required dependencies are ready.' -ForegroundColor Green; exit 0 }
  Write-Host ('  [X] Missing required dependencies: {0}' -f ($missing -join ', ')) -ForegroundColor Red
  exit 1
}

if ($missing.Count -gt 0) {
  Write-Host ('  Missing required: {0}' -f ($missing -join ', '))
  Write-Host ''
  $install = $Yes
  if (-not $install) {
    $answer = (Read-Host '  Install/repair the missing required dependencies now? [Y/n]').Trim()
    $install = [string]::IsNullOrWhiteSpace($answer) -or $answer -match '^[Yy]'
  }
  if (-not $install) {
    Write-Host '  Installation skipped. Re-run this wizard after installing the missing tools.'
    exit 2
  }

  $done = @{}
  foreach ($name in $missing) {
    $group = if ($name -in @('node','npm','npx')) { 'node-family' } else { $name }
    if ($done[$group]) { continue }
    Install-OneDependency -Name $name
    $done[$group] = $true
  }

  $snapshot = Get-DependencySnapshot
  $missing = @(Get-MissingRequired -Snapshot $snapshot)
  if ($missing.Count -gt 0) {
    Show-DependencyHeader
    Write-Host ('  [X] Still missing after installation: {0}' -f ($missing -join ', ')) -ForegroundColor Red
    Write-Host '      A new terminal or a manual installer may be required.'
    exit 1
  }
}

if (-not $RequiredOnly -and -not $Yes) {
  while ($true) {
    $snapshot = Get-DependencySnapshot
    $pnpmReady = Test-DependencyReady $snapshot 'pnpm'
    $yarnReady = Test-DependencyReady $snapshot 'yarn'
    if ($pnpmReady -and $yarnReady) { break }

    Show-DependencyHeader
    Write-Host '  Required dependencies are ready.'
    Write-Host ''
    Write-Host '  Optional package managers are installed only when you ask.'
    Write-Host ''
    if (-not $pnpmReady) { Write-Host '     [P] Install pnpm with npm' }
    if (-not $yarnReady) { Write-Host '     [Y] Install yarn with npm' }
    Write-Host '     [S] Skip optional tools'
    Write-Host ''
    $allowed = @('S')
    if (-not $pnpmReady) { $allowed += 'P' }
    if (-not $yarnReady) { $allowed += 'Y' }
    $choice = (Read-Host '  Select').Trim().ToUpperInvariant()
    if ($allowed -notcontains $choice) { continue }
    if ($choice -eq 'S') { break }
    if ($choice -eq 'P') { Install-WcaOptionalPackageManager -Name pnpm }
    if ($choice -eq 'Y') { Install-WcaOptionalPackageManager -Name yarn }
  }
}

Write-Host ''
Write-Host '  [OK] Dependency check complete.' -ForegroundColor Green
Write-Host ('  Toolchain registry: {0}' -f (Get-WcaToolchainPath))
