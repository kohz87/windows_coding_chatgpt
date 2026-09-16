param(
  [string]$TunnelId = '',
  [string]$ProfileName = 'windows-coding-agent',
  [string]$TunnelClient = '',
  [switch]$ConfigureOnly,
  [switch]$ShowInstructions,
  [switch]$ResetSetup,
  [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'

$script:TunnelsUrl = 'https://platform.openai.com/settings/organization/tunnels'
$script:ApiKeysUrl = 'https://platform.openai.com/settings/organization/api-keys'
$script:ChatGPTUrl = 'https://chatgpt.com/#settings/Connectors'
$script:TunnelClientUrl = 'https://github.com/openai/tunnel-client/releases/latest'
$script:RepoRoot = (Resolve-Path $PSScriptRoot).Path
$script:ServerPath = Join-Path $script:RepoRoot 'src\index.js'
$script:SetupCmd = Join-Path $script:RepoRoot 'Setup.cmd'
$script:ManagerCmd = Join-Path $script:RepoRoot 'Start-Agent.cmd'

function Get-AgentHome {
  if (-not [string]::IsNullOrWhiteSpace($env:WINDOWS_CODING_AGENT_HOME)) {
    return [System.IO.Path]::GetFullPath($env:WINDOWS_CODING_AGENT_HOME)
  }
  $userHome = [Environment]::GetFolderPath('UserProfile')
  if ([string]::IsNullOrWhiteSpace($userHome)) { $userHome = $env:USERPROFILE }
  return (Join-Path $userHome '.windows-coding-agent')
}

$script:AgentHome = Get-AgentHome
$script:StatePath = Join-Path $script:AgentHome 'chatgpt-connection.json'
$script:ConfigPath = Join-Path $script:AgentHome 'config.json'
$script:SecretsPath = Join-Path $script:AgentHome 'secrets'
$script:CredentialPath = Join-Path $script:SecretsPath 'tunnel-runtime-key.dpapi'
$script:CredentialEntropy = [Text.Encoding]::UTF8.GetBytes('windows-coding-agent:tunnel-runtime-key:v1')
Add-Type -AssemblyName System.Security -ErrorAction Stop

function Show-Header {
  param([string]$RightText = '')
  Clear-Host
  Write-Host '+----------------------------------------------------------+'
  Write-Host '|              WINDOWS CODING AGENT                      |'
  Write-Host '|          ChatGPT <-> Local Git Bridge                  |'
  Write-Host '+----------------------------------------------------------+'
  if (-not [string]::IsNullOrWhiteSpace($RightText)) {
    Write-Host ('  {0}' -f $RightText)
    Write-Host ''
  }
}

function Write-Rule {
  Write-Host '  --------------------------------------------------------'
}

function Write-Status {
  param([string]$Label, [string]$Status)
  Write-Host ('  {0,-38} {1}' -f $Label, $Status)
}

function Read-Choice {
  param([string]$Prompt, [string[]]$Allowed)
  while ($true) {
    $value = (Read-Host $Prompt).Trim().ToUpperInvariant()
    if ($Allowed -contains $value) { return $value }
    Write-Host ('  Please choose: {0}' -f ($Allowed -join ', ')) -ForegroundColor Yellow
  }
}

function Open-SetupPage {
  param([string]$Url)
  try {
    Start-Process $Url
    return $true
  } catch {
    Write-Host "  Could not open the browser automatically." -ForegroundColor Yellow
    Write-Host "  Open this page manually: $Url"
    return $false
  }
}

function Test-TunnelId {
  param([string]$Value)
  return (-not [string]::IsNullOrWhiteSpace($Value)) -and ($Value -match '^tunnel_[0-9A-Za-z_-]+$')
}

function Test-ProfileName {
  param([string]$Value)
  return (-not [string]::IsNullOrWhiteSpace($Value)) -and ($Value -match '^[A-Za-z0-9._-]+$')
}

function New-ConnectionState {
  return [ordered]@{
    schemaVersion = 1
    profileName = $ProfileName
    tunnelId = ''
    tunnelClientPath = ''
    profileConfigured = $false
    chatgptConfigured = $false
    lastDoctorOk = ''
    updatedAt = ''
  }
}

function Load-ConnectionState {
  $state = New-ConnectionState
  if (-not (Test-Path -LiteralPath $script:StatePath -PathType Leaf)) { return $state }
  try {
    $raw = Get-Content -LiteralPath $script:StatePath -Raw | ConvertFrom-Json
    if ($raw.schemaVersion -eq 1) {
      if (Test-ProfileName ([string]$raw.profileName)) { $state.profileName = [string]$raw.profileName }
      if (Test-TunnelId ([string]$raw.tunnelId)) { $state.tunnelId = [string]$raw.tunnelId }
      if (-not [string]::IsNullOrWhiteSpace([string]$raw.tunnelClientPath)) { $state.tunnelClientPath = [string]$raw.tunnelClientPath }
      $state.profileConfigured = [bool]$raw.profileConfigured
      $state.chatgptConfigured = [bool]$raw.chatgptConfigured
      $state.lastDoctorOk = [string]$raw.lastDoctorOk
      $state.updatedAt = [string]$raw.updatedAt
    }
  } catch {
    Write-Host "  [!] Saved ChatGPT setup state could not be read. A fresh state will be used." -ForegroundColor Yellow
  }
  return $state
}

function Save-ConnectionState {
  param($State)
  New-Item -ItemType Directory -Force -Path $script:AgentHome | Out-Null
  $State.updatedAt = (Get-Date).ToUniversalTime().ToString('o')
  $temporary = "$($script:StatePath).tmp"
  $State | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $temporary -Encoding UTF8
  Move-Item -LiteralPath $temporary -Destination $script:StatePath -Force
}

function Test-SavedRuntimeCredential {
  param([string]$Path = $script:CredentialPath)
  return (Test-Path -LiteralPath $Path -PathType Leaf)
}

function Save-RuntimeCredential {
  param(
    [Parameter(Mandatory = $true)][string]$PlainText,
    [string]$Path = $script:CredentialPath
  )

  if ([string]::IsNullOrWhiteSpace($PlainText)) { throw 'Runtime credential cannot be empty.' }
  $parent = Split-Path -Parent $Path
  if (-not [string]::IsNullOrWhiteSpace($parent)) {
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
  }

  $plainBytes = [Text.Encoding]::UTF8.GetBytes($PlainText)
  $protectedBytes = $null
  try {
    $protectedBytes = [System.Security.Cryptography.ProtectedData]::Protect(
      $plainBytes,
      $script:CredentialEntropy,
      [System.Security.Cryptography.DataProtectionScope]::CurrentUser
    )
    [IO.File]::WriteAllBytes($Path, $protectedBytes)
  } finally {
    if ($plainBytes) { [Array]::Clear($plainBytes, 0, $plainBytes.Length) }
    if ($protectedBytes) { [Array]::Clear($protectedBytes, 0, $protectedBytes.Length) }
  }
}

function Load-RuntimeCredential {
  param([string]$Path = $script:CredentialPath)

  if (-not (Test-SavedRuntimeCredential -Path $Path)) { return $null }
  $protectedBytes = [IO.File]::ReadAllBytes($Path)
  $plainBytes = $null
  try {
    $plainBytes = [System.Security.Cryptography.ProtectedData]::Unprotect(
      $protectedBytes,
      $script:CredentialEntropy,
      [System.Security.Cryptography.DataProtectionScope]::CurrentUser
    )
    return [Text.Encoding]::UTF8.GetString($plainBytes)
  } finally {
    if ($protectedBytes) { [Array]::Clear($protectedBytes, 0, $protectedBytes.Length) }
    if ($plainBytes) { [Array]::Clear($plainBytes, 0, $plainBytes.Length) }
  }
}

function Remove-SavedRuntimeCredential {
  param([string]$Path = $script:CredentialPath)
  if (Test-Path -LiteralPath $Path -PathType Leaf) {
    Remove-Item -LiteralPath $Path -Force
  }
}
function Get-RepositoryCount {
  if (-not (Test-Path -LiteralPath $script:ConfigPath -PathType Leaf)) { return 0 }
  try {
    $config = Get-Content -LiteralPath $script:ConfigPath -Raw | ConvertFrom-Json
    if ($null -eq $config.repositories) { return 0 }
    return @($config.repositories.PSObject.Properties).Count
  } catch {
    return 0
  }
}

function Get-NodePath {
  $command = Get-Command node.exe -ErrorAction SilentlyContinue
  if (-not $command) { $command = Get-Command node -ErrorAction SilentlyContinue }
  if ($command) { return $command.Source }
  return $null
}

function Get-GitPath {
  $command = Get-Command git.exe -ErrorAction SilentlyContinue
  if (-not $command) { $command = Get-Command git -ErrorAction SilentlyContinue }
  if ($command) { return $command.Source }
  return $null
}

function Get-ExistingTunnelClientPath {
  param($State)

  $candidates = @()
  if (-not [string]::IsNullOrWhiteSpace($TunnelClient)) { $candidates += $TunnelClient }
  if (-not [string]::IsNullOrWhiteSpace($env:TUNNEL_CLIENT_BIN)) { $candidates += $env:TUNNEL_CLIENT_BIN }
  if (-not [string]::IsNullOrWhiteSpace([string]$State.tunnelClientPath)) { $candidates += [string]$State.tunnelClientPath }

  foreach ($candidate in $candidates) {
    $trimmed = $candidate.Trim('"')
    if (Test-Path -LiteralPath $trimmed -PathType Leaf) {
      return (Resolve-Path -LiteralPath $trimmed).Path
    }
  }

  $found = Get-Command tunnel-client.exe -ErrorAction SilentlyContinue
  if (-not $found) { $found = Get-Command tunnel-client -ErrorAction SilentlyContinue }
  if ($found) { return $found.Source }
  return $null
}

function Select-TunnelClient {
  param($State, [int]$StepNumber = 2)

  while ($true) {
    $existing = Get-ExistingTunnelClientPath -State $State
    if ($existing) {
      $State.tunnelClientPath = $existing
      Save-ConnectionState -State $State
      return $existing
    }

    Show-Header -RightText "Setup  $StepNumber / 6"
    Write-Host '  [>>] OPENAI SECURE MCP TUNNEL CLIENT'
    Write-Host ''
    Write-Host '  The official tunnel client connects this PC to ChatGPT'
    Write-Host '  using an outbound-only encrypted connection.'
    Write-Host ''
    Write-Host '     [1] Open official download page'
    Write-Host '     [2] Enter path to tunnel-client.exe'
    Write-Host '     [3] Check PATH again'
    Write-Host '     [B] Back'
    Write-Host ''
    $choice = Read-Choice '  Select' @('1','2','3','B')
    if ($choice -eq '1') {
      Open-SetupPage $script:TunnelClientUrl | Out-Null
      continue
    }
    if ($choice -eq '2') {
      $manualPath = (Read-Host '  Full path to tunnel-client.exe').Trim().Trim('"')
      if (Test-Path -LiteralPath $manualPath -PathType Leaf) {
        $resolved = (Resolve-Path -LiteralPath $manualPath).Path
        $State.tunnelClientPath = $resolved
        Save-ConnectionState -State $State
        return $resolved
      }
      Write-Host '  [X] That file was not found.' -ForegroundColor Red
      Read-Host '  Press Enter to continue' | Out-Null
      continue
    }
    if ($choice -eq '3') { continue }
    return $null
  }
}

function Get-TunnelIdStep {
  param($State)

  if (Test-TunnelId $TunnelId) {
    $State.tunnelId = $TunnelId
    $State.profileConfigured = $false
    $State.chatgptConfigured = $false
    Save-ConnectionState -State $State
    return $State.tunnelId
  }
  if (Test-TunnelId $env:CONTROL_PLANE_TUNNEL_ID) {
    $State.tunnelId = $env:CONTROL_PLANE_TUNNEL_ID
    Save-ConnectionState -State $State
    return $State.tunnelId
  }

  while ($true) {
    Show-Header -RightText 'Setup  3 / 6'
    Write-Host '  [>>] CREATE OR SELECT YOUR OPENAI TUNNEL'
    Write-Host ''
    Write-Host '  The tunnel is the shared ID used by ChatGPT and this PC.'
    Write-Host '  Create it for the same ChatGPT workspace you will use.'
    Write-Host ''
    if (Test-TunnelId $State.tunnelId) {
      Write-Host "  Current tunnel: $($State.tunnelId)"
      Write-Host ''
      Write-Host '     [C] Continue with current tunnel'
    }
    Write-Host '     [O] Open OpenAI Tunnels page'
    Write-Host '     [P] Paste a tunnel ID'
    Write-Host '     [B] Back'
    Write-Host ''
    $allowed = @('O','P','B')
    if (Test-TunnelId $State.tunnelId) { $allowed += 'C' }
    $choice = Read-Choice '  Select' $allowed
    if ($choice -eq 'O') {
      Open-SetupPage $script:TunnelsUrl | Out-Null
      continue
    }
    if ($choice -eq 'P') {
      $candidate = (Read-Host '  Tunnel ID (tunnel_...)').Trim()
      if (-not (Test-TunnelId $candidate)) {
        Write-Host '  [X] Invalid tunnel ID. It must begin with tunnel_.' -ForegroundColor Red
        Read-Host '  Press Enter to continue' | Out-Null
        continue
      }
      if ($candidate -ne $State.tunnelId) {
        $State.profileConfigured = $false
        $State.chatgptConfigured = $false
      }
      $State.tunnelId = $candidate
      Save-ConnectionState -State $State
      return $candidate
    }
    if ($choice -eq 'C') { return $State.tunnelId }
    return $null
  }
}

function Read-RuntimeApiKey {
  param([switch]$ForcePrompt)

  if (-not $ForcePrompt -and -not [string]::IsNullOrWhiteSpace($env:CONTROL_PLANE_API_KEY)) {
    return $true
  }

  if (-not $ForcePrompt -and (Test-SavedRuntimeCredential)) {
    $savedCredential = $null
    try {
      $savedCredential = Load-RuntimeCredential
      if (-not [string]::IsNullOrWhiteSpace($savedCredential)) {
        $env:CONTROL_PLANE_API_KEY = $savedCredential
        return $true
      }
    } catch {
      Show-Header -RightText 'Runtime credential'
      Write-Host '  [!] The securely saved runtime credential could not be decrypted.' -ForegroundColor Yellow
      Write-Host '      It may belong to a different Windows user/profile or be damaged.'
      Write-Host '      Enter a replacement credential to continue.'
      Write-Host ''
      Read-Host '  Press Enter to continue' | Out-Null
    } finally {
      $savedCredential = $null
    }
  }

  while ($true) {
    Show-Header -RightText 'Setup  4 / 6'
    Write-Host '  [>>] RUNTIME API KEY'
    Write-Host ''
    Write-Host '  Create a RESTRICTED runtime key with:'
    Write-Host ''
    Write-Host '      Tunnels'
    Write-Host '        [x] Read'
    Write-Host '        [x] Use'
    Write-Host '        [ ] Manage'
    Write-Host ''
    Write-Host '  Windows Coding Agent can remember the key using Windows DPAPI.'
    Write-Host '  The saved file contains encrypted ciphertext bound to this Windows user.'
    Write-Host '  The literal key is never written to config.json or wizard state.'
    Write-Host ''
    if (Test-SavedRuntimeCredential) {
      Write-Host '  Saved credential: [OK] encrypted for this Windows user' -ForegroundColor Green
      Write-Host ''
    }
    Write-Host '     [O] Open API Keys page'
    Write-Host '     [E] Enter runtime API key'
    Write-Host '     [B] Back'
    Write-Host ''
    $choice = Read-Choice '  Select' @('O','E','B')
    if ($choice -eq 'O') {
      Open-SetupPage $script:ApiKeysUrl | Out-Null
      continue
    }
    if ($choice -eq 'B') { return $false }

    $secureKey = Read-Host '  Runtime API key' -AsSecureString
    $bstr = [IntPtr]::Zero
    $plainKey = $null
    try {
      $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey)
      $plainKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
      if ([string]::IsNullOrWhiteSpace($plainKey)) {
        Write-Host '  [X] Runtime API key cannot be empty.' -ForegroundColor Red
        continue
      }

      $env:CONTROL_PLANE_API_KEY = $plainKey
      Write-Host ''
      Write-Host '  How should this key be handled?'
      Write-Host ''
      Write-Host '     [1] Save securely for this Windows user   (recommended)'
      Write-Host '     [2] Use only for this session'
      Write-Host ''
      $storageChoice = Read-Choice '  Select' @('1','2')
      if ($storageChoice -eq '1') {
        try {
          Save-RuntimeCredential -PlainText $plainKey
          Write-Host ''
          Write-Host '  [OK] Runtime credential saved with Windows DPAPI.' -ForegroundColor Green
        } catch {
          Write-Host ''
          Write-Host '  [!] Secure save failed. The key will be used for this session only.' -ForegroundColor Yellow
          Write-Host ('      {0}' -f $_.Exception.Message)
        }
      } else {
        Remove-SavedRuntimeCredential
        Write-Host ''
        Write-Host '  [OK] Session-only mode selected. No saved credential remains.'
      }
      return $true
    } finally {
      if ($bstr -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
      $plainKey = $null
    }
  }
}

function Invoke-TunnelDoctor {
  param($State, [string]$ClientPath)

  Show-Header -RightText 'Connection check'
  Write-Host '  Checking OpenAI tunnel and local MCP configuration...'
  Write-Host ''
  & $ClientPath doctor --profile $State.profileName --explain
  if ($LASTEXITCODE -ne 0) {
    Write-Host ''
    Write-Host '  [X] Tunnel diagnostic failed.' -ForegroundColor Red
    Write-Host ''
    Write-Host '  Common causes:'
    Write-Host '    - runtime key is incorrect'
    Write-Host '    - Tunnels Read or Use permission is missing'
    Write-Host '    - tunnel belongs to another workspace'
    Write-Host '    - local MCP command cannot start'
    return $false
  }

  $State.profileConfigured = $true
  $State.lastDoctorOk = (Get-Date).ToUniversalTime().ToString('o')
  Save-ConnectionState -State $State
  Write-Host ''
  Write-Host '  +--------------------+'
  Write-Host '  |     ALL GREEN      |'
  Write-Host '  +--------------------+'
  return $true
}

function Get-McpCommand {
  param([string]$ServerPath)

  if ([string]::IsNullOrWhiteSpace($ServerPath)) {
    throw 'MCP server path cannot be empty.'
  }

  $fullPath = [System.IO.Path]::GetFullPath($ServerPath)
  $serverUri = ([System.Uri]::new($fullPath)).AbsoluteUri

  # Keep the stored command quote-free. Windows PowerShell 5.1 can
  # strip embedded quotes while forwarding native arguments, turning
  # C:\Program Files\... into a bogus C:\Program executable token.
  # A file URI percent-encodes spaces and remains one safe argument.
  return "node --import=$serverUri -e 0"
}

function Configure-TunnelProfile {
  param($State, [string]$ClientPath, [string]$NodePath)

  if (-not (Test-ProfileName $State.profileName)) {
    throw 'Invalid tunnel profile name.'
  }
  $mcpCommand = Get-McpCommand -ServerPath $script:ServerPath

  Show-Header -RightText 'Setup  5 / 6'
  Write-Host '  [>>] CONFIGURE LOCAL BRIDGE'
  Write-Host ''
  Write-Status 'Profile' $State.profileName
  Write-Status 'Tunnel' $State.tunnelId
  Write-Status 'MCP server' $script:ServerPath
  Write-Host ''
  Write-Host '  Configuring the Secure MCP Tunnel profile...'
  Write-Host ''

  & $ClientPath init --force --sample sample_mcp_stdio_local --profile $State.profileName --tunnel-id $State.tunnelId --mcp-command $mcpCommand
  if ($LASTEXITCODE -ne 0) {
    Write-Host "  [X] tunnel-client init failed with exit code $LASTEXITCODE." -ForegroundColor Red
    Write-Host '  [!] This failed while building the local MCP profile.' -ForegroundColor Yellow
    Write-Host '      Re-entering the API key will not fix an MCP command preflight error.'
    return $false
  }

  return (Invoke-TunnelDoctor -State $State -ClientPath $ClientPath)
}

function Show-ChatGPTSteps {
  param([string]$ResolvedTunnelId = '')

  Show-Header -RightText 'Setup  6 / 6'
  Write-Host '  [>>] CONNECT CHATGPT'
  Write-Host ''
  Write-Host '  In ChatGPT create/connect a custom MCP app:'
  Write-Host ''
  Write-Host '      Connection     Tunnel'
  if (-not [string]::IsNullOrWhiteSpace($ResolvedTunnelId)) {
    Write-Host ('      Tunnel ID      {0}' -f $ResolvedTunnelId)
  } else {
    Write-Host '      Tunnel ID      same tunnel used by this PC'
  }
  Write-Host '      Authentication None'
  Write-Host ''
  Write-Host '  Allow the Read and Write actions you want ChatGPT to use.'
  Write-Host '  Recommended write approval: Always ask.'
  Write-Host ''
  Write-Host '  Suggested first prompt:'
  Write-Host '    Use Windows Coding Agent. List my authorized repositories.'
  Write-Host '    Do not modify anything yet.'
  Write-Host ''
  Write-Rule
  Write-Host "  ChatGPT settings : $script:ChatGPTUrl"
  Write-Host "  Platform tunnels : $script:TunnelsUrl"
  Write-Host "  Runtime API keys : $script:ApiKeysUrl"
  Write-Host "  Tunnel client    : $script:TunnelClientUrl"
  Write-Host ''
}

function Invoke-ChatGPTSetupStep {
  param($State)

  while ($true) {
    Show-ChatGPTSteps -ResolvedTunnelId $State.tunnelId
    Write-Host '     [O] Open ChatGPT connection settings'
    Write-Host '     [C] I created/connected the app'
    Write-Host '     [S] Skip for now'
    Write-Host '     [B] Back'
    Write-Host ''
    $choice = Read-Choice '  Select' @('O','C','S','B')
    if ($choice -eq 'O') {
      Open-SetupPage $script:ChatGPTUrl | Out-Null
      continue
    }
    if ($choice -eq 'C') {
      $State.chatgptConfigured = $true
      Save-ConnectionState -State $State
      return 'complete'
    }
    if ($choice -eq 'S') { return 'skipped' }
    return 'back'
  }
}

function Test-LocalPrerequisites {
  param([switch]$Interactive)

  $node = Get-NodePath
  $git = Get-GitPath
  $repoCount = Get-RepositoryCount

  Show-Header -RightText 'Setup  1 / 6'
  Write-Host '  LOCAL READINESS'
  Write-Host ''
  Write-Status 'Node.js' $(if ($node) { '[OK]' } else { '[X]' })
  Write-Status 'Git' $(if ($git) { '[OK]' } else { '[X]' })
  Write-Status 'Authorized repositories' $(if ($repoCount -gt 0) { "[OK] $repoCount" } else { '[--] none' })
  Write-Host ''

  if ($node -and $git -and $repoCount -gt 0) {
    Write-Host '  [OK] Local coding agent is ready.' -ForegroundColor Green
    if ($Interactive) { Read-Host '  Press Enter to continue' | Out-Null }
    return $true
  }

  if (-not $node) { Write-Host '  [X] Install Node.js 20 or newer before continuing.' -ForegroundColor Red }
  if (-not $git) { Write-Host '  [X] Install Git for Windows before continuing.' -ForegroundColor Red }
  if ($repoCount -eq 0) {
    Write-Host '  [!] No local Git repositories are authorized yet.' -ForegroundColor Yellow
    if ($Interactive -and (Test-Path -LiteralPath $script:SetupCmd -PathType Leaf)) {
      Write-Host ''
      Write-Host '     [S] Run repository setup now'
      Write-Host '     [B] Back'
      $choice = Read-Choice '  Select' @('S','B')
      if ($choice -eq 'S') {
        & cmd.exe /c $script:SetupCmd
        if ($LASTEXITCODE -eq 0 -and (Get-RepositoryCount) -gt 0) { return $true }
      }
    }
  }
  return $false
}

function Invoke-GuidedSetup {
  param($State)

  if (-not (Test-Path -LiteralPath $script:ServerPath -PathType Leaf)) {
    throw "Windows Coding Agent MCP entrypoint not found: $script:ServerPath"
  }
  if (-not (Test-LocalPrerequisites -Interactive)) {
    Read-Host '  Press Enter to return to the menu' | Out-Null
    return
  }

  $nodePath = Get-NodePath
  $clientPath = Select-TunnelClient -State $State -StepNumber 2
  if (-not $clientPath) { return }

  $resolvedTunnelId = Get-TunnelIdStep -State $State
  if (-not $resolvedTunnelId) { return }

  if (-not (Read-RuntimeApiKey)) { return }

  $bridgeReady = Configure-TunnelProfile -State $State -ClientPath $clientPath -NodePath $nodePath
  while (-not $bridgeReady) {
    Write-Host ''
    Write-Host '  The local bridge is not configured yet.'
    Write-Host ''
    Write-Host '     [1] Retry local bridge configuration'
    Write-Host '     [2] Re-enter runtime API key, then retry'
    Write-Host '     [3] Open API Keys page'
    Write-Host '     [B] Return to menu'
    $choice = Read-Choice '  Select' @('1','2','3','B')
    if ($choice -eq '1') {
      $bridgeReady = Configure-TunnelProfile -State $State -ClientPath $clientPath -NodePath $nodePath
      continue
    }
    if ($choice -eq '2') {
      if (Read-RuntimeApiKey -ForcePrompt) {
        $bridgeReady = Configure-TunnelProfile -State $State -ClientPath $clientPath -NodePath $nodePath
      }
      continue
    }
    if ($choice -eq '3') {
      Open-SetupPage $script:ApiKeysUrl | Out-Null
      continue
    }
    return
  }

  $chatgptResult = Invoke-ChatGPTSetupStep -State $State
  if ($chatgptResult -eq 'back') { return }

  Show-Header
  Write-Host '                  +----------------------+'
  Write-Host '                  |    SETUP COMPLETE    |'
  Write-Host '                  +----------------------+'
  Write-Host ''
  Write-Host '                         ChatGPT'
  Write-Host '                            |'
  Write-Host '                            v'
  Write-Host '                  +-------------------+'
  Write-Host '                  | Secure MCP Tunnel |'
  Write-Host '                  +-------------------+'
  Write-Host '                            |'
  Write-Host '                            v'
  Write-Host '                  +-------------------+'
  Write-Host '                  | Windows Coding    |'
  Write-Host '                  | Agent             |'
  Write-Host '                  +-------------------+'
  Write-Host '                            |'
  Write-Host '                            v'
  Write-Host '                  +-------------------+'
  Write-Host '                  | Authorized Git    |'
  Write-Host '                  | Repositories      |'
  Write-Host '                  +-------------------+'
  Write-Host ''
  if ($ConfigureOnly) {
    Write-Host '  Configuration is saved. Run Connect-ChatGPT.cmd when you want to start the bridge.'
    Read-Host '  Press Enter to return to the menu' | Out-Null
    return
  }
  Write-Host '     [1] Start ChatGPT bridge now'
  Write-Host '     [2] Open ChatGPT'
  Write-Host '     [B] Return to menu'
  Write-Host ''
  $choice = Read-Choice '  Select' @('1','2','B')
  if ($choice -eq '1') { Start-ChatGPTBridge -State $State }
  if ($choice -eq '2') { Open-SetupPage 'https://chatgpt.com/' | Out-Null }
}

function Start-ChatGPTBridge {
  param($State)

  $clientPath = Get-ExistingTunnelClientPath -State $State
  if (-not $clientPath -or -not (Test-TunnelId $State.tunnelId)) {
    Write-Host '  [!] ChatGPT connection is not fully configured. Starting guided setup.' -ForegroundColor Yellow
    Read-Host '  Press Enter to continue' | Out-Null
    Invoke-GuidedSetup -State $State
    return
  }

  if (-not (Read-RuntimeApiKey)) { return }
  if (-not (Invoke-TunnelDoctor -State $State -ClientPath $clientPath)) {
    Read-Host '  Press Enter to return to the menu' | Out-Null
    return
  }

  Show-Header
  Write-Host '  CHATGPT BRIDGE READY TO START'
  Write-Host ''
  Write-Status 'Tunnel' $State.tunnelId
  Write-Status 'Profile' $State.profileName
  Write-Status 'Repository access' "[OK] $(Get-RepositoryCount) authorized"
  Write-Host ''
  Write-Host '  Keep this window open while ChatGPT uses your local repositories.'
  Write-Host '  Press Ctrl+C to stop the bridge and return to the terminal.'
  Write-Host ''
  $open = Read-Host '  Open ChatGPT before starting? [Y/n]'
  if ([string]::IsNullOrWhiteSpace($open) -or $open -match '^[Yy]') {
    Open-SetupPage 'https://chatgpt.com/' | Out-Null
  }
  Write-Host ''
  Write-Host '  Starting Secure MCP Tunnel...' -ForegroundColor Green
  Write-Host ''
  & $clientPath run --profile $State.profileName
  $exitCode = $LASTEXITCODE
  Write-Host ''
  if ($exitCode -eq 0) {
    Write-Host '  [OK] ChatGPT bridge stopped.'
  } else {
    Write-Host "  [X] ChatGPT bridge exited with code $exitCode." -ForegroundColor Red
  }
  Read-Host '  Press Enter to return to the menu' | Out-Null
}

function Invoke-Diagnostics {
  param($State)

  Show-Header -RightText 'Diagnostics'
  $nodePath = Get-NodePath
  $gitPath = Get-GitPath
  $repoCount = Get-RepositoryCount
  $clientPath = Get-ExistingTunnelClientPath -State $State

  Write-Status 'Node.js' $(if ($nodePath) { '[OK]' } else { '[X]' })
  Write-Status 'Git' $(if ($gitPath) { '[OK]' } else { '[X]' })
  Write-Status 'Repository registry' $(if ($repoCount -gt 0) { "[OK] $repoCount authorized" } else { '[--] none' })
  Write-Status 'Tunnel client' $(if ($clientPath) { '[OK]' } else { '[--] not found' })
  Write-Status 'Tunnel ID' $(if (Test-TunnelId $State.tunnelId) { '[OK]' } else { '[--] not configured' })
  Write-Status 'ChatGPT app step' $(if ($State.chatgptConfigured) { '[OK]' } else { '[--] not confirmed' })
  Write-Host ''

  if ($nodePath -and (Test-Path -LiteralPath (Join-Path $script:RepoRoot 'src\doctor.js') -PathType Leaf)) {
    Write-Rule
    Write-Host '  Running local Windows Coding Agent doctor...'
    Write-Host ''
    & $nodePath (Join-Path $script:RepoRoot 'src\doctor.js')
  }

  if ($clientPath -and (Test-TunnelId $State.tunnelId)) {
    Write-Host ''
    Write-Host '     [F] Run full tunnel diagnostic'
    Write-Host '     [O] Open ChatGPT connection settings'
    Write-Host '     [B] Back'
    Write-Host ''
    $choice = Read-Choice '  Select' @('F','O','B')
    if ($choice -eq 'F') {
      if (Read-RuntimeApiKey) { Invoke-TunnelDoctor -State $State -ClientPath $clientPath | Out-Null }
      Read-Host '  Press Enter to continue' | Out-Null
    }
    if ($choice -eq 'O') { Open-SetupPage $script:ChatGPTUrl | Out-Null }
  } else {
    Read-Host '  Press Enter to return to the menu' | Out-Null
  }
}

function Invoke-CredentialMenu {
  param($State)

  while ($true) {
    Show-Header -RightText 'Runtime credential'
    Write-Status 'Securely saved' $(if (Test-SavedRuntimeCredential) { '[OK] DPAPI / current user' } else { '[--] not saved' })
    Write-Status 'Current process' $(if (-not [string]::IsNullOrWhiteSpace($env:CONTROL_PLANE_API_KEY)) { '[OK] loaded' } else { '[--] not loaded' })
    Write-Host ''
    Write-Host '     [1] Enter / replace runtime credential'
    Write-Host '     [2] Test saved credential'
    Write-Host '     [3] Forget saved credential'
    Write-Host '     [B] Back'
    Write-Host ''
    $choice = Read-Choice '  Select' @('1','2','3','B')
    if ($choice -eq 'B') { return }

    if ($choice -eq '1') {
      $env:CONTROL_PLANE_API_KEY = $null
      if (Read-RuntimeApiKey -ForcePrompt) {
        $clientPath = Get-ExistingTunnelClientPath -State $State
        if ($clientPath -and (Test-TunnelId $State.tunnelId)) {
          Invoke-TunnelDoctor -State $State -ClientPath $clientPath | Out-Null
          Read-Host '  Press Enter to continue' | Out-Null
        }
      }
      continue
    }

    if ($choice -eq '2') {
      if (-not (Test-SavedRuntimeCredential)) {
        Write-Host ''
        Write-Host '  [!] No securely saved runtime credential exists.' -ForegroundColor Yellow
        Read-Host '  Press Enter to continue' | Out-Null
        continue
      }
      $env:CONTROL_PLANE_API_KEY = $null
      try {
        $savedCredential = Load-RuntimeCredential
        if ([string]::IsNullOrWhiteSpace($savedCredential)) { throw 'Saved credential decrypted to an empty value.' }
        $env:CONTROL_PLANE_API_KEY = $savedCredential
        $savedCredential = $null
        $clientPath = Get-ExistingTunnelClientPath -State $State
        if ($clientPath -and (Test-TunnelId $State.tunnelId)) {
          Invoke-TunnelDoctor -State $State -ClientPath $clientPath | Out-Null
        } else {
          Write-Host ''
          Write-Host '  [OK] Saved credential decrypted successfully.' -ForegroundColor Green
          Write-Host '      Configure a tunnel before running the full remote diagnostic.'
        }
      } catch {
        Write-Host ''
        Write-Host '  [X] Saved credential could not be used.' -ForegroundColor Red
        Write-Host ('      {0}' -f $_.Exception.Message)
      } finally {
        $savedCredential = $null
      }
      Read-Host '  Press Enter to continue' | Out-Null
      continue
    }

    Remove-SavedRuntimeCredential
    $env:CONTROL_PLANE_API_KEY = $null
    Write-Host ''
    Write-Host '  [OK] Saved runtime credential removed. Future starts will ask again.' -ForegroundColor Green
    Read-Host '  Press Enter to continue' | Out-Null
  }
}
function Invoke-ReconfigureMenu {
  param($State)

  while ($true) {
    Show-Header -RightText 'Reconfigure'
    Write-Host '  Change only the piece you need.'
    Write-Host ''
    Write-Host '     [1] Change tunnel ID'
    Write-Host '     [2] Change tunnel-client location'
    Write-Host '     [3] Manage runtime credential'
    Write-Host '     [4] Re-open ChatGPT app setup'
    Write-Host '     [5] Manage authorized repositories'
    Write-Host '     [B] Back'
    Write-Host ''
    $choice = Read-Choice '  Select' @('1','2','3','4','5','B')
    if ($choice -eq 'B') { return }
    if ($choice -eq '1') {
      $State.tunnelId = ''
      $State.profileConfigured = $false
      $State.chatgptConfigured = $false
      Save-ConnectionState -State $State
      Get-TunnelIdStep -State $State | Out-Null
      continue
    }
    if ($choice -eq '2') {
      $State.tunnelClientPath = ''
      $State.profileConfigured = $false
      Save-ConnectionState -State $State
      Select-TunnelClient -State $State | Out-Null
      continue
    }
    if ($choice -eq '3') {
      Invoke-CredentialMenu -State $State
      continue
    }
    if ($choice -eq '4') {
      Invoke-ChatGPTSetupStep -State $State | Out-Null
      continue
    }
    if ($choice -eq '5') {
      if (Test-Path -LiteralPath $script:ManagerCmd -PathType Leaf) {
        & cmd.exe /c $script:ManagerCmd
      }
      continue
    }
  }
}

function Reset-ChatGPTConnection {
  if (Test-Path -LiteralPath $script:StatePath -PathType Leaf) {
    Remove-Item -LiteralPath $script:StatePath -Force
  }
  Remove-SavedRuntimeCredential
  $env:CONTROL_PLANE_API_KEY = $null
  $env:CONTROL_PLANE_TUNNEL_ID = $null
}

function Invoke-FreshSetupMenu {
  while ($true) {
    Show-Header -RightText 'Start fresh'
    Write-Host '  What would you like to reset?'
    Write-Host ''
    Write-Host '     [1] ChatGPT connection only        (recommended)'
    Write-Host ''
    Write-Host '         Resets: tunnel ID, launcher path, wizard progress'
    Write-Host '         Keeps : repository authorization and worktrees'
    Write-Host ''
    Write-Host '     [2] Full Windows Coding Agent setup'
    Write-Host ''
    Write-Host '         Backs up and clears repository authorization plus'
    Write-Host '         the ChatGPT connection. Worktrees are NOT deleted.'
    Write-Host ''
    Write-Host '     [B] Cancel'
    Write-Host ''
    $choice = Read-Choice '  Select' @('1','2','B')
    if ($choice -eq 'B') { return }
    if ($choice -eq '1') {
      Reset-ChatGPTConnection
      Write-Host ''
      Write-Host '  [OK] ChatGPT connection state cleared.' -ForegroundColor Green
      Write-Host '  Existing tunnel-client profile files are left untouched and'
      Write-Host '  will be overwritten safely by the next guided setup.'
      Read-Host '  Press Enter to continue' | Out-Null
      return
    }

    Write-Host ''
    Write-Host '  [!] Full reset removes local repository authorization.' -ForegroundColor Yellow
    Write-Host '  Existing repositories and worktrees remain on disk.'
    $confirm = Read-Host '  Type RESET to continue'
    if ($confirm -cne 'RESET') {
      Write-Host '  Cancelled.'
      Read-Host '  Press Enter to continue' | Out-Null
      return
    }

    Reset-ChatGPTConnection
    if (Test-Path -LiteralPath $script:ConfigPath -PathType Leaf) {
      $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
      $backup = Join-Path $script:AgentHome "config.backup.$stamp.json"
      Copy-Item -LiteralPath $script:ConfigPath -Destination $backup -Force
      Remove-Item -LiteralPath $script:ConfigPath -Force
      Write-Host "  [OK] Previous repository registry backed up to: $backup"
    }
    if (Test-Path -LiteralPath $script:SetupCmd -PathType Leaf) {
      $runSetup = Read-Host '  Run repository setup now? [Y/n]'
      if ([string]::IsNullOrWhiteSpace($runSetup) -or $runSetup -match '^[Yy]') {
        & cmd.exe /c $script:SetupCmd
      }
    }
    return
  }
}

function Show-MainMenu {
  while ($true) {
    $state = Load-ConnectionState
    if (Test-ProfileName $ProfileName) { $state.profileName = $ProfileName }
    $repoCount = Get-RepositoryCount
    $clientPath = Get-ExistingTunnelClientPath -State $state

    Show-Header
    Write-Host '  Connection status'
    Write-Host ''
    Write-Status 'Local repositories' $(if ($repoCount -gt 0) { "[OK] $repoCount authorized" } else { '[--] not configured' })
    Write-Status 'Tunnel client' $(if ($clientPath) { '[OK] found' } else { '[--] not configured' })
    Write-Status 'OpenAI tunnel' $(if (Test-TunnelId $state.tunnelId) { '[OK] configured' } else { '[--] not configured' })
    Write-Status 'Runtime credential' $(if (Test-SavedRuntimeCredential) { '[OK] securely saved' } elseif (-not [string]::IsNullOrWhiteSpace($env:CONTROL_PLANE_API_KEY)) { '[OK] session only' } else { '[--] prompt on start' })
    Write-Status 'ChatGPT app' $(if ($state.chatgptConfigured) { '[OK] confirmed' } else { '[--] not confirmed' })
    Write-Host ''
    Write-Rule
    Write-Host ''
    if ($state.profileConfigured -and (Test-TunnelId $state.tunnelId) -and $clientPath) {
      Write-Host '     [1] Start ChatGPT bridge'
    } else {
      Write-Host '     [1] Start guided setup'
    }
    Write-Host '     [2] Setup / resume / reconfigure'
    Write-Host '     [3] Diagnostics'
    Write-Host '     [4] Manage repositories'
    Write-Host '     [5] Start fresh setup'
    Write-Host '     [Q] Quit'
    Write-Host ''
    $choice = Read-Choice '  Select' @('1','2','3','4','5','Q')
    if ($choice -eq 'Q') { return }
    if ($choice -eq '1') {
      if ($state.profileConfigured -and (Test-TunnelId $state.tunnelId) -and $clientPath) {
        Start-ChatGPTBridge -State $state
      } else {
        Invoke-GuidedSetup -State $state
      }
      continue
    }
    if ($choice -eq '2') {
      if ($state.profileConfigured -or (Test-TunnelId $state.tunnelId) -or $clientPath) {
        Show-Header -RightText 'Setup options'
        Write-Host '     [1] Resume / run guided setup'
        Write-Host '     [2] Reconfigure one item'
        Write-Host '     [B] Back'
        Write-Host ''
        $sub = Read-Choice '  Select' @('1','2','B')
        if ($sub -eq '1') { Invoke-GuidedSetup -State $state }
        if ($sub -eq '2') { Invoke-ReconfigureMenu -State $state }
      } else {
        Invoke-GuidedSetup -State $state
      }
      continue
    }
    if ($choice -eq '3') { Invoke-Diagnostics -State $state; continue }
    if ($choice -eq '4') {
      if (Test-Path -LiteralPath $script:ManagerCmd -PathType Leaf) { & cmd.exe /c $script:ManagerCmd }
      continue
    }
    if ($choice -eq '5') { Invoke-FreshSetupMenu; continue }
  }
}

if (-not (Test-ProfileName $ProfileName)) {
  throw 'ProfileName may contain only letters, numbers, dot, underscore, and hyphen.'
}

if ($SelfTest) {
  $state = New-ConnectionState
  $keys = @($state.Keys) -join ','
  if ($keys -match '(?i)api.?key|secret|token') { throw 'Connection state must never contain secret fields.' }
  if (-not (Test-TunnelId 'tunnel_abc123')) { throw 'Tunnel ID validation rejected a valid ID.' }
  if (Test-TunnelId 'not-a-tunnel') { throw 'Tunnel ID validation accepted an invalid ID.' }
  if (-not (Test-ProfileName 'windows-coding-agent')) { throw 'Profile validation rejected the default profile.' }
  $spacePath = Join-Path ([System.IO.Path]::GetTempPath()) 'Windows Coding Agent Path With Spaces\src\index.js'
  $mcpCommand = Get-McpCommand -ServerPath $spacePath
  if ($mcpCommand.Contains('"') -or $mcpCommand.Contains("'")) { throw 'MCP command must remain quote-free for Windows PowerShell 5.1.' }
  if (-not $mcpCommand.StartsWith('node --import=file:///')) { throw "Unexpected MCP command prefix: $mcpCommand" }
  if ($mcpCommand -notmatch '%20') { throw "MCP command did not URI-encode spaces: $mcpCommand" }
  if (-not $mcpCommand.EndsWith(' -e 0')) { throw "Unexpected MCP command suffix: $mcpCommand" }
  $credentialTestRoot = Join-Path ([IO.Path]::GetTempPath()) ('wca-dpapi-selftest-' + [Guid]::NewGuid().ToString('N'))
  $credentialTestPath = Join-Path $credentialTestRoot 'runtime.dpapi'
  $credentialProbe = 'wca-dpapi-probe-' + [Guid]::NewGuid().ToString('N')
  try {
    Save-RuntimeCredential -PlainText $credentialProbe -Path $credentialTestPath
    if (-not (Test-SavedRuntimeCredential -Path $credentialTestPath)) { throw 'DPAPI credential file was not created.' }
    $cipherBytes = [IO.File]::ReadAllBytes($credentialTestPath)
    $cipherText = [Text.Encoding]::UTF8.GetString($cipherBytes)
    if ($cipherText.Contains($credentialProbe)) { throw 'DPAPI credential file contains the plaintext probe.' }
    $roundTrip = Load-RuntimeCredential -Path $credentialTestPath
    if ($roundTrip -ne $credentialProbe) { throw 'DPAPI credential round-trip did not recover the original value.' }
  } finally {
    $credentialProbe = $null
    $roundTrip = $null
    if (Test-Path -LiteralPath $credentialTestRoot) { Remove-Item -LiteralPath $credentialTestRoot -Recurse -Force }
  }
  Write-Host 'SELFTEST OK - wizard state is secret-free; validators, quote-safe MCP command, and DPAPI credential round-trip passed.'
  exit 0
}

if ($ShowInstructions) {
  Show-ChatGPTSteps -ResolvedTunnelId $TunnelId
  exit 0
}

if ($ResetSetup) {
  Reset-ChatGPTConnection
  Write-Host 'ChatGPT connection wizard state was cleared. Repository authorization was not changed.'
}

Show-MainMenu
