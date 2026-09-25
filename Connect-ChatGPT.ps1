param(
  [switch]$SelfTest,
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$RemainingArgs
)

$ErrorActionPreference = 'Stop'
$target = Join-Path $PSScriptRoot 'Windows-Coding-Agent.ps1'
if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
  throw 'Windows-Coding-Agent.ps1 is missing. The managed staging compatibility repair did not complete.'
}
if ($SelfTest) {
  & $target -SelfTest
} else {
  & $target @RemainingArgs
}
exit $(if ($?) { 0 } else { 1 })
