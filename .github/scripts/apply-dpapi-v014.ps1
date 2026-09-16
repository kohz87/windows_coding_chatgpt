$ErrorActionPreference = 'Stop'

function Replace-Once {
  param([string]$Text, [string]$Old, [string]$New, [string]$Label)
  $count = ([regex]::Matches($Text, [regex]::Escape($Old))).Count
  if ($count -ne 1) { throw "$Label expected exactly one match, found $count" }
  return $Text.Replace($Old, $New)
}

$path = 'Connect-ChatGPT.ps1'
$text = Get-Content -LiteralPath $path -Raw

$old = @'
$script:StatePath = Join-Path $script:AgentHome 'chatgpt-connection.json'
$script:ConfigPath = Join-Path $script:AgentHome 'config.json'
'@
$new = @'
$script:StatePath = Join-Path $script:AgentHome 'chatgpt-connection.json'
$script:ConfigPath = Join-Path $script:AgentHome 'config.json'
$script:SecretsPath = Join-Path $script:AgentHome 'secrets'
$script:CredentialPath = Join-Path $script:SecretsPath 'tunnel-runtime-key.dpapi'
$script:CredentialEntropy = [Text.Encoding]::UTF8.GetBytes('windows-coding-agent:tunnel-runtime-key:v1')
'@
$text = Replace-Once $text $old $new 'credential paths'

$marker = 'function Get-RepositoryCount {'
$functions = @'
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
    $protectedBytes = [Security.Cryptography.ProtectedData]::Protect(
      $plainBytes,
      $script:CredentialEntropy,
      [Security.Cryptography.DataProtectionScope]::CurrentUser
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
    $plainBytes = [Security.Cryptography.ProtectedData]::Unprotect(
      $protectedBytes,
      $script:CredentialEntropy,
      [Security.Cryptography.DataProtectionScope]::CurrentUser
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

'@
$text = Replace-Once $text $marker ($functions + $marker) 'credential helper insertion'

$pattern = '(?s)function Read-RuntimeApiKey \{.*?\r?\n\}\r?\n\r?\nfunction Invoke-TunnelDoctor \{'
$matches = [regex]::Matches($text, $pattern)
if ($matches.Count -ne 1) { throw "Read-RuntimeApiKey block expected one match, found $($matches.Count)" }
$replacement = @'
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
'@
$text = [regex]::Replace($text, $pattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $replacement }, 1)

$insertMarker = 'function Invoke-ReconfigureMenu {'
$credentialMenu = @'
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

'@
$text = Replace-Once $text $insertMarker ($credentialMenu + $insertMarker) 'credential menu insertion'
$text = Replace-Once $text "    Write-Host '     [3] Re-enter / validate runtime API key'" "    Write-Host '     [3] Manage runtime credential'" 'reconfigure menu label'

$old = @'
    if ($choice -eq '3') {
      $env:CONTROL_PLANE_API_KEY = $null
      if (Read-RuntimeApiKey -ForcePrompt) {
        $clientPath = Get-ExistingTunnelClientPath -State $State
        if ($clientPath -and (Test-TunnelId $State.tunnelId)) {
          Invoke-TunnelDoctor -State $State -ClientPath $clientPath | Out-Null
        }
      }
      Read-Host '  Press Enter to continue' | Out-Null
      continue
    }
'@
$new = @'
    if ($choice -eq '3') {
      Invoke-CredentialMenu -State $State
      continue
    }
'@
$text = Replace-Once $text $old $new 'reconfigure credential action'

$old = @'
function Reset-ChatGPTConnection {
  if (Test-Path -LiteralPath $script:StatePath -PathType Leaf) {
    Remove-Item -LiteralPath $script:StatePath -Force
  }
  $env:CONTROL_PLANE_API_KEY = $null
  $env:CONTROL_PLANE_TUNNEL_ID = $null
}
'@
$new = @'
function Reset-ChatGPTConnection {
  if (Test-Path -LiteralPath $script:StatePath -PathType Leaf) {
    Remove-Item -LiteralPath $script:StatePath -Force
  }
  Remove-SavedRuntimeCredential
  $env:CONTROL_PLANE_API_KEY = $null
  $env:CONTROL_PLANE_TUNNEL_ID = $null
}
'@
$text = Replace-Once $text $old $new 'reset saved credential'

$mainStatusOld = "    Write-Status 'OpenAI tunnel' `$(if (Test-TunnelId `$state.tunnelId) { '[OK] configured' } else { '[--] not configured' })`n    Write-Status 'ChatGPT app'"
$text = $text -replace "`r`n", "`n"
$mainStatusNew = "    Write-Status 'OpenAI tunnel' `$(if (Test-TunnelId `$state.tunnelId) { '[OK] configured' } else { '[--] not configured' })`n    Write-Status 'Runtime credential' `$(if (Test-SavedRuntimeCredential) { '[OK] securely saved' } elseif (-not [string]::IsNullOrWhiteSpace(`$env:CONTROL_PLANE_API_KEY)) { '[OK] session only' } else { '[--] prompt on start' })`n    Write-Status 'ChatGPT app'"
$text = Replace-Once $text $mainStatusOld $mainStatusNew 'main credential status'

$selfMarker = "  Write-Host 'SELFTEST OK - wizard state is secret-free; validators and quote-safe MCP command passed.'"
$selfNew = @'
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
'@
$text = Replace-Once $text $selfMarker $selfNew 'DPAPI self-test'
Set-Content -LiteralPath $path -Value $text -Encoding UTF8

$readmePath = 'README.md'
$readme = Get-Content -LiteralPath $readmePath -Raw
$readme = Replace-Once $readme '- Resume/reconfigure/fresh-setup flows without storing the runtime API key' '- Resume/reconfigure/fresh-setup flows with optional Windows DPAPI-secured runtime credential storage' 'README feature'
$readme = Replace-Once $readme 'Windows Coding Agent does **not** store GitHub tokens or OpenAI runtime API keys in its repository registry or ChatGPT wizard state.' 'Windows Coding Agent does **not** store GitHub tokens or literal OpenAI runtime API keys in its repository registry or ChatGPT wizard state. When you choose secure persistence, the tunnel runtime key is stored only as Windows DPAPI-encrypted ciphertext bound to the current Windows user.' 'README credential boundary'
$readme = Replace-Once $readme 'The wizard asks for the runtime key again unless `CONTROL_PLANE_API_KEY` already exists, verifies the tunnel, optionally opens ChatGPT, and starts the foreground Secure MCP Tunnel.' 'If you chose secure persistence, the wizard loads the DPAPI-protected runtime credential automatically. Otherwise it asks again unless `CONTROL_PLANE_API_KEY` already exists. It then verifies the tunnel, optionally opens ChatGPT, and starts the foreground Secure MCP Tunnel.' 'README startup'
$readme = Replace-Once $readme 'The runtime API key is never written there.' 'The runtime API key is never written there. If secure persistence is enabled, encrypted ciphertext is stored separately at `%USERPROFILE%\.windows-coding-agent\secrets\tunnel-runtime-key.dpapi` (or under `WINDOWS_CODING_AGENT_HOME`).' 'README state section'
$readme = Replace-Once $readme '- validate a new runtime key' '- manage, test, replace, or forget the securely saved runtime credential' 'README reconfigure list'
Set-Content -LiteralPath $readmePath -Value $readme -Encoding UTF8

$chatPath = 'docs/CHATGPT.md'
$chat = Get-Content -LiteralPath $chatPath -Raw
$chat = $chat -replace "`r`n", "`n"
$chat = Replace-Once $chat 'The key is entered with a hidden prompt. Windows Coding Agent places it only in the current process environment as `CONTROL_PLANE_API_KEY`.' 'The key is entered with a hidden prompt. You can either save it securely for the current Windows user or keep it session-only. Secure persistence uses Windows DPAPI and stores only encrypted ciphertext; session-only mode places it only in the current process environment as `CONTROL_PLANE_API_KEY`.' 'CHATGPT key handling'
$chat = Replace-Once $chat 'The literal key is **never saved** in `chatgpt-connection.json`, `config.json`, or the Windows Coding Agent source tree.' 'The literal key is **never saved** in `chatgpt-connection.json`, `config.json`, the tunnel profile, or the Windows Coding Agent source tree. DPAPI ciphertext is stored separately at `%USERPROFILE%\.windows-coding-agent\secrets\tunnel-runtime-key.dpapi` when secure persistence is selected.' 'CHATGPT key storage'
$chat = Replace-Once $chat "The runtime API key is intentionally absent.`n`nThis lets the wizard resume without turning the setup file into a credential vault." "The runtime API key is intentionally absent. When secure persistence is enabled, the encrypted DPAPI blob lives under `secrets\tunnel-runtime-key.dpapi` instead. It can be decrypted only in the Windows user context that created it (subject to normal local-machine/user security boundaries).`n`nThis lets the wizard resume without turning the setup file into a plaintext credential vault." 'CHATGPT remembered state'
$chat = Replace-Once $chat 'The launcher asks for the runtime key again unless `CONTROL_PLANE_API_KEY` is already present, reruns the tunnel diagnostic, optionally opens ChatGPT, then starts:' 'The launcher first uses `CONTROL_PLANE_API_KEY` when already present, otherwise loads the DPAPI-protected saved credential when available, and only prompts when neither exists. It reruns the tunnel diagnostic, optionally opens ChatGPT, then starts:' 'CHATGPT daily startup'
$chat = Replace-Once $chat '- runtime API key validation' '- runtime credential management (replace, test, forget, or switch back to session-only)' 'CHATGPT reconfigure'
$chat = Replace-Once $chat "- saved tunnel-client path`n- wizard progress" "- saved tunnel-client path`n- securely saved DPAPI runtime credential, if one exists`n- wizard progress" 'CHATGPT reset list'
Set-Content -LiteralPath $chatPath -Value $chat -Encoding UTF8

$securityPath = 'docs/SECURITY.md'
$security = Get-Content -LiteralPath $securityPath -Raw
$security = Replace-Once $security 'The tunnel runtime uses a restricted `CONTROL_PLANE_API_KEY` with Tunnels Read + Use. `Connect-ChatGPT.cmd` prompts for that key without echo and places it in the current process environment. The Windows Coding Agent repository registry does not persist it.' 'The tunnel runtime uses a restricted `CONTROL_PLANE_API_KEY` with Tunnels Read + Use. `Connect-ChatGPT.cmd` prompts for that key without echo. The user can keep it session-only or persist it as Windows DPAPI-encrypted ciphertext bound to the current Windows user. The repository registry and wizard-state JSON never contain the literal key.' 'SECURITY tunnel credential'
$security = Replace-Once $security 'The wizard state must not contain API keys, bearer tokens, GitHub credentials, or other secrets. CI includes a self-test that rejects secret-like state fields.' 'The wizard state must not contain API keys, bearer tokens, GitHub credentials, or other secrets. CI includes a self-test that rejects secret-like state fields and performs a DPAPI encrypt/decrypt round-trip using a temporary test credential.' 'SECURITY CI'
$security = Replace-Once $security 'Resetting only the ChatGPT connection removes this wizard state but leaves the repository registry and worktrees intact.' 'Resetting only the ChatGPT connection removes this wizard state and the DPAPI-protected tunnel credential, but leaves the repository registry and worktrees intact.' 'SECURITY reset'
$security = Replace-Once $security 'The repository registry stores repository paths, GitHub slugs, branches, permissions, and allowed script names. It does not store GitHub tokens or OpenAI Secure MCP Tunnel runtime API keys.' 'The repository registry stores repository paths, GitHub slugs, branches, permissions, and allowed script names. It does not store GitHub tokens or OpenAI Secure MCP Tunnel runtime API keys. Optional tunnel credential persistence uses a separate DPAPI ciphertext file under the user-scoped Windows Coding Agent data directory.' 'SECURITY credentials'
$security += @'

### DPAPI credential storage

When the user chooses **Save securely for this Windows user**, the launcher encrypts the restricted tunnel runtime key with Windows Data Protection API (DPAPI), `CurrentUser` scope, plus application-specific entropy. The encrypted blob is written to:

```text
%USERPROFILE%\.windows-coding-agent\secrets\tunnel-runtime-key.dpapi
```

or the equivalent path beneath `WINDOWS_CODING_AGENT_HOME`.

DPAPI protects the credential at rest against simple file disclosure, but it is not a boundary against malware, an administrator, or another process already able to operate as the same Windows user. The launcher decrypts the key only when needed, exports it to `CONTROL_PLANE_API_KEY` for the current process tree, and never writes the plaintext value to JSON configuration or tunnel profiles.
'@
Set-Content -LiteralPath $securityPath -Value $security -Encoding UTF8

$installPath = 'docs/INSTALLATION.md'
$install = Get-Content -LiteralPath $installPath -Raw
$install = Replace-Once $install 'The runtime API key is kept only in process memory and is never persisted by Windows Coding Agent.' 'After entering the runtime API key, choose either **Save securely for this Windows user** (DPAPI-encrypted, recommended for convenience) or **Use only for this session**. The literal key is never written to JSON configuration or the package directory.' 'INSTALLATION credential'
Set-Content -LiteralPath $installPath -Value $install -Encoding UTF8

npm version 0.1.4 --no-git-tag-version
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
