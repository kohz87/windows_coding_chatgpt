param(
  [switch]$CheckOnly,
  [switch]$Yes,
  [switch]$Force,
  [switch]$Rollback,
  [switch]$InstallCurrent,
  [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path $PSScriptRoot).Path
. (Join-Path $root 'Toolchain.ps1')
$releaseApi = 'https://api.github.com/repos/kohz87/windows_coding_chatgpt/releases/latest'

function Get-ReleaseDigest {
  param($Release, $Asset)
  $digest = [string]$Asset.digest
  if ($digest -match '^sha256:([0-9a-fA-F]{64})$') { return $Matches[1].ToLowerInvariant() }
  $checksum = @($Release.assets) | Where-Object { $_.name -eq ($Asset.name + '.sha256') } | Select-Object -First 1
  if ($checksum) {
    $temporary = Join-Path ([IO.Path]::GetTempPath()) ('wca-release-checksum-' + [Guid]::NewGuid().ToString('N') + '.txt')
    try {
      Invoke-WebRequest -Uri $checksum.browser_download_url -OutFile $temporary -UseBasicParsing
      $text = Get-Content -LiteralPath $temporary -Raw
      $match = [regex]::Match($text, '(?i)\b([0-9a-f]{64})\b')
      if ($match.Success) { return $match.Groups[1].Value.ToLowerInvariant() }
    } finally {
      Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
    }
  }
  return $null
}

function Show-UpdateHeader {
  Clear-Host
  Write-Host '+----------------------------------------------------------+'
  Write-Host '| WINDOWS CODING AGENT - MAINTENANCE                      |'
  Write-Host '+----------------------------------------------------------+'
  Write-Host ''
}

if ($SelfTest) {
  if ((Compare-WcaVersion '0.1.6' '0.1.5') -le 0) { throw 'Version comparator failed.' }
  if (-not (Test-Path -LiteralPath (Join-Path $root 'bootstrap\mcp-loader.mjs') -PathType Leaf)) { throw 'Stable bootstrap template is missing.' }
  Write-Host 'UPDATE SELFTEST OK'
  exit 0
}

if ($Rollback) {
  Show-UpdateHeader
  $state = Invoke-WcaRollback
  Write-Host ('  [OK] Rolled back to v{0}' -f $state.activeVersion) -ForegroundColor Green
  Write-Host ('  Active path: {0}' -f $state.path)
  exit 0
}

if ($InstallCurrent) {
  Show-UpdateHeader
  Write-Host '  Preparing the current release as a managed installation...'
  Write-Host ''
  $installed = Install-WcaManagedVersion -SourceRoot $root -ForceActivate
  Refresh-WcaToolchain | Out-Null
  Write-Host ''
  Write-Host ('  [OK] Active Windows Coding Agent: v{0}' -f $installed.version) -ForegroundColor Green
  Write-Host ('  Stable launcher: {0}' -f $installed.launcher)
  exit 0
}

Show-UpdateHeader
$currentPackage = Get-WcaPackageVersion -SourceRoot $root
$active = Get-WcaActiveInstallation
$current = if ($active -and -not [string]::IsNullOrWhiteSpace([string]$active.activeVersion)) { [string]$active.activeVersion } else { $currentPackage }
Write-Host ('  Current active version: v{0}' -f $current)
Write-Host '  Checking GitHub releases...'

$headers = @{ 'User-Agent' = 'Windows-Coding-Agent' }
$release = Invoke-RestMethod -Uri $releaseApi -Headers $headers
$latest = ([string]$release.tag_name) -replace '^v', ''
if ([string]::IsNullOrWhiteSpace($latest)) { throw 'Latest release did not contain a version tag.' }
Write-Host ('  Latest release:        v{0}' -f $latest)
Write-Host ''

$comparison = Compare-WcaVersion $latest $current
if ($comparison -le 0 -and -not $Force) {
  Write-Host '  [OK] No newer release is available.' -ForegroundColor Green
  exit 0
}
if ($CheckOnly) {
  Write-Host ('  [!] Update available: v{0} -> v{1}' -f $current, $latest) -ForegroundColor Yellow
  exit 0
}

$proceed = $Yes
if (-not $proceed) {
  $answer = (Read-Host ('  Download, verify, test, and activate v{0}? [Y/n]' -f $latest)).Trim()
  $proceed = [string]::IsNullOrWhiteSpace($answer) -or $answer -match '^[Yy]'
}
if (-not $proceed) { Write-Host '  Update cancelled.'; exit 0 }

$assetName = 'Windows-Coding-Agent-v' + $latest + '.zip'
$asset = @($release.assets) | Where-Object { $_.name -eq $assetName } | Select-Object -First 1
if (-not $asset) { throw "Release v$latest does not contain $assetName." }
$expected = Get-ReleaseDigest -Release $release -Asset $asset
if (-not $expected) { throw 'The release package has no verifiable SHA-256 digest. Activation was stopped.' }

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('wca-update-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
try {
  $zip = Join-Path $tempRoot $assetName
  Write-Host ('  Downloading {0}...' -f $assetName)
  Invoke-WebRequest -Uri $asset.browser_download_url -Headers $headers -OutFile $zip -UseBasicParsing
  $actual = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($actual -ne $expected) { throw 'Downloaded update failed SHA-256 verification.' }
  Write-Host '  [OK] SHA-256 verified.' -ForegroundColor Green

  $extract = Join-Path $tempRoot 'extract'
  Expand-Archive -LiteralPath $zip -DestinationPath $extract -Force
  $packageFiles = Get-ChildItem -LiteralPath $extract -Recurse -Filter 'package.json' -File
  $bundle = $null
  foreach ($packageFile in $packageFiles) {
    try {
      $package = Get-Content -LiteralPath $packageFile.FullName -Raw | ConvertFrom-Json
      if ([string]$package.name -eq 'windows-coding-agent' -and [string]$package.version -eq $latest) {
        $bundle = $packageFile.Directory.FullName
        break
      }
    } catch {}
  }
  if (-not $bundle) { throw 'The verified release ZIP did not contain the expected Windows Coding Agent package.' }

  Write-Host '  Validating candidate before activation...'
  $candidateToolchain = Join-Path $bundle 'Toolchain.ps1'
  if (-not (Test-Path -LiteralPath $candidateToolchain -PathType Leaf)) { throw 'The verified release is missing Toolchain.ps1.' }
  . $candidateToolchain
  $installed = Install-WcaManagedVersion -SourceRoot $bundle -ForceActivate
  Refresh-WcaToolchain | Out-Null
  Write-Host ''
  Write-Host ('  [OK] Update complete. Active version: v{0}' -f $installed.version) -ForegroundColor Green
  Write-Host ('  Stable launcher: {0}' -f $installed.launcher)
  Write-Host '  If a later startup health check fails, run Update.cmd -Rollback.'
} finally {
  Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
