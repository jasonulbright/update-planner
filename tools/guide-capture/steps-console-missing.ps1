# Capture steps without the Configuration Manager console: one image of the start message.
# Test copy only: make the module path lookup return nothing, as on a computer without the console.
$f = Join-Path $appDir 'Lib\SuiteCommon\SuiteCommon.psm1'
$t = Get-Content -LiteralPath $f -Raw
$t = $t -replace '(?s)(function Resolve-ConfigurationManagerModulePath \{)', '$1 return $null;'
Set-Content -LiteralPath $f -Value $t -Encoding UTF8
Remove-Item Env:SMS_ADMIN_UI_PATH -ErrorAction SilentlyContinue
Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-File', (Join-Path $appDir 'start-updateplanner.ps1'))
# The start script shows a plain message box with the app name as its title, before any window.
$m = Find-Top 'Update Planner' 40
Start-Sleep -Seconds 1
Shot $m 'start-console-missing'
Log ('message window size: ' + $m.Current.BoundingRectangle.Width + 'x' + $m.Current.BoundingRectangle.Height)
Focus-Win $m; Send-Keys '{ENTER}'; Start-Sleep -Seconds 2
Log ('app processes left: ' + @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -like '*start-updateplanner.ps1*' }).Count)
Stop-App 'start-updateplanner.ps1'
