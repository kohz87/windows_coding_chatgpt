param(
  [Parameter(Mandatory = $true)][string]$ZipPath,
  [switch]$LegacyV019
)

$ErrorActionPreference = 'Stop'
$zip = (Resolve-Path -LiteralPath $ZipPath).Path
$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ('wca-release-verify-' + [Guid]::NewGuid().ToString('N'))

function Invoke-Checked {
  param([string]$Label, [scriptblock]$Action)
  & $Action
  if ($LASTEXITCODE -ne 0) { throw "$Label failed with exit code $LASTEXITCODE." }
}

try {
  New-Item -ItemType Directory -Force -Path $temporaryRoot | Out-Null
  $extract = Join-Path $temporaryRoot 'extract'
  Expand-Archive -LiteralPath $zip -DestinationPath $extract -Force
  $bundle = Get-ChildItem -LiteralPath $extract -Directory | Select-Object -First 1
  if (-not $bundle) { throw 'Release ZIP did not contain a bundle directory.' }

  $required = @(
    'Setup.cmd','Windows-Coding-Agent.cmd','Windows-Coding-Agent.ps1','Toolchain.ps1',
    'Install-Dependencies.cmd','Install-Dependencies.ps1','Update.cmd','Update.ps1',
    'package.json','package-lock.json','README.md','LICENSE','VERSION.txt',
    'src','docs','test','bootstrap','scripts'
  )
  foreach ($item in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $bundle.FullName $item))) {
      throw "Release package is missing $item."
    }
  }

  Invoke-Checked 'Toolchain self-test' {
    powershell -NoProfile -ExecutionPolicy Bypass -Command ". '$(Join-Path $bundle.FullName 'Toolchain.ps1')'; Invoke-WcaToolchainSelfTest"
  }
  Invoke-Checked 'Updater self-test' {
    powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $bundle.FullName 'Update.ps1') -SelfTest
  }
  Invoke-Checked 'Control-panel self-test' {
    powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $bundle.FullName 'Windows-Coding-Agent.ps1') -SelfTest
  }

  if ($LegacyV019) {
    $legacyStage = Join-Path $temporaryRoot 'legacy-v0.1.9-stage'
    New-Item -ItemType Directory -Force -Path $legacyStage | Out-Null
    $legacyItems = @(
      'src','docs','test','bootstrap','scripts',
      'Setup.cmd','Start-Agent.cmd','Connect-ChatGPT.cmd','Connect-ChatGPT.ps1',
      'Doctor.cmd','Update.cmd','Update.ps1','Install-Dependencies.cmd','Install-Dependencies.ps1',
      'Toolchain.ps1','config.example.json','package.json','package-lock.json','README.md','LICENSE','AGENTS.md'
    )
    foreach ($item in $legacyItems) {
      $source = Join-Path $bundle.FullName $item
      if (Test-Path -LiteralPath $source) {
        Copy-Item -LiteralPath $source -Destination (Join-Path $legacyStage $item) -Recurse -Force
      }
    }

    Push-Location $legacyStage
    try {
      Invoke-Checked 'v0.1.9-style npm ci' { npm ci --ignore-scripts }
      Invoke-Checked 'v0.1.9-style npm test' { npm test }
      Invoke-Checked 'v0.1.9-style source validation' { npm run validate }

      foreach ($canonical in @('Windows-Coding-Agent.cmd','Windows-Coding-Agent.ps1')) {
        if (-not (Test-Path -LiteralPath (Join-Path $legacyStage $canonical) -PathType Leaf)) {
          throw "Legacy staging repair did not materialize $canonical."
        }
      }
      $compat = Join-Path $legacyStage 'Connect-ChatGPT.ps1'
      if (-not (Test-Path -LiteralPath $compat -PathType Leaf)) {
        throw 'v0.1.9 compatibility shim Connect-ChatGPT.ps1 is missing.'
      }
      Invoke-Checked 'v0.1.9 Connect-ChatGPT self-test' {
        powershell -NoProfile -ExecutionPolicy Bypass -File $compat -SelfTest
      }
    } finally {
      Pop-Location
    }
  }

  Write-Host 'RELEASE PACKAGE VERIFY OK'
} finally {
  Remove-Item -LiteralPath $temporaryRoot -Recurse -Force -ErrorAction SilentlyContinue
}
