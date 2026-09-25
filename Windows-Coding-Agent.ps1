param(
  [string]$TunnelId = '',
  [string]$ProfileName = 'windows-coding-agent',
  [string]$TunnelClient = '',
  [switch]$ConfigureOnly,
  [switch]$ShowInstructions,
  [switch]$ResetSetup,
  [switch]$RepairOnly,
  [switch]$SelfTest,
  [ValidateSet('Menu','Repositories')]
  [string]$Open = 'Menu'
)

$ErrorActionPreference = 'Stop'

$script:TunnelsUrl = 'https://platform.openai.com/settings/organization/tunnels'
$script:ApiKeysUrl = 'https://platform.openai.com/settings/organization/api-keys'
$script:ChatGPTUrl = 'https://chatgpt.com/#settings/Connectors'
$script:TunnelClientUrl = 'https://github.com/openai/tunnel-client/releases/latest'
$script:RepoRoot = (Resolve-Path $PSScriptRoot).Path
$script:ToolchainScript = Join-Path $script:RepoRoot 'Toolchain.ps1'
if (-not (Test-Path -LiteralPath $script:ToolchainScript -PathType Leaf)) {
  throw "Toolchain.ps1 was not found: $script:ToolchainScript"
}
. $script:ToolchainScript
$script:CurrentVersion = Get-WcaPackageVersion -SourceRoot $script:RepoRoot
$script:BootstrapPath = Get-WcaStableMcpBootstrapPath
$script:SetupCmd = Join-Path $script:RepoRoot 'Setup.cmd'
$script:RepositoryManagerScript = Join-Path $script:RepoRoot 'src\startup.js'
$script:DependencyInstaller = Join-Path $script:RepoRoot 'Install-Dependencies.ps1'
$script:Updater = Join-Path $script:RepoRoot 'Update.ps1'

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
    mcpCommand = ''
    managedVersion = ''
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
      if (-not [string]::IsNullOrWhiteSpace([string]$raw.mcpCommand)) { $state.mcpCommand = [string]$raw.mcpCommand }
      if (-not [string]::IsNullOrWhiteSpace([string]$raw.managedVersion)) { $state.managedVersion = [string]$raw.managedVersion }
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
  return (Resolve-WcaToolPath -Name node)
}

function Invoke-RepositoryManager {
  $node = Get-NodePath
  if (-not $node) { throw 'Node.js is unavailable. Use Maintenance -> Dependencies from Windows-Coding-Agent.cmd.' }
  if (-not (Test-Path -LiteralPath $script:RepositoryManagerScript -PathType Leaf)) {
    throw "Repository manager is missing: $script:RepositoryManagerScript"
  }
  & $node $script:RepositoryManagerScript
  if ($LASTEXITCODE -ne 0) { throw "Repository manager exited with code $LASTEXITCODE." }
}
function Get-GitPath {
  return (Resolve-WcaToolPath -Name git)
}

function Get-NpmPath {
  return (Resolve-WcaToolPath -Name npm)
}

function Get-NpxPath {
  return (Resolve-WcaToolPath -Name npx)
}
function Get-ExistingTunnelClientPath {
  param($State)

  $hints = @()
  if (-not [string]::IsNullOrWhiteSpace($TunnelClient)) { $hints += $TunnelClient }
  if (-not [string]::IsNullOrWhiteSpace($env:TUNNEL_CLIENT_BIN)) { $hints += $env:TUNNEL_CLIENT_BIN }
  if (-not [string]::IsNullOrWhiteSpace([string]$State.tunnelClientPath)) { $hints += [string]$State.tunnelClientPath }

  foreach ($hint in $hints) {
    $resolved = Resolve-WcaToolPath -Name tunnelClient -Hint $hint.Trim('"')
    if ($resolved) { return $resolved }
  }
  return (Resolve-WcaToolPath -Name tunnelClient)
}
function Select-TunnelClient {
  param($State, [int]$StepNumber = 2)

  while ($true) {
    $existing = Get-ExistingTunnelClientPath -State $State
    if ($existing) {
      $State.tunnelClientPath = $existing
      Save-ConnectionState -State $State
      Refresh-WcaToolchain -TunnelClientHint $existing | Out-Null
      return $existing
    }

    Show-Header -RightText "Setup  $StepNumber / 6"
    Write-Host '  [>>] OPENAI SECURE MCP TUNNEL CLIENT'
    Write-Host ''
    Write-Host '  The official tunnel client connects this PC to ChatGPT'
    Write-Host '  using an outbound-only encrypted connection.'
    Write-Host ''
    Write-Host '     [1] Install official tunnel-client automatically'
    Write-Host '     [2] Open official download page'
    Write-Host '     [3] Enter path to tunnel-client.exe'
    Write-Host '     [4] Scan again'
    Write-Host '     [B] Back'
    Write-Host ''
    $choice = Read-Choice '  Select' @('1','2','3','4','B')
    if ($choice -eq '1') {
      try {
        $resolved = Install-WcaTunnelClient
        $State.tunnelClientPath = $resolved
        Save-ConnectionState -State $State
        return $resolved
      } catch {
        Write-Host ''
        Write-Host ('  [X] Automatic tunnel-client installation failed: {0}' -f $_.Exception.Message) -ForegroundColor Red
        Write-Host '      You can use the official download page instead.'
        Read-Host '  Press Enter to continue' | Out-Null
      }
      continue
    }
    if ($choice -eq '2') {
      Open-SetupPage $script:TunnelClientUrl | Out-Null
      continue
    }
    if ($choice -eq '3') {
      $manualPath = (Read-Host '  Full path to tunnel-client.exe').Trim().Trim('"')
      if (Test-Path -LiteralPath $manualPath -PathType Leaf) {
        $resolved = (Resolve-Path -LiteralPath $manualPath).Path
        $State.tunnelClientPath = $resolved
        Save-ConnectionState -State $State
        Refresh-WcaToolchain -TunnelClientHint $resolved | Out-Null
        return $resolved
      }
      Write-Host '  [X] That file was not found.' -ForegroundColor Red
      Read-Host '  Press Enter to continue' | Out-Null
      continue
    }
    if ($choice -eq '4') {
      Refresh-WcaToolchain | Out-Null
      continue
    }
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


function Invoke-TunnelNative {
  param(
    [Parameter(Mandatory = $true)][string]$ClientPath,
    [Parameter(Mandatory = $true)][string[]]$Arguments
  )
  try {
    & $ClientPath @Arguments
    return [pscustomobject]@{ ok = ($LASTEXITCODE -eq 0); exitCode = $LASTEXITCODE; blocked = $false; message = '' }
  } catch {
    $message = $_.Exception.Message
    if (Test-WcaApplicationControlMessage $message) {
      Show-WcaApplicationControlHelp -Path $ClientPath -Message $message
      return [pscustomobject]@{ ok = $false; exitCode = -1; blocked = $true; message = $message }
    }
    Write-Host ''
    Write-Host ('  [X] tunnel-client could not start: {0}' -f $message) -ForegroundColor Red
    return [pscustomobject]@{ ok = $false; exitCode = -1; blocked = $false; message = $message }
  }
}

function Ensure-LocalManagedRuntime {
  param([switch]$Quiet)

  try {
    if (-not $Quiet) {
      Show-Header -RightText 'Local runtime'
      Write-Host '  Preparing the stable managed Windows Coding Agent runtime...'
      Write-Host ''
    }
    $installed = Install-WcaManagedVersion -SourceRoot $script:RepoRoot
    $script:BootstrapPath = Get-WcaStableMcpBootstrapPath
    if (-not (Test-Path -LiteralPath $script:BootstrapPath -PathType Leaf)) {
      throw "Stable MCP bootstrap was not created: $script:BootstrapPath"
    }
    if (-not $Quiet) {
      Write-Status 'Managed version' ('[OK] v' + [string]$installed.version)
      Write-Status 'Stable MCP bootstrap' '[OK]'
    }
    return $installed
  } catch {
    if (-not $Quiet) {
      Write-Host ('  [X] Managed runtime preparation failed: {0}' -f $_.Exception.Message) -ForegroundColor Red
    }
    return $null
  }
}

function Ensure-TunnelProfileCurrent {
  param($State, [string]$ClientPath)

  $mcpCommand = Get-McpCommand -ServerPath $script:BootstrapPath
  $needsRepair = (-not $State.profileConfigured) -or ([string]$State.mcpCommand -ne $mcpCommand)
  if (-not $needsRepair) { return $true }

  Show-Header -RightText 'Self-heal'
  Write-Host '  Tunnel profile is missing or points at an older installation.'
  Write-Host '  Rebuilding it against the stable MCP bootstrap...'
  Write-Host ''
  $arguments = @('init','--force','--sample','sample_mcp_stdio_local','--profile',$State.profileName,'--tunnel-id',$State.tunnelId,'--mcp-command',$mcpCommand)
  $result = Invoke-TunnelNative -ClientPath $ClientPath -Arguments $arguments
  if (-not $result.ok) { return $false }

  $State.mcpCommand = $mcpCommand
  $State.managedVersion = $script:CurrentVersion
  $State.profileConfigured = $true
  Save-ConnectionState -State $State
  Write-Host '  [OK] Tunnel profile repaired.' -ForegroundColor Green
  return $true
}

function Invoke-TunnelDoctor {
  param($State, [string]$ClientPath)

  Show-Header -RightText 'Connection check'
  Write-Host '  Checking OpenAI tunnel and local MCP configuration...'
  Write-Host ''
  $result = Invoke-TunnelNative -ClientPath $ClientPath -Arguments @('doctor','--profile',$State.profileName,'--explain')
  if (-not $result.ok) {
    if (-not $result.blocked) {
      Write-Host ''
      Write-Host '  [X] Tunnel diagnostic failed.' -ForegroundColor Red
      Write-Host ''
      Write-Host '  Common causes:'
      Write-Host '    - runtime key is incorrect'
      Write-Host '    - Tunnels Read or Use permission is missing'
      Write-Host '    - tunnel belongs to another workspace'
      Write-Host '    - local MCP command cannot start'
    }
    return $false
  }

  $State.profileConfigured = $true
  $State.mcpCommand = Get-McpCommand -ServerPath $script:BootstrapPath
  $State.managedVersion = $script:CurrentVersion
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

  if (-not (Test-ProfileName $State.profileName)) { throw 'Invalid tunnel profile name.' }
  if (-not (Test-Path -LiteralPath $script:BootstrapPath -PathType Leaf)) {
    $managed = Ensure-LocalManagedRuntime
    if (-not $managed) { return $false }
  }

  $mcpCommand = Get-McpCommand -ServerPath $script:BootstrapPath
  Show-Header -RightText 'Setup  5 / 6'
  Write-Host '  [>>] CONFIGURE LOCAL BRIDGE'
  Write-Host ''
  Write-Status 'Profile' $State.profileName
  Write-Status 'Tunnel' $State.tunnelId
  Write-Status 'Stable MCP bootstrap' $script:BootstrapPath
  Write-Host ''
  Write-Host '  Configuring the Secure MCP Tunnel profile...'
  Write-Host ''

  $arguments = @('init','--force','--sample','sample_mcp_stdio_local','--profile',$State.profileName,'--tunnel-id',$State.tunnelId,'--mcp-command',$mcpCommand)
  $result = Invoke-TunnelNative -ClientPath $ClientPath -Arguments $arguments
  if (-not $result.ok) {
    if (-not $result.blocked) {
      Write-Host ('  [X] tunnel-client init failed with exit code {0}.' -f $result.exitCode) -ForegroundColor Red
      Write-Host '  [!] This failed while building the local MCP profile.' -ForegroundColor Yellow
      Write-Host '      Re-entering the API key will not fix an MCP command preflight error.'
    }
    return $false
  }

  $State.mcpCommand = $mcpCommand
  $State.managedVersion = $script:CurrentVersion
  $State.profileConfigured = $true
  Save-ConnectionState -State $State
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

  Refresh-WcaProcessPath
  $toolchain = Refresh-WcaToolchain
  $node = Get-NodePath
  $npm = Get-NpmPath
  $npx = Get-NpxPath
  $git = Get-GitPath
  $nodeSupported = $node -and (Test-WcaNodeSupported ([string]$toolchain.tools.node.version))
  $repoCount = Get-RepositoryCount

  Show-Header -RightText 'Setup  1 / 6'
  Write-Host '  LOCAL READINESS'
  Write-Host ''
  Write-Status 'Node.js 20+' $(if ($nodeSupported) { '[OK] ' + [string]$toolchain.tools.node.version } else { '[X]' })
  Write-Status 'npm' $(if ($npm) { '[OK]' } else { '[X]' })
  Write-Status 'npx' $(if ($npx) { '[OK]' } else { '[X]' })
  Write-Status 'Git' $(if ($git) { '[OK]' } else { '[X]' })
  Write-Status 'Authorized repositories' $(if ($repoCount -gt 0) { "[OK] $repoCount" } else { '[--] none' })
  Write-Host ''

  if ($nodeSupported -and $npm -and $npx -and $git -and $repoCount -gt 0) {
    Write-Host '  [OK] Local coding agent prerequisites are ready.' -ForegroundColor Green
    if ($Interactive) { Read-Host '  Press Enter to continue' | Out-Null }
    return $true
  }

  if (-not $nodeSupported -or -not $npm -or -not $npx -or -not $git) {
    Write-Host '  [!] One or more required development tools are missing or outdated.' -ForegroundColor Yellow
    if ($Interactive -and (Test-Path -LiteralPath $script:DependencyInstaller -PathType Leaf)) {
      Write-Host ''
      Write-Host '     [I] Install / repair required dependencies'
      Write-Host '     [B] Back'
      $dependencyChoice = Read-Choice '  Select' @('I','B')
      if ($dependencyChoice -eq 'I') {
        $powershell = Resolve-WcaToolPath -Name powershell
        & $powershell -NoProfile -ExecutionPolicy Bypass -File $script:DependencyInstaller -RequiredOnly
        if ($LASTEXITCODE -eq 0) { return (Test-LocalPrerequisites -Interactive:$false) }
      }
      return $false
    }
  }

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

  if (-not (Test-Path -LiteralPath (Join-Path $script:RepoRoot 'src\index.js') -PathType Leaf)) {
    throw "Windows Coding Agent MCP entrypoint not found under: $script:RepoRoot"
  }
  if (-not (Test-LocalPrerequisites -Interactive)) {
    Read-Host '  Press Enter to return to the menu' | Out-Null
    return
  }

  $managed = Ensure-LocalManagedRuntime
  if (-not $managed) {
    Read-Host '  Press Enter to return to the menu' | Out-Null
    return
  }
  $State.managedVersion = [string]$managed.version
  Save-ConnectionState -State $State

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
    Write-Host '     [4] Dependency / toolchain diagnostics'
    Write-Host '     [B] Return to menu'
    $choice = Read-Choice '  Select' @('1','2','3','4','B')
    if ($choice -eq '1') { $bridgeReady = Configure-TunnelProfile -State $State -ClientPath $clientPath -NodePath $nodePath; continue }
    if ($choice -eq '2') {
      if (Read-RuntimeApiKey -ForcePrompt) { $bridgeReady = Configure-TunnelProfile -State $State -ClientPath $clientPath -NodePath $nodePath }
      continue
    }
    if ($choice -eq '3') { Open-SetupPage $script:ApiKeysUrl | Out-Null; continue }
    if ($choice -eq '4') {
      $powershell = Resolve-WcaToolPath -Name powershell
      & $powershell -NoProfile -ExecutionPolicy Bypass -File $script:DependencyInstaller -ForChatGPT
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
  Write-Host '                  | Stable Bootstrap  |'
  Write-Host '                  +-------------------+'
  Write-Host '                            |'
  Write-Host '                            v'
  Write-Host '                  +-------------------+'
  Write-Host '                  | Active Agent      |'
  Write-Host '                  | Managed Version   |'
  Write-Host '                  +-------------------+'
  Write-Host '                            |'
  Write-Host '                            v'
  Write-Host '                  +-------------------+'
  Write-Host '                  | Authorized Git    |'
  Write-Host '                  | Repositories      |'
  Write-Host '                  +-------------------+'
  Write-Host ''
  Write-Host ('  Stable launcher: {0}' -f (Get-WcaStableLauncherPath))
  Write-Host ''
  if ($ConfigureOnly) {
    Write-Host '  Configuration is saved. Use the stable launcher when you want to start the bridge.'
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

  $managed = Ensure-LocalManagedRuntime -Quiet
  if (-not $managed) {
    Show-Header -RightText 'Self-heal'
    Write-Host '  [X] The managed runtime could not be repaired automatically.' -ForegroundColor Red
    Write-Host '      Run Maintenance -> Repair local runtime.'
    Read-Host '  Press Enter to return to the menu' | Out-Null
    return
  }

  if (-not (Read-RuntimeApiKey)) { return }
  if (-not (Ensure-TunnelProfileCurrent -State $State -ClientPath $clientPath)) {
    Read-Host '  Press Enter to return to the menu' | Out-Null
    return
  }
  if (-not (Invoke-TunnelDoctor -State $State -ClientPath $clientPath)) {
    Read-Host '  Press Enter to return to the menu' | Out-Null
    return
  }

  Show-Header
  Write-Host '  CHATGPT BRIDGE READY TO START'
  Write-Host ''
  Write-Status 'Tunnel' $State.tunnelId
  Write-Status 'Profile' $State.profileName
  Write-Status 'Active agent' ('v' + [string]$managed.version)
  Write-Status 'Stable bootstrap' '[OK]'
  Write-Status 'Repository access' "[OK] $(Get-RepositoryCount) authorized"
  Write-Host ''
  Write-Host '  Keep this window open while ChatGPT uses your local repositories.'
  Write-Host '  Press Ctrl+C to stop the bridge and return to the terminal.'
  Write-Host ''
  $open = Read-Host '  Open ChatGPT before starting? [Y/n]'
  if ([string]::IsNullOrWhiteSpace($open) -or $open -match '^[Yy]') { Open-SetupPage 'https://chatgpt.com/' | Out-Null }
  Write-Host ''
  Write-Host '  Starting Secure MCP Tunnel...' -ForegroundColor Green
  Write-Host ''
  $result = Invoke-TunnelNative -ClientPath $clientPath -Arguments @('run','--profile',$State.profileName)
  Write-Host ''
  if ($result.ok -and $result.exitCode -eq 0) { Write-Host '  [OK] ChatGPT bridge stopped.' }
  elseif (-not $result.blocked) { Write-Host ('  [X] ChatGPT bridge exited with code {0}.' -f $result.exitCode) -ForegroundColor Red }
  Read-Host '  Press Enter to return to the menu' | Out-Null
}
function Invoke-Diagnostics {
  param($State)

  Show-Header -RightText 'Diagnostics'
  $toolchain = Refresh-WcaToolchain -TunnelClientHint ([string]$State.tunnelClientPath)
  $repoCount = Get-RepositoryCount
  $clientPath = Get-ExistingTunnelClientPath -State $State
  $active = Get-WcaActiveInstallation

  Write-Status 'Node.js' $(if ($toolchain.tools.node.status -eq 'ok') { '[OK] ' + [string]$toolchain.tools.node.version } else { '[X]' })
  Write-Status 'npm' $(if ($toolchain.tools.npm.status -eq 'ok') { '[OK] ' + [string]$toolchain.tools.npm.version } else { '[X]' })
  Write-Status 'npx' $(if ($toolchain.tools.npx.status -eq 'ok') { '[OK] ' + [string]$toolchain.tools.npx.version } else { '[X]' })
  Write-Status 'Git' $(if ($toolchain.tools.git.status -eq 'ok') { '[OK] ' + [string]$toolchain.tools.git.version } else { '[X]' })
  Write-Status 'Python 3.11+' $(if ($toolchain.tools.python.status -eq 'ok') { '[OK] ' + [string]$toolchain.tools.python.version + $(if ([string]$toolchain.tools.python.source -eq 'managed') { ' (managed)' } else { ' (system)' }) } else { '[--] optional' })
  Write-Status 'pip' $(if ($toolchain.tools.pip.status -eq 'ok') { '[OK] ' + [string]$toolchain.tools.pip.version } else { '[--] optional' })
  Write-Status 'Repository registry' $(if ($repoCount -gt 0) { "[OK] $repoCount authorized" } else { '[--] none' })
  Write-Status 'Managed agent' $(if ($active -and (Test-WcaManagedRoot ([string]$active.path))) { '[OK] v' + [string]$active.activeVersion } else { '[--] not installed' })
  Write-Status 'Stable bootstrap' $(if (Test-Path -LiteralPath (Get-WcaStableMcpBootstrapPath) -PathType Leaf) { '[OK]' } else { '[X]' })
  Write-Status 'Tunnel client' $(if ($clientPath) { if ($toolchain.tools.tunnelClient.status -eq 'blocked') { '[X] blocked by Windows' } else { '[OK]' } } else { '[--] not found' })
  Write-Status 'Tunnel ID' $(if (Test-TunnelId $State.tunnelId) { '[OK]' } else { '[--] not configured' })
  Write-Status 'ChatGPT app step' $(if ($State.chatgptConfigured) { '[OK]' } else { '[--] not confirmed' })
  Write-Host ''

  if ($toolchain.tools.tunnelClient.status -eq 'blocked') {
    Show-WcaApplicationControlHelp -Path ([string]$toolchain.tools.tunnelClient.path) -Message ([string]$toolchain.tools.tunnelClient.error)
  }

  if ($clientPath -and (Test-TunnelId $State.tunnelId)) {
    Write-Host ''
    Write-Host '     [F] Run full tunnel diagnostic'
    Write-Host '     [R] Repair local runtime / tunnel profile'
    Write-Host '     [O] Open ChatGPT connection settings'
    Write-Host '     [B] Back'
    Write-Host ''
    $choice = Read-Choice '  Select' @('F','R','O','B')
    if ($choice -eq 'F') {
      if (Read-RuntimeApiKey) {
        if (Ensure-TunnelProfileCurrent -State $State -ClientPath $clientPath) { Invoke-TunnelDoctor -State $State -ClientPath $clientPath | Out-Null }
      }
      Read-Host '  Press Enter to continue' | Out-Null
    }
    if ($choice -eq 'R') { Invoke-SelfHeal -State $State }
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

function Invoke-SelfHeal {
  param($State)

  Show-Header -RightText 'Self-heal'
  Write-Host '  Refreshing tool paths and repairing the stable runtime...'
  Write-Host ''
  try {
    Refresh-WcaProcessPath
    $managed = Install-WcaManagedVersion -SourceRoot $script:RepoRoot
    $toolchain = Refresh-WcaToolchain -TunnelClientHint ([string]$State.tunnelClientPath)
    $script:BootstrapPath = Get-WcaStableMcpBootstrapPath
    Write-Status 'Managed agent' ('[OK] v' + [string]$managed.version)
    Write-Status 'Stable MCP bootstrap' $(if (Test-Path -LiteralPath $script:BootstrapPath -PathType Leaf) { '[OK]' } else { '[X]' })
    Write-Status 'Node.js' $(if ($toolchain.tools.node.status -eq 'ok') { '[OK]' } else { '[X]' })
    Write-Status 'npm' $(if ($toolchain.tools.npm.status -eq 'ok') { '[OK]' } else { '[X]' })
    Write-Status 'Git' $(if ($toolchain.tools.git.status -eq 'ok') { '[OK]' } else { '[X]' })
    Write-Status 'Python 3.11+' $(if ($toolchain.tools.python.status -eq 'ok') { '[OK] ' + [string]$toolchain.tools.python.version } else { '[--] optional' })

    $clientPath = Get-ExistingTunnelClientPath -State $State
    if ($clientPath -and (Test-TunnelId $State.tunnelId) -and (Test-SavedRuntimeCredential)) {
      if (Read-RuntimeApiKey) { Ensure-TunnelProfileCurrent -State $State -ClientPath $clientPath | Out-Null }
    }
    Write-Host ''
    Write-Host '  [OK] Local self-heal pass completed.' -ForegroundColor Green
  } catch {
    Write-Host ('  [X] Self-heal failed: {0}' -f $_.Exception.Message) -ForegroundColor Red
  }
  Read-Host '  Press Enter to continue' | Out-Null
}

function Invoke-MaintenanceMenu {
  param($State)

  while ($true) {
    Show-Header -RightText 'Maintenance'
    $active = Get-WcaActiveInstallation
    Write-Status 'Active agent' $(if ($active) { '[OK] v' + [string]$active.activeVersion } else { '[--] not managed' })
    Write-Status 'Toolchain registry' $(if (Test-Path -LiteralPath (Get-WcaToolchainPath) -PathType Leaf) { '[OK]' } else { '[--] not scanned' })
    Write-Host ''
    Write-Host '     [1] Scan / install dependencies'
    Write-Host '     [2] Self-heal paths, bootstrap, and tunnel profile'
    Write-Host '     [3] Check for / install Windows Coding Agent update'
    Write-Host '     [4] Roll back to last-known-good agent version'
    Write-Host '     [5] Show stable launcher directory'
    Write-Host '     [B] Back'
    Write-Host ''
    $choice = Read-Choice '  Select' @('1','2','3','4','5','B')
    if ($choice -eq 'B') { return }

    $powershell = Resolve-WcaToolPath -Name powershell
    if ($choice -eq '1') {
      & $powershell -NoProfile -ExecutionPolicy Bypass -File $script:DependencyInstaller -ForChatGPT
      Refresh-WcaToolchain -TunnelClientHint ([string]$State.tunnelClientPath) | Out-Null
      continue
    }
    if ($choice -eq '2') { Invoke-SelfHeal -State $State; continue }
    if ($choice -eq '3') {
      & $powershell -NoProfile -ExecutionPolicy Bypass -File $script:Updater
      Read-Host '  Press Enter to continue' | Out-Null
      continue
    }
    if ($choice -eq '4') {
      try {
        $rolled = Invoke-WcaRollback
        Write-Host ''
        Write-Host ('  [OK] Active version is now v{0}' -f $rolled.activeVersion) -ForegroundColor Green
      } catch {
        Write-Host ''
        Write-Host ('  [X] Rollback unavailable: {0}' -f $_.Exception.Message) -ForegroundColor Red
      }
      Read-Host '  Press Enter to continue' | Out-Null
      continue
    }
    if ($choice -eq '5') {
      Write-Host ''
      Write-Host ('  Stable launchers: {0}' -f (Split-Path -Parent (Get-WcaStableLauncherPath)))
      Read-Host '  Press Enter to continue' | Out-Null
    }
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
      Invoke-RepositoryManager
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
    $active = Get-WcaActiveInstallation

    Show-Header
    Write-Host '  Connection status'
    Write-Host ''
    Write-Status 'Local repositories' $(if ($repoCount -gt 0) { "[OK] $repoCount authorized" } else { '[--] not configured' })
    Write-Status 'Active agent' $(if ($active -and (Test-WcaManagedRoot ([string]$active.path))) { '[OK] v' + [string]$active.activeVersion } else { '[--] not managed' })
    Write-Status 'Stable MCP bootstrap' $(if (Test-Path -LiteralPath (Get-WcaStableMcpBootstrapPath) -PathType Leaf) { '[OK]' } else { '[--] not prepared' })
    Write-Status 'Tunnel client' $(if ($clientPath) { '[OK] found' } else { '[--] not configured' })
    Write-Status 'OpenAI tunnel' $(if (Test-TunnelId $state.tunnelId) { '[OK] configured' } else { '[--] not configured' })
    Write-Status 'Runtime credential' $(if (Test-SavedRuntimeCredential) { '[OK] securely saved' } elseif (-not [string]::IsNullOrWhiteSpace($env:CONTROL_PLANE_API_KEY)) { '[OK] session only' } else { '[--] prompt on start' })
    Write-Status 'ChatGPT app' $(if ($state.chatgptConfigured) { '[OK] confirmed' } else { '[--] not confirmed' })
    Write-Host ''
    Write-Rule
    Write-Host ''
    if ($state.profileConfigured -and (Test-TunnelId $state.tunnelId) -and $clientPath) { Write-Host '     [1] Start ChatGPT bridge' } else { Write-Host '     [1] Start guided setup' }
    Write-Host '     [2] Setup / resume / reconfigure'
    Write-Host '     [3] Diagnostics'
    Write-Host '     [4] Manage repositories'
    Write-Host '     [5] Start fresh setup'
    Write-Host '     [6] Maintenance / dependencies / updates'
    Write-Host '     [Q] Quit'
    Write-Host ''
    $choice = Read-Choice '  Select' @('1','2','3','4','5','6','Q')
    if ($choice -eq 'Q') { return }
    if ($choice -eq '1') {
      if ($state.profileConfigured -and (Test-TunnelId $state.tunnelId) -and $clientPath) { Start-ChatGPTBridge -State $state } else { Invoke-GuidedSetup -State $state }
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
      } else { Invoke-GuidedSetup -State $state }
      continue
    }
    if ($choice -eq '3') { Invoke-Diagnostics -State $state; continue }
    if ($choice -eq '4') {
      Invoke-RepositoryManager
      continue
    }
    if ($choice -eq '5') { Invoke-FreshSetupMenu; continue }
    if ($choice -eq '6') { Invoke-MaintenanceMenu -State $state; continue }
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
  if (-not (Test-WcaApplicationControlMessage 'An Application Control policy has blocked this file')) { throw 'Application Control classifier failed.' }
  Write-Host 'SELFTEST OK - wizard state is secret-free; validators, stable-bootstrap command, Application Control handling, and DPAPI credential round-trip passed.'
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

if ($RepairOnly) {
  $state = Load-ConnectionState
  $managed = Ensure-LocalManagedRuntime
  if (-not $managed) { exit 1 }
  Refresh-WcaToolchain -TunnelClientHint ([string]$state.tunnelClientPath) | Out-Null
  Write-Host 'Local runtime and toolchain repair completed.'
  exit 0
}

if ($Open -eq 'Repositories') {
  Invoke-RepositoryManager
  exit 0
}

Show-MainMenu
