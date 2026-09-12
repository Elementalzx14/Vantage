# Convenience wrapper for this PC; the cloud build uses its own pinned SDK.
$taskRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$taskRoot = Split-Path $taskRoot -Parent
$sdk = Join-Path $taskRoot 'work/flutter/bin/flutter.bat'
if (-not (Test-Path -LiteralPath $sdk)) {
  throw 'Project-local Flutter SDK not found. Install Flutter 3.38.5 and use flutter directly.'
}
$env:PUB_CACHE = Join-Path $taskRoot 'work/pub-cache'
$env:FLUTTER_SUPPRESS_ANALYTICS = 'true'
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
  & $sdk @args
  $flutterExitCode = $LASTEXITCODE
} finally {
  Pop-Location
}
exit $flutterExitCode
