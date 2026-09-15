param(
  [string]$TunnelId = '',
  [string]$ProfileName = 'windows-coding-agent',
  [string]$TunnelClient = '',
  [switch]$ConfigureOnly,
  [switch]$ShowInstructions
)

$ErrorActionPreference = 'Stop'

function Show-ChatGPTSteps {
  param([string]$ResolvedTunnelId)

  Write-Host ''
  Write-Host 'ChatGPT custom app setup'
  Write-Host '========================'
  Write-Host '1. Open ChatGPT Settings, then Plugins/Apps -> Advanced settings.'
  Write-Host '2. Enable Developer mode if your workspace permits it.'
  Write-Host '3. Create a custom MCP app (sometimes shown as Create app/connector).'
  Write-Host '4. Choose Connection: Tunnel.'
  if (-not [string]::IsNullOrWhiteSpace($ResolvedTunnelId)) {
    Write-Host "5. Select or paste tunnel ID: $ResolvedTunnelId"
  } else {
    Write-Host '5. Select the same tunnel ID used by this PC.'
  }
  Write-Host '6. Use Authentication: None. Secure MCP Tunnel authenticates the local runtime to OpenAI.'
  Write-Host '7. Let ChatGPT scan/import the MCP tools, then create/save the custom app.'
  Write-Host '8. In workspace app controls, allow the required Read actions and Write actions.'
  Write-Host '   Keep write approvals on Always ask unless you deliberately choose otherwise.'
  Write-Host '9. In a normal ChatGPT chat, enable/select the Windows Coding Agent custom app.'
  Write-Host ''
  Write-Host 'Suggested first prompt:'
  Write-Host '  Use Windows Coding Agent. List my authorized repositories. Do not modify anything yet.'
  Write-Host ''
  Write-Host 'Suggested coding prompt:'
  Write-Host '  Use Windows Coding Agent on <repository>. Create an isolated worktree, make the requested change,'
  Write-Host '  run the allowlisted tests, show me the diff, and commit only if checks pass. Do not publish unless I explicitly ask.'
  Write-Host ''
  Write-Host 'ChatGPT connector settings: https://chatgpt.com/#settings/Connectors'
  Write-Host 'Platform tunnels:          https://platform.openai.com/settings/organization/tunnels'
  Write-Host 'Runtime API keys:          https://platform.openai.com/settings/organization/api-keys'
  Write-Host 'Official tunnel client:    https://github.com/openai/tunnel-client/releases/latest'
}

if ($ShowInstructions) {
  Show-ChatGPTSteps -ResolvedTunnelId $TunnelId
  exit 0
}

$repoRoot = (Resolve-Path $PSScriptRoot).Path
$serverPath = Join-Path $repoRoot 'src\index.js'
if (-not (Test-Path -LiteralPath $serverPath -PathType Leaf)) {
  throw "Windows Coding Agent MCP entrypoint not found: $serverPath"
}

$nodeCommand = Get-Command node.exe -ErrorAction SilentlyContinue
if (-not $nodeCommand) {
  $nodeCommand = Get-Command node -ErrorAction SilentlyContinue
}
if (-not $nodeCommand) {
  throw 'Node.js was not found. Install Node.js 20 or newer, then rerun Connect-ChatGPT.cmd.'
}
$nodePath = $nodeCommand.Source

$tunnelClientPath = $null
if (-not [string]::IsNullOrWhiteSpace($TunnelClient)) {
  if (-not (Test-Path -LiteralPath $TunnelClient -PathType Leaf)) {
    throw "Tunnel client was not found at: $TunnelClient"
  }
  $tunnelClientPath = (Resolve-Path -LiteralPath $TunnelClient).Path
} elseif (-not [string]::IsNullOrWhiteSpace($env:TUNNEL_CLIENT_BIN)) {
  if (Test-Path -LiteralPath $env:TUNNEL_CLIENT_BIN -PathType Leaf) {
    $tunnelClientPath = (Resolve-Path -LiteralPath $env:TUNNEL_CLIENT_BIN).Path
  }
} else {
  $foundTunnelClient = Get-Command tunnel-client.exe -ErrorAction SilentlyContinue
  if (-not $foundTunnelClient) {
    $foundTunnelClient = Get-Command tunnel-client -ErrorAction SilentlyContinue
  }
  if ($foundTunnelClient) {
    $tunnelClientPath = $foundTunnelClient.Source
  }
}

if (-not $tunnelClientPath) {
  Write-Host 'OpenAI Secure MCP Tunnel client was not found.' -ForegroundColor Yellow
  Write-Host ''
  Write-Host 'Download the current Windows build from:'
  Write-Host '  https://github.com/openai/tunnel-client/releases/latest'
  Write-Host 'Extract it, then either put tunnel-client.exe on PATH or set:'
  Write-Host '  TUNNEL_CLIENT_BIN=C:\path\to\tunnel-client.exe'
  Write-Host ''
  $manualPath = Read-Host 'Or paste the full path to tunnel-client.exe now (blank to exit)'
  if ([string]::IsNullOrWhiteSpace($manualPath)) {
    exit 2
  }
  $manualPath = $manualPath.Trim('"')
  if (-not (Test-Path -LiteralPath $manualPath -PathType Leaf)) {
    throw "Tunnel client was not found at: $manualPath"
  }
  $tunnelClientPath = (Resolve-Path -LiteralPath $manualPath).Path
}

if ([string]::IsNullOrWhiteSpace($TunnelId)) {
  if (-not [string]::IsNullOrWhiteSpace($env:CONTROL_PLANE_TUNNEL_ID)) {
    $TunnelId = $env:CONTROL_PLANE_TUNNEL_ID
  } else {
    Write-Host ''
    Write-Host 'Create/select a tunnel at:'
    Write-Host '  https://platform.openai.com/settings/organization/tunnels'
    $TunnelId = Read-Host 'Paste the tunnel ID (tunnel_...)'
  }
}

if ($TunnelId -notmatch '^tunnel_[0-9A-Za-z_-]+$') {
  throw 'Invalid tunnel ID. Expected a value beginning with tunnel_.'
}

if ([string]::IsNullOrWhiteSpace($env:CONTROL_PLANE_API_KEY)) {
  Write-Host ''
  Write-Host 'Create a restricted Runtime API key with Tunnels Read + Use at:'
  Write-Host '  https://platform.openai.com/settings/organization/api-keys'
  Write-Host 'The key entered here is placed only in this process environment and is not written to the project config.'
  $secureKey = Read-Host 'Runtime API key' -AsSecureString
  $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey)
  try {
    $plainKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    if ([string]::IsNullOrWhiteSpace($plainKey)) {
      throw 'Runtime API key cannot be empty.'
    }
    $env:CONTROL_PLANE_API_KEY = $plainKey
  } finally {
    if ($bstr -ne [IntPtr]::Zero) {
      [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
    $plainKey = $null
  }
}

$mcpCommand = "`"$nodePath`" `"$serverPath`""

Write-Host ''
Write-Host 'Configuring OpenAI Secure MCP Tunnel...' -ForegroundColor Cyan
Write-Host "Profile:  $ProfileName"
Write-Host "Tunnel:   $TunnelId"
Write-Host "MCP:      $mcpCommand"

& $tunnelClientPath init --force --sample sample_mcp_stdio_local --profile $ProfileName --tunnel-id $TunnelId --mcp-command $mcpCommand
if ($LASTEXITCODE -ne 0) {
  throw "tunnel-client init failed with exit code $LASTEXITCODE."
}

Write-Host ''
Write-Host 'Checking tunnel and MCP configuration...' -ForegroundColor Cyan
& $tunnelClientPath doctor --profile $ProfileName --explain
if ($LASTEXITCODE -ne 0) {
  throw "tunnel-client doctor failed with exit code $LASTEXITCODE."
}

Show-ChatGPTSteps -ResolvedTunnelId $TunnelId

if ($ConfigureOnly) {
  Write-Host 'Configuration completed. Rerun Connect-ChatGPT.cmd to start the tunnel.'
  exit 0
}

$openSettings = Read-Host 'Open ChatGPT connector settings in your browser? [Y/n]'
if ([string]::IsNullOrWhiteSpace($openSettings) -or $openSettings -match '^[Yy]') {
  Start-Process 'https://chatgpt.com/#settings/Connectors'
}

Write-Host ''
Write-Host 'Starting Secure MCP Tunnel. Keep this window open while ChatGPT uses your local repositories.' -ForegroundColor Green
Write-Host 'Only one active tunnel-client instance should use this tunnel ID with the local stdio MCP.'
Write-Host 'Press Ctrl+C to stop the connection.'
Write-Host ''

& $tunnelClientPath run --profile $ProfileName
exit $LASTEXITCODE
