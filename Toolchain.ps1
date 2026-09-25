$ErrorActionPreference = 'Stop'

$script:WcaTunnelClientReleaseApi = 'https://api.github.com/repos/openai/tunnel-client/releases/latest'

function Get-WcaAgentHome {
  if (-not [string]::IsNullOrWhiteSpace($env:WINDOWS_CODING_AGENT_HOME)) {
    return [IO.Path]::GetFullPath($env:WINDOWS_CODING_AGENT_HOME)
  }
  $userHome = [Environment]::GetFolderPath('UserProfile')
  if ([string]::IsNullOrWhiteSpace($userHome)) { $userHome = $env:USERPROFILE }
  return (Join-Path $userHome '.windows-coding-agent')
}

function Get-WcaToolchainPath { return (Join-Path (Get-WcaAgentHome) 'toolchain.json') }
function Get-WcaActiveVersionPath { return (Join-Path (Get-WcaAgentHome) 'active-version.json') }
function Get-WcaVersionsRoot { return (Join-Path (Get-WcaAgentHome) 'versions') }
function Get-WcaStableMcpBootstrapPath { return (Join-Path (Get-WcaAgentHome) 'bootstrap\mcp-loader.mjs') }
function Get-WcaStableLauncherPath {
  param([string]$Name = 'Windows-Coding-Agent.cmd')
  return (Join-Path (Get-WcaAgentHome) ('bin\' + $Name))
}

function Read-WcaJsonFile {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
  return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json)
}

function Write-WcaJsonFile {
  param([string]$Path, $Value)
  $parent = Split-Path -Parent $Path
  if (-not [string]::IsNullOrWhiteSpace($parent)) {
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
  }
  $temporary = $Path + '.tmp'
  $json = $Value | ConvertTo-Json -Depth 10
  [IO.File]::WriteAllText($temporary, $json + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
  Move-Item -LiteralPath $temporary -Destination $Path -Force
}

function Get-WcaPackageVersion {
  param([string]$SourceRoot)
  $packagePath = Join-Path $SourceRoot 'package.json'
  if (-not (Test-Path -LiteralPath $packagePath -PathType Leaf)) { throw "package.json was not found under $SourceRoot" }
  $package = Get-Content -LiteralPath $packagePath -Raw | ConvertFrom-Json
  $version = [string]$package.version
  if ([string]::IsNullOrWhiteSpace($version)) { throw 'package.json does not contain a version.' }
  return $version
}

function ConvertTo-WcaVersion {
  param([string]$Value)
  $clean = ([string]$Value).Trim() -replace '^v', ''
  $clean = $clean -replace '-.*$', ''
  try { return [version]$clean } catch { return [version]'0.0.0' }
}

function Compare-WcaVersion {
  param([string]$Left, [string]$Right)
  return (ConvertTo-WcaVersion $Left).CompareTo((ConvertTo-WcaVersion $Right))
}

function Get-WcaToolchainState {
  $state = Read-WcaJsonFile -Path (Get-WcaToolchainPath)
  if ($null -eq $state -or $state.schemaVersion -ne 1) {
    return [pscustomobject]@{ schemaVersion = 1; tools = [pscustomobject]@{}; updatedAt = '' }
  }
  return $state
}

function Save-WcaToolchainState {
  param($State)
  $State.updatedAt = (Get-Date).ToUniversalTime().ToString('o')
  Write-WcaJsonFile -Path (Get-WcaToolchainPath) -Value $State
}

function Get-WcaCommandSource {
  param([string[]]$Names)
  foreach ($name in $Names) {
    $command = Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) {
      if (-not [string]::IsNullOrWhiteSpace([string]$command.Source)) { return [string]$command.Source }
      if (-not [string]::IsNullOrWhiteSpace([string]$command.Path)) { return [string]$command.Path }
      if (-not [string]::IsNullOrWhiteSpace([string]$command.Definition) -and (Test-Path -LiteralPath $command.Definition -PathType Leaf)) {
        return [string]$command.Definition
      }
    }
  }
  return $null
}

function Get-WcaSavedToolPath {
  param($State, [string]$Name)
  if ($null -eq $State -or $null -eq $State.tools) { return $null }
  $property = $State.tools.PSObject.Properties[$Name]
  if ($null -eq $property -or $null -eq $property.Value) { return $null }
  $path = [string]$property.Value.path
  if (-not [string]::IsNullOrWhiteSpace($path) -and (Test-Path -LiteralPath $path -PathType Leaf)) {
    return (Resolve-Path -LiteralPath $path).Path
  }
  return $null
}

function Find-WcaToolPath {
  param(
    [ValidateSet('node','npm','npx','git','powershell','cmd','winget','tunnelClient','pnpm','yarn')]
    [string]$Name,
    [string]$Hint = ''
  )

  $state = Get-WcaToolchainState
  $candidates = New-Object System.Collections.Generic.List[string]
  if (-not [string]::IsNullOrWhiteSpace($Hint)) { $candidates.Add($Hint.Trim('"')) }

  if ($Name -eq 'tunnelClient') {
    if (-not [string]::IsNullOrWhiteSpace($env:TUNNEL_CLIENT_BIN)) { $candidates.Add($env:TUNNEL_CLIENT_BIN.Trim('"')) }
    $candidates.Add((Join-Path (Get-WcaAgentHome) 'tools\tunnel-client\tunnel-client.exe'))
  }

  $saved = Get-WcaSavedToolPath -State $state -Name $Name
  if ($saved) { $candidates.Add($saved) }

  if ($Name -eq 'node' -and $env:ProgramFiles) { $candidates.Add((Join-Path $env:ProgramFiles 'nodejs\node.exe')) }
  if ($Name -eq 'npm' -and $env:ProgramFiles) { $candidates.Add((Join-Path $env:ProgramFiles 'nodejs\npm.cmd')) }
  if ($Name -eq 'npx' -and $env:ProgramFiles) { $candidates.Add((Join-Path $env:ProgramFiles 'nodejs\npx.cmd')) }
  if ($Name -eq 'git' -and $env:ProgramFiles) { $candidates.Add((Join-Path $env:ProgramFiles 'Git\cmd\git.exe')) }
  if ($Name -eq 'powershell' -and $env:SystemRoot) { $candidates.Add((Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe')) }
  if ($Name -eq 'cmd' -and -not [string]::IsNullOrWhiteSpace($env:ComSpec)) { $candidates.Add($env:ComSpec) }

  foreach ($candidate in $candidates) {
    if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
      return (Resolve-Path -LiteralPath $candidate).Path
    }
  }

  switch ($Name) {
    'node' { return (Get-WcaCommandSource @('node.exe','node')) }
    'npm' { return (Get-WcaCommandSource @('npm.cmd','npm.exe','npm')) }
    'npx' { return (Get-WcaCommandSource @('npx.cmd','npx.exe','npx')) }
    'git' { return (Get-WcaCommandSource @('git.exe','git')) }
    'powershell' { return (Get-WcaCommandSource @('powershell.exe','powershell','pwsh.exe','pwsh')) }
    'cmd' { return (Get-WcaCommandSource @('cmd.exe','cmd')) }
    'winget' { return (Get-WcaCommandSource @('winget.exe','winget')) }
    'tunnelClient' { return (Get-WcaCommandSource @('tunnel-client.exe','tunnel-client')) }
    'pnpm' { return (Get-WcaCommandSource @('pnpm.cmd','pnpm.exe','pnpm')) }
    'yarn' { return (Get-WcaCommandSource @('yarn.cmd','yarn.exe','yarn')) }
  }
  return $null
}

function Test-WcaApplicationControlMessage {
  param([string]$Message)
  if ([string]::IsNullOrWhiteSpace($Message)) { return $false }
  return ($Message -match '(?i)application control policy|blocked this file|applocker|code integrity|smart app control')
}

function Get-WcaToolVersion {
  param([string]$Name, [string]$Path)
  if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    return [pscustomobject]@{ status = 'missing'; version = ''; error = '' }
  }
  if ($Name -eq 'cmd') { return [pscustomobject]@{ status = 'ok'; version = [Environment]::OSVersion.VersionString; error = '' } }

  try {
    if ($Name -eq 'powershell') {
      $output = & $Path -NoProfile -Command '$PSVersionTable.PSVersion.ToString()' 2>&1
    } else {
      $output = & $Path --version 2>&1
    }
    $exitCode = $LASTEXITCODE
    $text = ([string]($output -join ' ')).Trim()
    if ($exitCode -eq 0) { return [pscustomobject]@{ status = 'ok'; version = $text; error = '' } }
    return [pscustomobject]@{ status = 'error'; version = ''; error = $text }
  } catch {
    $message = $_.Exception.Message
    $status = if (Test-WcaApplicationControlMessage $message) { 'blocked' } else { 'error' }
    return [pscustomobject]@{ status = $status; version = ''; error = $message }
  }
}

function Refresh-WcaProcessPath {
  $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
  $user = [Environment]::GetEnvironmentVariable('Path', 'User')
  $current = $env:Path
  $seen = @{}
  $parts = New-Object System.Collections.Generic.List[string]
  foreach ($source in @($machine, $user, $current)) {
    if ([string]::IsNullOrWhiteSpace($source)) { continue }
    foreach ($part in ($source -split ';')) {
      $trimmed = $part.Trim()
      if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
      $key = $trimmed.ToLowerInvariant()
      if (-not $seen.ContainsKey($key)) {
        $seen[$key] = $true
        $parts.Add($trimmed)
      }
    }
  }
  if ($parts.Count -gt 0) { $env:Path = ($parts -join ';') }
}

function Refresh-WcaToolchain {
  param([string]$TunnelClientHint = '')
  $names = @('node','npm','npx','git','powershell','cmd','winget','tunnelClient','pnpm','yarn')
  $tools = [ordered]@{}
  foreach ($name in $names) {
    $hint = if ($name -eq 'tunnelClient') { $TunnelClientHint } else { '' }
    $path = Find-WcaToolPath -Name $name -Hint $hint
    $probe = Get-WcaToolVersion -Name $name -Path $path
    $tools[$name] = [ordered]@{
      path = $(if ($path) { $path } else { '' })
      version = [string]$probe.version
      status = [string]$probe.status
      error = [string]$probe.error
    }
  }
  $state = [pscustomobject]@{ schemaVersion = 1; tools = [pscustomobject]$tools; updatedAt = '' }
  Save-WcaToolchainState -State $state
  return $state
}

function Resolve-WcaToolPath {
  param(
    [ValidateSet('node','npm','npx','git','powershell','cmd','winget','tunnelClient','pnpm','yarn')]
    [string]$Name,
    [string]$Hint = ''
  )
  if (-not [string]::IsNullOrWhiteSpace($Hint) -and (Test-Path -LiteralPath $Hint -PathType Leaf)) {
    return (Resolve-Path -LiteralPath $Hint).Path
  }
  $state = Get-WcaToolchainState
  $saved = Get-WcaSavedToolPath -State $state -Name $Name
  if ($saved) { return $saved }
  return (Find-WcaToolPath -Name $Name -Hint $Hint)
}

function Test-WcaNodeSupported {
  param([string]$VersionText)
  if ([string]::IsNullOrWhiteSpace($VersionText)) { return $false }
  $match = [regex]::Match($VersionText, '(\d+)\.(\d+)\.(\d+)')
  if (-not $match.Success) { return $false }
  return ([int]$match.Groups[1].Value -ge 20)
}

function Show-WcaApplicationControlHelp {
  param([string]$Path, [string]$Message = '')
  Write-Host ''
  Write-Host '  [X] Windows Application Control blocked this executable.' -ForegroundColor Red
  Write-Host ''
  if (-not [string]::IsNullOrWhiteSpace($Path)) { Write-Host ('      File: {0}' -f $Path) }
  Write-Host '      Windows refused to start the process before the tool could run.'
  Write-Host '      This is not an API-key or tunnel-ID failure.'
  Write-Host ''
  Write-Host '      Check Windows Security / App Control, WDAC, or AppLocker policy.'
  Write-Host '      On a managed PC, an administrator may need to allow the verified executable.'
  if (-not [string]::IsNullOrWhiteSpace($Message)) {
    Write-Host ''
    Write-Host ('      Detail: {0}' -f $Message)
  }
}

function Install-WcaWingetPackage {
  param([string]$PackageId)
  $winget = Resolve-WcaToolPath -Name winget
  if (-not $winget) { throw 'WinGet is not available. Install the dependency manually, then run the scan again.' }
  Write-Host ('  Installing {0} with WinGet...' -f $PackageId)
  & $winget install --id $PackageId --exact --source winget --accept-package-agreements --accept-source-agreements
  if ($LASTEXITCODE -ne 0) { throw "WinGet failed to install $PackageId (exit $LASTEXITCODE)." }
  Refresh-WcaProcessPath
}

function Get-WcaTunnelArchitecture {
  if ([string]$env:PROCESSOR_ARCHITECTURE -match '(?i)ARM64') { return 'arm64' }
  if ([Environment]::Is64BitOperatingSystem) { return 'amd64' }
  throw 'Automatic tunnel-client installation currently requires 64-bit Windows.'
}

function Get-WcaReleaseAssetDigest {
  param($Release, $Asset)
  $digest = [string]$Asset.digest
  if ($digest -match '^sha256:([0-9a-fA-F]{64})$') { return $Matches[1].ToLowerInvariant() }

  $checksumAsset = @($Release.assets) | Where-Object { $_.name -eq ($Asset.name + '.sha256') } | Select-Object -First 1
  if ($checksumAsset) {
    $temporary = Join-Path ([IO.Path]::GetTempPath()) ('wca-checksum-' + [Guid]::NewGuid().ToString('N') + '.txt')
    try {
      Invoke-WebRequest -Uri $checksumAsset.browser_download_url -OutFile $temporary -UseBasicParsing
      $text = Get-Content -LiteralPath $temporary -Raw
      $match = [regex]::Match($text, '(?i)\b([0-9a-f]{64})\b')
      if ($match.Success) { return $match.Groups[1].Value.ToLowerInvariant() }
    } finally {
      Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
    }
  }
  return $null
}

function Install-WcaTunnelClient {
  $arch = Get-WcaTunnelArchitecture
  Write-Host '  Downloading the official OpenAI tunnel-client release metadata...'
  $headers = @{ 'User-Agent' = 'Windows-Coding-Agent' }
  $release = Invoke-RestMethod -Uri $script:WcaTunnelClientReleaseApi -Headers $headers
  $patterns = if ($arch -eq 'arm64') { @('windows-arm64\.zip$','windows-aarch64\.zip$') } else { @('windows-amd64\.zip$','windows-x86_64\.zip$') }
  $asset = $null
  foreach ($pattern in $patterns) {
    $asset = @($release.assets) | Where-Object { $_.name -match $pattern } | Select-Object -First 1
    if ($asset) { break }
  }
  if (-not $asset) { throw "No official Windows $arch tunnel-client ZIP was found in the latest OpenAI release." }

  $expected = Get-WcaReleaseAssetDigest -Release $release -Asset $asset
  if (-not $expected) { throw 'The release did not expose a verifiable SHA-256 digest. Automatic installation was stopped.' }

  $temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ('wca-tunnel-client-' + [Guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Force -Path $temporaryRoot | Out-Null
  $zip = Join-Path $temporaryRoot $asset.name
  try {
    Write-Host ('  Downloading {0}...' -f $asset.name)
    Invoke-WebRequest -Uri $asset.browser_download_url -Headers $headers -OutFile $zip -UseBasicParsing
    $actual = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $expected) { throw "SHA-256 verification failed for $([string]$asset.name)." }

    $extract = Join-Path $temporaryRoot 'extract'
    Expand-Archive -LiteralPath $zip -DestinationPath $extract -Force
    $exe = Get-ChildItem -LiteralPath $extract -Recurse -Filter 'tunnel-client.exe' -File | Select-Object -First 1
    if (-not $exe) { throw 'The verified tunnel-client archive did not contain tunnel-client.exe.' }

    $targetDir = Join-Path (Get-WcaAgentHome) 'tools\tunnel-client'
    New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
    $target = Join-Path $targetDir 'tunnel-client.exe'
    Copy-Item -LiteralPath $exe.FullName -Destination $target -Force
    Unblock-File -LiteralPath $target -ErrorAction SilentlyContinue

    $probe = Get-WcaToolVersion -Name tunnelClient -Path $target
    if ($probe.status -eq 'blocked') {
      Show-WcaApplicationControlHelp -Path $target -Message $probe.error
      throw 'Windows Application Control blocked the verified tunnel-client executable.'
    }
    if ($probe.status -ne 'ok') { throw "Installed tunnel-client could not run: $([string]$probe.error)" }

    Refresh-WcaToolchain -TunnelClientHint $target | Out-Null
    Write-Host ('  [OK] tunnel-client installed: {0}' -f $target) -ForegroundColor Green
    return $target
  } finally {
    Remove-Item -LiteralPath $temporaryRoot -Recurse -Force -ErrorAction SilentlyContinue
  }
}

function Install-WcaOptionalPackageManager {
  param([ValidateSet('pnpm','yarn')][string]$Name)
  $npm = Resolve-WcaToolPath -Name npm
  if (-not $npm) { throw 'npm is required before installing optional JavaScript package managers.' }
  Write-Host ('  Installing {0} with npm...' -f $Name)
  & $npm install --global $Name
  if ($LASTEXITCODE -ne 0) { throw "npm failed to install $Name." }
  Refresh-WcaProcessPath
  Refresh-WcaToolchain | Out-Null
}

function Test-WcaManagedRoot {
  param([string]$Path)
  if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Container)) { return $false }
  return (Test-Path -LiteralPath (Join-Path $Path 'src\index.js') -PathType Leaf) -and
         (Test-Path -LiteralPath (Join-Path $Path 'package.json') -PathType Leaf) -and
         (Test-Path -LiteralPath (Join-Path $Path 'node_modules\@modelcontextprotocol\server') -PathType Container)
}

function Get-WcaActiveInstallation {
  $state = Read-WcaJsonFile -Path (Get-WcaActiveVersionPath)
  if ($null -eq $state -or $state.schemaVersion -ne 1) { return $null }
  return $state
}

function Test-WcaPathInsideVersions {
  param([string]$Path)
  if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
  $root = [IO.Path]::GetFullPath((Get-WcaVersionsRoot)).TrimEnd('\') + '\'
  $candidate = [IO.Path]::GetFullPath($Path)
  return $candidate.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)
}

function Set-WcaActiveInstallation {
  param([string]$Version, [string]$Path)

  if (-not (Test-WcaPathInsideVersions $Path)) { throw 'Active installation must remain under the Windows Coding Agent versions directory.' }
  $previous = Get-WcaActiveInstallation
  $state = [ordered]@{
    schemaVersion = 1
    activeVersion = $Version
    path = [IO.Path]::GetFullPath($Path)
    lastKnownGoodVersion = ''
    lastKnownGoodPath = ''
    updatedAt = (Get-Date).ToUniversalTime().ToString('o')
  }
  if ($previous -and -not [string]::IsNullOrWhiteSpace([string]$previous.path) -and
      ([string]$previous.path -ne [string]$state.path) -and (Test-WcaManagedRoot ([string]$previous.path))) {
    $state.lastKnownGoodVersion = [string]$previous.activeVersion
    $state.lastKnownGoodPath = [string]$previous.path
  } elseif ($previous) {
    $state.lastKnownGoodVersion = [string]$previous.lastKnownGoodVersion
    $state.lastKnownGoodPath = [string]$previous.lastKnownGoodPath
  }
  Write-WcaJsonFile -Path (Get-WcaActiveVersionPath) -Value $state
  return [pscustomobject]$state
}

function Write-WcaStableLauncher {
  param([string]$Path, [string]$Mode)
  $lines = @(
    '@echo off',
    'setlocal',
    ('powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\bootstrap\launch.ps1" -Mode ' + $Mode + ' %*'),
    'exit /b %ERRORLEVEL%'
  )
  [IO.File]::WriteAllText($Path, ($lines -join [Environment]::NewLine) + [Environment]::NewLine, [Text.ASCIIEncoding]::new())
}

function Ensure-WcaStableFiles {
  param([string]$SourceRoot)

  $bootstrapSource = Join-Path $SourceRoot 'bootstrap'
  if (-not (Test-Path -LiteralPath (Join-Path $bootstrapSource 'mcp-loader.mjs') -PathType Leaf)) { throw 'Distribution is missing bootstrap\mcp-loader.mjs.' }
  if (-not (Test-Path -LiteralPath (Join-Path $bootstrapSource 'launch.ps1') -PathType Leaf)) { throw 'Distribution is missing bootstrap\launch.ps1.' }

  $agentHome = Get-WcaAgentHome
  $bootstrapTarget = Join-Path $agentHome 'bootstrap'
  $binTarget = Join-Path $agentHome 'bin'
  New-Item -ItemType Directory -Force -Path $bootstrapTarget, $binTarget | Out-Null
  Copy-Item -LiteralPath (Join-Path $bootstrapSource 'mcp-loader.mjs') -Destination (Join-Path $bootstrapTarget 'mcp-loader.mjs') -Force
  Copy-Item -LiteralPath (Join-Path $bootstrapSource 'launch.ps1') -Destination (Join-Path $bootstrapTarget 'launch.ps1') -Force

  Write-WcaStableLauncher -Path (Join-Path $binTarget 'Windows-Coding-Agent.cmd') -Mode 'Control'
  # Compatibility aliases for existing pinned shortcuts. The canonical entry point is Windows-Coding-Agent.cmd.
  Write-WcaStableLauncher -Path (Join-Path $binTarget 'Connect-ChatGPT.cmd') -Mode 'Connect'
  Write-WcaStableLauncher -Path (Join-Path $binTarget 'Start-Agent.cmd') -Mode 'Manage'
  Write-WcaStableLauncher -Path (Join-Path $binTarget 'Setup.cmd') -Mode 'Setup'
  Write-WcaStableLauncher -Path (Join-Path $binTarget 'Doctor.cmd') -Mode 'Doctor'
  Write-WcaStableLauncher -Path (Join-Path $binTarget 'Update.cmd') -Mode 'Update'
  Write-WcaStableLauncher -Path (Join-Path $binTarget 'Install-Dependencies.cmd') -Mode 'Dependencies'
}

function Copy-WcaDistribution {
  param([string]$SourceRoot, [string]$DestinationRoot)
  New-Item -ItemType Directory -Force -Path $DestinationRoot | Out-Null
  $items = @(
    'src','docs','test','bootstrap','scripts',
    'Windows-Coding-Agent.cmd','Windows-Coding-Agent.ps1','Setup.cmd',
    'Doctor.cmd','Update.cmd','Update.ps1','Install-Dependencies.cmd','Install-Dependencies.ps1',
    'Toolchain.ps1','config.example.json','package.json','package-lock.json','README.md','LICENSE','AGENTS.md'
  )
  foreach ($item in $items) {
    $source = Join-Path $SourceRoot $item
    if (Test-Path -LiteralPath $source) {
      Copy-Item -LiteralPath $source -Destination (Join-Path $DestinationRoot $item) -Recurse -Force
    }
  }
}

function Invoke-WcaDistributionValidation {
  param([string]$Root)
  $npm = Resolve-WcaToolPath -Name npm
  $powershell = Resolve-WcaToolPath -Name powershell
  if (-not $npm -or -not $powershell) { throw 'Node.js, npm, and Windows PowerShell are required to validate an agent installation.' }

  Push-Location $Root
  try {
    Write-Host '  Installing locked runtime dependencies...'
    & $npm ci --ignore-scripts
    if ($LASTEXITCODE -ne 0) { throw 'npm ci failed while preparing the managed installation.' }

    Write-Host '  Running package tests...'
    & $npm test
    if ($LASTEXITCODE -ne 0) { throw 'npm test failed for the managed installation.' }

    Write-Host '  Validating source...'
    & $npm run validate
    if ($LASTEXITCODE -ne 0) { throw 'npm run validate failed for the managed installation.' }

    Write-Host '  Running Windows launcher self-test...'
    & $powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'Windows-Coding-Agent.ps1') -SelfTest
    if ($LASTEXITCODE -ne 0) { throw 'Windows-Coding-Agent control-panel self-test failed for the managed installation.' }
  } finally {
    Pop-Location
  }
}

function Install-WcaManagedVersion {
  param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [switch]$ForceActivate
  )

  $source = (Resolve-Path -LiteralPath $SourceRoot).Path
  $version = Get-WcaPackageVersion -SourceRoot $source
  $versionsRoot = Get-WcaVersionsRoot
  New-Item -ItemType Directory -Force -Path $versionsRoot | Out-Null
  $target = Join-Path $versionsRoot ('v' + $version)

  if (-not (Test-WcaManagedRoot $target)) {
    $stageRoot = Join-Path (Get-WcaAgentHome) 'staging'
    New-Item -ItemType Directory -Force -Path $stageRoot | Out-Null
    $stage = Join-Path $stageRoot ('v' + $version + '-' + [Guid]::NewGuid().ToString('N'))
    try {
      Copy-WcaDistribution -SourceRoot $source -DestinationRoot $stage
      Invoke-WcaDistributionValidation -Root $stage

      if (Test-Path -LiteralPath $target) {
        $backup = $target + '.broken-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
        Move-Item -LiteralPath $target -Destination $backup
      }
      Move-Item -LiteralPath $stage -Destination $target
    } finally {
      if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue }
    }
  }

  Ensure-WcaStableFiles -SourceRoot $target
  $active = Get-WcaActiveInstallation
  $shouldActivate = $ForceActivate -or $null -eq $active -or [string]::IsNullOrWhiteSpace([string]$active.activeVersion)
  if (-not $shouldActivate -and (Compare-WcaVersion $version ([string]$active.activeVersion)) -ge 0) { $shouldActivate = $true }
  if ($shouldActivate) { $active = Set-WcaActiveInstallation -Version $version -Path $target }

  return [pscustomobject]@{
    version = $version
    path = $target
    active = [bool]($active -and ([string]$active.path -eq [string]$target))
    bootstrap = Get-WcaStableMcpBootstrapPath
    launcher = Get-WcaStableLauncherPath
  }
}

function Invoke-WcaRollback {
  $active = Get-WcaActiveInstallation
  if (-not $active) { throw 'No active managed installation exists.' }
  $fallback = [string]$active.lastKnownGoodPath
  if ([string]::IsNullOrWhiteSpace($fallback) -or -not (Test-WcaManagedRoot $fallback)) { throw 'No valid last-known-good installation is available for rollback.' }
  if (-not (Test-WcaPathInsideVersions $fallback)) { throw 'Last-known-good path is outside the managed versions directory.' }

  $next = [ordered]@{
    schemaVersion = 1
    activeVersion = [string]$active.lastKnownGoodVersion
    path = $fallback
    lastKnownGoodVersion = [string]$active.activeVersion
    lastKnownGoodPath = [string]$active.path
    updatedAt = (Get-Date).ToUniversalTime().ToString('o')
  }
  Write-WcaJsonFile -Path (Get-WcaActiveVersionPath) -Value $next
  Ensure-WcaStableFiles -SourceRoot $fallback
  return [pscustomobject]$next
}

function Invoke-WcaToolchainSelfTest {
  $oldHome = $env:WINDOWS_CODING_AGENT_HOME
  $temporary = Join-Path ([IO.Path]::GetTempPath()) ('wca-toolchain-selftest-' + [Guid]::NewGuid().ToString('N'))
  try {
    $env:WINDOWS_CODING_AGENT_HOME = $temporary
    $state = [pscustomobject]@{ schemaVersion = 1; tools = [pscustomobject]@{}; updatedAt = '' }
    Save-WcaToolchainState -State $state
    if (-not (Test-Path -LiteralPath (Get-WcaToolchainPath) -PathType Leaf)) { throw 'Toolchain state was not written.' }
    if ((Compare-WcaVersion '0.1.6' '0.1.5') -le 0) { throw 'Version comparison failed.' }
    Ensure-WcaStableFiles -SourceRoot $PSScriptRoot
    if (-not (Test-Path -LiteralPath (Get-WcaStableLauncherPath) -PathType Leaf)) { throw 'Stable launcher self-test failed.' }
    if (-not (Test-WcaApplicationControlMessage 'An Application Control policy has blocked this file')) { throw 'Application Control detection failed.' }
    if (Test-WcaPathInsideVersions 'C:\Windows\System32') { throw 'Managed path containment accepted an external path.' }
    Write-Host 'TOOLCHAIN SELFTEST OK'
  } finally {
    if ($null -eq $oldHome) { Remove-Item Env:WINDOWS_CODING_AGENT_HOME -ErrorAction SilentlyContinue } else { $env:WINDOWS_CODING_AGENT_HOME = $oldHome }
    Remove-Item -LiteralPath $temporary -Recurse -Force -ErrorAction SilentlyContinue
  }
}
