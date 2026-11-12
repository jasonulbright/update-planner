# Runs on the lab workstation in the interactive session (scheduled task). Loads the UI
# Automation helpers, runs the steps file and writes the finished flag. The flag holds
# "finished" or "failed: <reason>", so Invoke-GuideCapture.ps1 can stop before it replaces an image.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'The dot-sourced steps file reads $appDir and $Capture.')]
param([string]$GuideRoot)
$ErrorActionPreference = 'Stop'
$OutDir = Join-Path $GuideRoot 'ui\out'; New-Item -ItemType Directory $OutDir -Force | Out-Null
$appDir = $GuideRoot
. (Join-Path $GuideRoot 'ui\guilib.ps1')
# Settings that the caller passes in (site code, SMS Provider, wave collections).
$Capture = Get-Content -LiteralPath (Join-Path $GuideRoot 'ui\capture.json') -Raw | ConvertFrom-Json
$state = 'finished'
try { . (Join-Path $GuideRoot 'ui\steps.ps1') }
catch {
    Log ('ERROR: ' + $_.Exception.Message + ' @ ' + $_.ScriptStackTrace)
    $state = 'failed: ' + $_.Exception.Message
}
finally { $state | Set-Content (Join-Path $OutDir 'finished.flag') }
