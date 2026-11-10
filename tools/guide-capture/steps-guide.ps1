# Capture steps of the user guide. Runs in the interactive session on the lab workstation
# (main.ps1 dot-sources it). $Capture holds the values of the caller: SiteCode, SmsProvider and
# Waves (three device collection names of the lab site, in rollout order). The steps read the
# site, run a dry run and open the deploy confirmation, and always select No: they never deploy.
$waves = @($Capture.Waves)
if ($waves.Count -lt 3) { throw 'capture.json needs three wave collection names (Waves).' }
$shortProvider = ([string]$Capture.SmsProvider -split '\.')[0]
$win = Start-App 'start-updateplanner.ps1' 'Update Planner'
Size-Win $win 1440 900
$win = Find-Top 'Update Planner' 10
Section 'first run' {
  Shot $win 'start-first-run'
  Invoke-El (Get-El $win 'btnAddWave'); Start-Sleep -Milliseconds 800; Shot $win 'start-add-without-provider'
  Invoke-El (Get-El $win 'btnOptions'); $dlg = Find-Top 'Options' 10
  Set-Text (Get-El $dlg 'txtSiteCode') 'ab'; Set-Text (Get-El $dlg 'txtSmsProvider') $Capture.SmsProvider
  Invoke-El (Get-El $dlg 'btnOk'); Start-Sleep -Seconds 1
  # The message box of the Options dialog has the app name as its title, not the dialog title.
  $m = Find-Other 'Update Planner' $win; Log ('options windows: ' + (Find-All 'Options').Count)
  Shot $m 'options-bad-site-code'
  Invoke-El (Get-El $m 'OK'); Start-Sleep -Milliseconds 600
  Set-Text (Get-El $dlg 'txtSiteCode') ''
  Invoke-El (Get-El $dlg 'btnOk'); Start-Sleep -Milliseconds 800
  Invoke-El (Get-El $win 'btnAddWave'); Start-Sleep -Milliseconds 800; Shot $win 'start-add-without-site-code'
  Invoke-El (Get-El $win 'btnOptions'); $dlg = Find-Top 'Options' 10
  Set-Text (Get-El $dlg 'txtSiteCode') $Capture.SiteCode
  Shot $dlg 'options-connection'
  Invoke-El (Get-El $dlg 'btnCatAbout'); Start-Sleep -Milliseconds 500; Shot $dlg 'options-about'
  Invoke-El (Get-El $dlg 'btnOk'); Start-Sleep -Milliseconds 800
}
function Add-Wave([string]$filter, [string]$name, [string]$shot) {
  Invoke-El (Get-El $win 'btnAddWave'); $dlg = Find-Top 'Add wave collection' 40; Start-Sleep -Milliseconds 800
  if ($shot) { Set-Text (Get-El $dlg 'txtPickerFilter') 'All'; Start-Sleep -Milliseconds 700; Shot $dlg $shot }
  Set-Text (Get-El $dlg 'txtPickerFilter') $filter; Start-Sleep -Milliseconds 700
  # A picker item is named "<collection name>  (<collection ID>, <n> members)".
  # The name is escaped, so a [ or * in a collection name matches as text.
  $it = Find-NameLike $dlg ('{0}  (*' -f [WildcardPattern]::Escape($name))
  Select-El $it; Start-Sleep -Milliseconds 400
  if ($shot) { Shot $dlg ($shot + '-selected') }
  Invoke-El (Get-El $dlg 'btnOk'); Start-Sleep -Seconds 1
}
Section 'load and picker' {
  Invoke-El (Get-El $win 'btnLoadCollections'); Start-Sleep -Milliseconds 500; Shot $win 'plan-loading'
  $null = Wait-Until { (Get-ElText (Get-El $win 'txtLog')) -like '*Loaded*' } 120
  Add-Wave $waves[0] $waves[0] 'plan-picker'
  Add-Wave $waves[1] $waves[1]
  Add-Wave $waves[2] $waves[2]
  # A wave list item is named "<n>.  <collection name>   (<collection ID>)".
  Select-El (Find-NameLike $win ('2.  {0}   (*' -f [WildcardPattern]::Escape($waves[1]))); Start-Sleep -Milliseconds 500; Shot $win 'plan-waves'
  Invoke-El (Get-El $win 'btnWaveUp'); Start-Sleep -Milliseconds 500; Shot $win 'plan-wave-moved-up'
  Invoke-El (Get-El $win 'btnWaveDown'); Start-Sleep -Milliseconds 500
}
Section 'duplicate' {
  Add-Wave $waves[0] $waves[0]; Shot $win 'plan-duplicate-wave'
}
Section 'invalid' {
  Set-Text (Get-El $win 'txtSpacing') 'x'
  Invoke-El (Get-El $win 'btnBuildPlan'); Start-Sleep -Seconds 1
  $m = Find-Last 'Build plan'; Shot $m 'plan-invalid-input'; Invoke-El (Get-El $m 'OK'); Start-Sleep -Milliseconds 500
  Set-Text (Get-El $win 'txtSpacing') '7'
}
Section 'build' {
  Invoke-El (Get-El $win 'btnBuildPlan'); Start-Sleep -Milliseconds 700; Shot $win 'plan-building'
  $null = Wait-Until { (Get-ElText (Get-El $win 'txtPlanSummary')) -like 'Plan *' } 180
  Shot $win 'plan-planned'
  Select-El (Get-El $win 'tabSkipped'); Start-Sleep -Milliseconds 500; Shot $win 'plan-skipped'
  Select-El (Get-El $win 'tabPlanned')
  Expand-El (Get-El $win 'cboSeverity'); Start-Sleep -Milliseconds 600; Shot $win 'plan-severity' -Hover; Collapse-El (Get-El $win 'cboSeverity')
}
Section 'tab order' {
  Invoke-El (Get-El $win 'btnViewPlan'); Focus-Win $win
  Send-Keys '{TAB}'
  1..32 | ForEach-Object { Send-Keys '{TAB}'; $f = [System.Windows.Automation.AutomationElement]::FocusedElement; Log ('tab -> ' + $f.Current.AutomationId + ' / ' + $f.Current.Name); if ($f.Current.AutomationId -eq 'btnBuildPlan') { Shot $win 'plan-focus-build' -Hover } }
}
Section 'report' {
  Invoke-El (Get-El $win 'btnViewReport'); Shot $win 'report-markdown'
  Select-El (Get-El $win 'rdoHtml'); Start-Sleep -Milliseconds 800; Shot $win 'report-html-source'
  Select-El (Get-El $win 'rdoMarkdown')
  Invoke-El (Get-El $win 'btnCopyReport'); Start-Sleep -Milliseconds 400
  Log ('clipboard: ' + ([System.Windows.Forms.Clipboard]::GetText()).Substring(0, 14))
}
Section 'exports' {
  foreach ($k in 'btnExportJson', 'btnExportMarkdown', 'btnExportHtml') {
    Invoke-El (Get-El $win $k); Start-Sleep -Seconds 2
    $d = Find-Last 'Save As' 15; if ($k -eq 'btnExportJson') { Shot $d 'report-save-dialog' }
    $e = Get-El $d '1001' -Quiet; if ($e) { Log ('file name: ' + (Get-ElText $e)) }
    Focus-Win $d; Send-Keys '{ENTER}'; Start-Sleep -Seconds 2
    Log ('save dialogs left: ' + (Find-All 'Save As').Count)
  }
  Shot $win 'report-exported'
}
Section 'htmlreport' {
  Invoke-El (Get-El $win 'btnOpenHtml'); Start-Sleep -Seconds 6
  $br = $null
  foreach ($try in 1..25) {
    $br = $root.FindAll('Children', [System.Windows.Automation.Condition]::TrueCondition) | Where-Object { $_.Current.Name -match 'Edge' -and $_.Current.Name -match 'Update plan|update-plan' } | Select-Object -First 1
    if ($br) { break }; Start-Sleep -Seconds 2
  }
  Log ('tops: ' + ((@($root.FindAll('Children', [System.Windows.Automation.Condition]::TrueCondition) | ForEach-Object { $_.Current.Name }) -join ' ; ')))
  if (-not $br) { Shot-Screen 'report-html-browser-screen'; throw 'The browser window of the HTML report did not show.' }
  Start-Sleep -Seconds 3; Shot $br 'report-html-browser'
  try { Invoke-El (Get-El $br 'Close') } catch { Log ('edge close failed: ' + $_.Exception.Message) }
  Start-Sleep -Seconds 3
  Focus-Win $win
}
Section 'deploy' {
  Focus-Win $win
  Invoke-El (Get-El $win 'btnViewApply'); Shot $win 'deploy-off'
  Toggle-El (Get-El $win 'toggleActions'); Start-Sleep -Milliseconds 600; Shot $win 'deploy-on'
  Invoke-El (Get-El $win 'btnDryRun'); Start-Sleep -Milliseconds 700; Shot $win 'deploy-dry-run-running'
  $null = Wait-Until { (Get-El $win 'btnDryRun').Current.IsEnabled } 120; Start-Sleep -Seconds 2; Shot $win 'deploy-dry-run'
  Invoke-El (Get-El $win 'btnApply'); $d = Find-Top 'Create deployments' 20; Shot $d 'deploy-confirm'
  Invoke-El (Get-El $d 'btnNo'); Start-Sleep -Milliseconds 800; Shot $win 'deploy-cancelled'
}
Section 'builtin' {
  Invoke-El (Get-El $win 'btnViewPlan')
  Add-Wave 'All Systems' 'All Systems'
  Toggle-El (Get-El $win 'chkWsus'); Set-Text (Get-El $win 'txtMaxUpdates') '2'
  Invoke-El (Get-El $win 'btnBuildPlan'); Start-Sleep -Seconds 2; $null = Wait-Until { (Get-El $win 'btnBuildPlan').Current.IsEnabled } 240
  Shot $win 'plan-builtin-wsus'
  Select-El (Get-El $win 'tabSkipped'); Start-Sleep -Milliseconds 500; Shot $win 'plan-skipped-wave-limit'; Select-El (Get-El $win 'tabPlanned')
  Invoke-El (Get-El $win 'btnViewReport'); Start-Sleep -Milliseconds 400; Shot $win 'report-markdown-wsus'
  Invoke-El (Get-El $win 'btnViewApply'); Start-Sleep -Milliseconds 400
  Invoke-El (Get-El $win 'btnApply'); Start-Sleep -Seconds 1
  $m = Find-Last 'Deploy blocked'; Shot $m 'deploy-blocked'; Invoke-El (Get-El $m 'OK'); Start-Sleep -Milliseconds 600
  Toggle-El (Get-El $win 'toggleActions')
  Invoke-El (Get-El $win 'btnViewPlan')
  Select-El (Find-NameLike $win '4.  All Systems   (*'); Invoke-El (Get-El $win 'btnRemoveWave'); Start-Sleep -Milliseconds 500
  Toggle-El (Get-El $win 'chkWsus'); Set-Text (Get-El $win 'txtMaxUpdates') '1000'
}
Section 'severity filter' {
  $later = (Get-Date).Date.AddDays(10).ToString('d')
  $tomorrow = (Get-Date).Date.AddDays(1).ToString('d')
  Expand-El (Get-El $win 'cboSeverity'); Start-Sleep -Milliseconds 500
  Click-El (Find-Role $win 'ListItem' 'Critical'); Start-Sleep -Milliseconds 500
  Focus-Win $win
  $tb = Get-El (Get-El $win 'dpStartDate') 'PART_TextBox'
  Click-El $tb; Send-Keys '^a'; Send-Keys $later; Send-Keys '{TAB}'; Start-Sleep -Milliseconds 500
  Invoke-El (Get-El $win 'btnBuildPlan'); Start-Sleep -Seconds 2; $null = Wait-Until { (Get-El $win 'btnBuildPlan').Current.IsEnabled } 240
  Shot $win 'plan-severity-critical'
  Select-El (Get-El $win 'tabSkipped'); Start-Sleep -Milliseconds 500; Shot $win 'plan-skipped-severity'
  Select-El (Get-El $win 'tabPlanned')
  Expand-El (Get-El $win 'cboSeverity'); Start-Sleep -Milliseconds 500; Click-El (Find-Role $win 'ListItem' 'All'); Start-Sleep -Milliseconds 400; Focus-Win $win
  $tb = Get-El (Get-El $win 'dpStartDate') 'PART_TextBox'
  Click-El $tb; Send-Keys '^a'; Send-Keys $tomorrow; Send-Keys '{TAB}'; Start-Sleep -Milliseconds 500
}
Section 'keys' {
  Invoke-El (Get-El $win 'btnOptions'); $d = Find-Top 'Options' 10; Focus-Win $d; Send-Keys '{ESC}'; Start-Sleep -Milliseconds 600
  Log ('options open after Esc: ' + (Find-All 'Options').Count)
  Focus-Win $win; Click-El (Get-El $win 'btnViewPlan')
  1..70 | ForEach-Object { Send-Keys '{TAB}'; $f = [System.Windows.Automation.AutomationElement]::FocusedElement; if ($f.Current.AutomationId -eq 'toggleTheme') { Log ('toggle focused after ' + $_ + ' tabs') } }
}
Section 'options clears plan' {
  Invoke-El (Get-El $win 'btnViewPlan'); Select-El (Get-El $win 'tabSkipped'); Start-Sleep -Milliseconds 500
  Invoke-El (Get-El $win 'btnOptions'); $d = Find-Top 'Options' 10
  # A different provider text (the short name) is a change of the connection, which clears the plan.
  Set-Text (Get-El $d 'txtSmsProvider') $shortProvider; Invoke-El (Get-El $d 'btnOk'); Start-Sleep -Seconds 1
  Shot $win 'options-plan-cleared'
}
Section 'light' {
  Toggle-El (Get-El $win 'toggleTheme'); Start-Sleep -Seconds 1
  Invoke-El (Get-El $win 'btnBuildPlan'); Start-Sleep -Seconds 2; $null = Wait-Until { (Get-El $win 'btnBuildPlan').Current.IsEnabled } 180
  Shot $win 'plan-light'
  Select-El (Get-El $win 'tabSkipped'); Start-Sleep -Milliseconds 500; Shot $win 'plan-skipped-light'
  Invoke-El (Get-El $win 'btnViewReport'); Shot $win 'report-light'
  Invoke-El (Get-El $win 'btnViewApply'); Start-Sleep -Milliseconds 800; Toggle-El (Get-El $win 'toggleActions'); Start-Sleep -Milliseconds 600
  Invoke-El (Get-El $win 'btnDryRun'); $null = Wait-Until { (Get-El $win 'btnDryRun').Current.IsEnabled } 120; Start-Sleep -Seconds 2; Shot $win 'deploy-light'
  Invoke-El (Get-El $win 'btnApply'); $d = Find-Top 'Create deployments' 20; Shot $d 'deploy-confirm-light'; Invoke-El (Get-El $d 'btnNo'); Start-Sleep -Milliseconds 600
  Toggle-El (Get-El $win 'toggleActions')
  Invoke-El (Get-El $win 'btnOptions'); $d = Find-Top 'Options' 10; Shot $d 'options-light'; Invoke-El (Get-El $d 'btnCancel'); Start-Sleep -Milliseconds 500
  Toggle-El (Get-El $win 'toggleTheme')
}
Section 'persist' {
  Invoke-El (Get-El $win 'btnViewApply'); Start-Sleep -Milliseconds 500
  Invoke-El (Get-El $win 'Close'); Start-Sleep -Seconds 3
  Log ('app still running: ' + @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -like '*start-updateplanner.ps1*' }).Count)
  $win = Start-App 'start-updateplanner.ps1' 'Update Planner'; Shot $win 'start-reopen-saved-state'
}
Stop-App 'start-updateplanner.ps1'
Get-Process msedge -ErrorAction SilentlyContinue | Where-Object { $_.StartTime -gt (Get-Date).AddMinutes(-30) } | ForEach-Object { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }
