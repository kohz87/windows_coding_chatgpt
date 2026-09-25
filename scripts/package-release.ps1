param(
  [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\dist'),
  [string]$Commit = ''
)

$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$package = Get-Content (Join-Path $repoRoot 'package.json') -Raw | ConvertFrom-Json
$version = [string]$package.version
if ([string]::IsNullOrWhiteSpace($version)) {
  throw 'package.json does not contain a version.'
}

$bundleName = "Windows-Coding-Agent-v$version"
if ([System.IO.Path]::IsPathRooted($OutputDirectory)) {
  $outputRoot = [System.IO.Path]::GetFullPath($OutputDirectory)
} else {
  $outputRoot = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $OutputDirectory))
}
New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null

$temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("windows-coding-agent-package-" + [guid]::NewGuid().ToString('N'))
$bundleRoot = Join-Path $temporaryRoot $bundleName
New-Item -ItemType Directory -Force -Path $bundleRoot | Out-Null

try {
  $items = @(
    'src',
    'docs',
    'test',
    'bootstrap',
    'scripts',
    'Setup.cmd',
    'Windows-Coding-Agent.cmd',
    'Windows-Coding-Agent.ps1',
    'Toolchain.ps1',
    'Install-Dependencies.cmd',
    'Install-Dependencies.ps1',
    'Doctor.cmd',
    'Update.cmd',
    'Update.ps1',
    'config.example.json',
    'package.json',
    'package-lock.json',
    'README.md',
    'LICENSE'
  )

  foreach ($item in $items) {
    $source = Join-Path $repoRoot $item
    if (Test-Path $source) {
      Copy-Item -Path $source -Destination (Join-Path $bundleRoot $item) -Recurse -Force
    }
  }

  $commitText = if ([string]::IsNullOrWhiteSpace($Commit)) { 'unknown' } else { $Commit }
  @(
    "Windows Coding Agent v$version",
    "Commit: $commitText",
    '',
    'Unzip this directory and run Setup.cmd.',
    'Setup can install or repair required dependencies and creates a managed user-scoped installation.',
    'After setup, use Windows-Coding-Agent.cmd for ChatGPT, repositories, diagnostics, and maintenance.'
  ) | Set-Content -Path (Join-Path $bundleRoot 'VERSION.txt') -Encoding ascii

  $zipPath = Join-Path $outputRoot "$bundleName.zip"
  $checksumPath = "$zipPath.sha256"
  Remove-Item $zipPath, $checksumPath -Force -ErrorAction SilentlyContinue

  Compress-Archive -Path $bundleRoot -DestinationPath $zipPath -CompressionLevel Optimal

  $stream = [System.IO.File]::OpenRead($zipPath)
  $sha256 = [System.Security.Cryptography.SHA256]::Create()
  try {
    $hashBytes = $sha256.ComputeHash($stream)
    $hash = -join ($hashBytes | ForEach-Object { $_.ToString('x2') })
  } finally {
    $stream.Dispose()
    $sha256.Dispose()
  }

  "$hash  $bundleName.zip" | Set-Content -Path $checksumPath -Encoding ascii

  Write-Host "Created $zipPath"
  Write-Host "SHA-256 $hash"
  Write-Output $zipPath
} finally {
  Remove-Item -Path $temporaryRoot -Recurse -Force -ErrorAction SilentlyContinue
}
