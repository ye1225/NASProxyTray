#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root       = Split-Path -Parent $MyInvocation.MyCommand.Path
$scriptPath = Join-Path $root 'ProxyTray.ps1'
$iconPath   = Join-Path $root 'app.ico'
$exePath    = Join-Path $root 'NASProxyTray.exe'

if (-not (Test-Path $scriptPath)) { throw "Cannot find ProxyTray.ps1" }
if (-not (Test-Path $iconPath))   { throw "Cannot find app.ico" }

Write-Host '[1/3] Reading icon ...' -ForegroundColor Cyan
$b64 = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($iconPath))

Write-Host '[2/3] Injecting ...' -ForegroundColor Cyan
$lines = [System.IO.File]::ReadAllLines($scriptPath)
$found = $false
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i].TrimStart().StartsWith('$IconBase64')) {
        $lines[$i] = '$IconBase64 = ' + [char]39 + $b64 + [char]39
        $found = $true
        break
    }
}
if (-not $found) { throw "IconBase64 line not found in ProxyTray.ps1" }
$newText = [string]::Join("`r`n", $lines)
[System.IO.File]::WriteAllText($scriptPath, $newText, (New-Object System.Text.UTF8Encoding $true))

Write-Host '[3/3] Packaging ...' -ForegroundColor Cyan
if (-not (Get-Module -ListAvailable ps2exe)) {
    Install-Module ps2exe -Scope CurrentUser -Force
}
Invoke-ps2exe -InputFile $scriptPath -OutputFile $exePath -noConsole `
    -title 'NASProxyTray' -description 'NAS Proxy Tray' -product 'NASProxyTray' `
    -version '1.0.0.0' -iconFile $iconPath

Write-Host ''
Write-Host "Build OK: $exePath" -ForegroundColor Green