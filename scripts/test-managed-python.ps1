$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $repoRoot 'Toolchain.ps1')

$oldHome = $env:WINDOWS_CODING_AGENT_HOME
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('wca-managed-python-test-' + [Guid]::NewGuid().ToString('N'))

try {
  $env:WINDOWS_CODING_AGENT_HOME = $temporary
  $python = Install-WcaManagedPython
  if (-not (Test-Path -LiteralPath $python -PathType Leaf)) { throw 'Managed Python executable was not created.' }
  if (-not (Test-WcaManagedPythonPath $python)) { throw 'Managed Python escaped the controller tool directory.' }

  $version = (& $python --version 2>&1 | Out-String).Trim()
  if (-not (Test-WcaPythonSupported $version)) { throw "Managed Python version is unsupported: $version" }

  & $python -I -m pip --version
  if ($LASTEXITCODE -ne 0) { throw 'Managed Python pip probe failed.' }

  $venv = Join-Path $temporary 'venv-probe'
  & $python -I -m venv $venv
  if ($LASTEXITCODE -ne 0) { throw 'Managed Python venv creation failed.' }
  $venvPython = Join-Path $venv 'Scripts\python.exe'
  if (-not (Test-Path -LiteralPath $venvPython -PathType Leaf)) { throw 'Managed Python venv did not contain Scripts\python.exe.' }

  Write-Host ('MANAGED PYTHON TEST OK - {0}' -f $version)
} finally {
  if ($null -eq $oldHome) {
    Remove-Item Env:WINDOWS_CODING_AGENT_HOME -ErrorAction SilentlyContinue
  } else {
    $env:WINDOWS_CODING_AGENT_HOME = $oldHome
  }
  Remove-Item -LiteralPath $temporary -Recurse -Force -ErrorAction SilentlyContinue
}
