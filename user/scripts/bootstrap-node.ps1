param([switch]$ForceInstall)
$ErrorActionPreference = 'Stop'
$TaskRoot = Split-Path $PSScriptRoot -Parent
$TaskBase = if ($env:WORKSHOP_HOME) { $env:WORKSHOP_HOME } else { Join-Path $env:USERPROFILE '.jfrog-workshop' }
$TaskBin = Join-Path $TaskBase 'bin'
$env:PATH = $TaskBin + ';' + $env:PATH
if (!$ForceInstall -and (Get-Command node.exe -ErrorAction SilentlyContinue)) {
    & node.exe -e 'process.exit(+process.versions.node.split(".")[0]>=18?0:1)'
    if ($LASTEXITCODE -eq 0) { Write-Host 'Node runtime available'; exit 0 }
}
$TaskArch = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
$TaskArch = switch ($TaskArch) { 'ARM64' {'arm64'} 'AMD64' {'x64'} default {throw 'Unsupported Windows CPU'} }
$TaskZip = Join-Path $TaskRoot "tools/win32-$TaskArch/node.zip"
New-Item -ItemType Directory -Force (Split-Path $TaskZip -Parent) | Out-Null
$TaskVersion = '24.22.0'
$TaskSourceFile = "node-v$TaskVersion-win-$TaskArch.zip"
$TaskSourceBase = "https://nodejs.org/download/release/v$TaskVersion"
if (Test-Path $TaskZip) {
    Write-Host "LOCAL tools/win32-$TaskArch/node.zip"
    $TaskExpected = $null
    if (Test-Path "$TaskZip.sha256") {
        $TaskExpected = (Get-Content "$TaskZip.sha256" -Raw).Trim()
    } else {
        $TaskManifest = Join-Path $TaskRoot 'tools/checksums.json'
        if (Test-Path $TaskManifest) {
            $TaskChecksums = Get-Content $TaskManifest -Raw | ConvertFrom-Json
            $TaskProperty = $TaskChecksums.files.PSObject.Properties["win32-$TaskArch/node.zip"]
            if ($TaskProperty) {$TaskExpected = $TaskProperty.Value}
        }
        if (!$TaskExpected) {
            $TaskExpected = (Get-FileHash -Algorithm SHA256 $TaskZip).Hash.ToLower()
            Write-Host 'LOCAL HASH recorded for manually supplied Node archive'
        }
    }
} else {
    Write-Host "DOWNLOAD Node $TaskVersion -> tools/win32-$TaskArch/node.zip"
    $TaskChecksums = (Invoke-WebRequest -UseBasicParsing -Uri "$TaskSourceBase/SHASUMS256.txt").Content
    if ($TaskChecksums -is [byte[]]) {$TaskChecksums = [Text.Encoding]::UTF8.GetString($TaskChecksums)}
    $TaskLine = ($TaskChecksums -split "`n" | Where-Object { $_.Trim().EndsWith(" $TaskSourceFile") })
    if (!$TaskLine) {throw 'Official Node SHA256 was not found'}
    $TaskExpected = ($TaskLine.Trim() -split '\s+')[0]
    try {
        Invoke-WebRequest -UseBasicParsing -Uri "$TaskSourceBase/$TaskSourceFile" -OutFile "$TaskZip.partial"
        if ((Get-FileHash -Algorithm SHA256 "$TaskZip.partial").Hash.ToLower() -ne $TaskExpected) {throw 'Downloaded Node SHA256 mismatch'}
        Move-Item -LiteralPath "$TaskZip.partial" -Destination $TaskZip
        Write-Host 'CACHED Node archive (official SHA256 verified)'
    } finally {if (Test-Path "$TaskZip.partial") {Remove-Item -LiteralPath "$TaskZip.partial"}}
}
if ((Get-FileHash -Algorithm SHA256 $TaskZip).Hash.ToLower() -ne $TaskExpected.ToLower()) {throw 'Local Node SHA256 mismatch; replace the damaged archive before retrying'}
[IO.File]::WriteAllText("$TaskZip.sha256", $TaskExpected.ToLower() + "`n")
New-Item -ItemType Directory -Force $TaskBin | Out-Null
$TaskDest = Join-Path $TaskBase ('node-' + [guid]::NewGuid().ToString('N'))
Expand-Archive -LiteralPath $TaskZip -DestinationPath $TaskDest
$TaskNode = @(Get-ChildItem -Path $TaskDest -Filter node.exe -Recurse)[0].Directory.FullName
& (Join-Path $TaskNode 'node.exe') -e 'process.exit(+process.versions.node.split(".")[0]>=18?0:1)'
if ($LASTEXITCODE -ne 0) {throw 'Offline Node binary incompatible'}
# A small node.exe beside launch shims allows all tools to use the same user bin.
$TaskCurrent = Join-Path $TaskBin 'node.exe'
$TaskKeepNode = $false
if (Test-Path $TaskCurrent) {
    & $TaskCurrent -e 'process.exit(+process.versions.node.split(".")[0]>=18?0:1)'
    $TaskKeepNode = $LASTEXITCODE -eq 0
}
if (!$TaskKeepNode) {Copy-Item (Join-Path $TaskNode 'node.exe') $TaskCurrent -Force}
foreach ($TaskName in @('npm','npx')) {
    $TaskCli = Join-Path $TaskNode "node_modules/npm/bin/$TaskName-cli.js"
    $TaskWrapper = "@echo off`r`n`"$TaskNode\node.exe`" `"$TaskCli`" %*`r`n"
    [IO.File]::WriteAllText((Join-Path $TaskBin "$TaskName.cmd"), $TaskWrapper)
}
& (Join-Path $TaskBin 'node.exe') --version
& (Join-Path $TaskBin 'npx.cmd') --version
if ($LASTEXITCODE -ne 0) {throw 'Offline npx verification failed'}

& node.exe (Join-Path $PSScriptRoot 'package-cache.cjs') node
if ($LASTEXITCODE -ne 0) {throw 'Node cache registration failed'}
