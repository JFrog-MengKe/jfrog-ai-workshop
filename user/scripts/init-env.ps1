param([switch]$Check)
$ErrorActionPreference = 'Stop'
& powershell.exe -NoProfile -File (Join-Path $PSScriptRoot 'bootstrap-node.ps1')
if ($LASTEXITCODE -ne 0) {exit $LASTEXITCODE}
$TaskBase = if ($env:WORKSHOP_HOME) {$env:WORKSHOP_HOME} else {Join-Path $env:USERPROFILE '.jfrog-workshop'}
$env:PATH = (Join-Path $TaskBase 'bin') + ';' + $env:PATH
if ($Check) { & node.exe (Join-Path $PSScriptRoot 'environment.cjs') --check } else { & node.exe (Join-Path $PSScriptRoot 'environment.cjs') }
exit $LASTEXITCODE
