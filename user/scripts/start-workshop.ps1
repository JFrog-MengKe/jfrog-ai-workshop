$ErrorActionPreference = 'Stop'
& powershell.exe -NoProfile -File (Join-Path $PSScriptRoot 'bootstrap-node.ps1')
if ($LASTEXITCODE -ne 0) {exit $LASTEXITCODE}
$TaskBase = if ($env:WORKSHOP_HOME) {$env:WORKSHOP_HOME} else {Join-Path $env:USERPROFILE '.jfrog-workshop'}
$env:PATH = (Join-Path $TaskBase 'bin') + ';' + $env:PATH
& node.exe (Join-Path $PSScriptRoot 'workshop-server.cjs')
exit $LASTEXITCODE
