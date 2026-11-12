<#
.SYNOPSIS
    Main window of Update Planner, a tool that plans software update rollouts in waves for a Configuration Manager site.

.DESCRIPTION
    Sidebar navigation across three views (Plan, Report, Deploy). The Plan view
    holds the wave collections, the dates and the plan grids. The Report view
    shows the plan as Markdown or HTML. The Deploy view holds the Enable
    actions switch, the dry run and the deployment step.

    The tool reads the site with the permissions of the signed-in user. It
    stores no password. It changes nothing on the site until the Enable
    actions switch is on and the person confirms the deployment.

    Requirements:
      - PowerShell 5.1
      - .NET Framework 4.7.2+
      - MahApps.Metro DLLs in .\Lib\
      - UpdatePlannerCommon module under .\Module\
      - Configuration Manager console on this computer (it provides the
        ConfigurationManager PowerShell module)
      - Access to the SMS Provider computer

.NOTES
    ScriptName : start-updateplanner.ps1
    Version    : 2026.11.10.0005
    Updated    : 2026-11-07
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '', Justification='$global: survives closure scope-strip in WPF event handlers.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification='WPF event handler scriptblocks bind positional sender/args ($s, $e).')]
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$__txDir = Join-Path $PSScriptRoot 'Logs'
try {
    if (-not (Test-Path -LiteralPath $__txDir)) { New-Item -ItemType Directory -Path $__txDir -Force | Out-Null }
    $__tx = Join-Path $__txDir ('UpdatePlanner-startup-{0}.txt' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Start-Transcript -LiteralPath $__tx -Force | Out-Null
} catch { $null = $_ }

if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    $psExe = (Get-Process -Id $PID).Path
    $fwd   = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-File', $PSCommandPath)
    Start-Process -FilePath $psExe -ArgumentList $fwd | Out-Null
    try { Stop-Transcript | Out-Null } catch { $null = $_ }
    exit 0
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

$libDir = Join-Path $PSScriptRoot 'Lib'
if (-not (Test-Path -LiteralPath $libDir)) { throw "Lib/ directory not found at: $libDir." }
Get-ChildItem -LiteralPath $libDir -File -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue
[void][System.Reflection.Assembly]::LoadFrom((Join-Path $libDir 'Microsoft.Xaml.Behaviors.dll'))
[void][System.Reflection.Assembly]::LoadFrom((Join-Path $libDir 'ControlzEx.dll'))
[void][System.Reflection.Assembly]::LoadFrom((Join-Path $libDir 'MahApps.Metro.dll'))

$__modulePath = Join-Path $PSScriptRoot 'Module\UpdatePlannerCommon.psd1'
if (-not (Test-Path -LiteralPath $__modulePath)) { throw "Shared module not found at: $__modulePath" }
Import-Module -Name $__modulePath -Force -DisableNameChecking

# The site is read with the ConfigurationManager module, which comes only with the
# Configuration Manager console. Without it the tool stops here with a plain message.
$__console = Test-UpConsoleModule
if (-not $__console.Available) {
    Write-Warning -Message $__console.Message
    [void][System.Windows.MessageBox]::Show($__console.Message, 'Update Planner', [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
    try { Stop-Transcript | Out-Null } catch { $null = $_ }
    exit 2
}

$global:PrefsPath = Join-Path $PSScriptRoot 'UpdatePlanner.prefs.json'
function Get-UpPreferences {
    return Read-SuiteSettings -Path $global:PrefsPath -Defaults @{
        DarkMode = $true; SiteCode = ''; SMSProvider = ''
        WaveSpacingDays = '7'; DeadlineDays = '3'; Severity = 'All'; MaxUpdates = '1000'
        IncludeWsus = $false; Waves = @()
    }
}
function Save-UpPreferences {
    param([Parameter(Mandatory)][hashtable]$Prefs)
    $null = Save-SuiteSettings -Path $global:PrefsPath -Settings $Prefs
}
$global:Prefs = Get-UpPreferences

# The suite launcher hands its site code and provider to each tool it starts.
# A value saved in this tool wins; the launcher value fills an empty one.
if (-not $global:Prefs.SiteCode    -and $env:SUITE_CM_SITECODE) { $global:Prefs.SiteCode    = [string]$env:SUITE_CM_SITECODE }
if (-not $global:Prefs.SMSProvider -and $env:SUITE_CM_PROVIDER) { $global:Prefs.SMSProvider = [string]$env:SUITE_CM_PROVIDER }

$script:ToolLogPath = Join-Path $__txDir ('UpdatePlanner-{0}.log' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
$script:ActionLogPath = Join-Path $__txDir 'update-planner-actions.jsonl'
Initialize-Logging -LogPath $script:ToolLogPath

$xamlPath = Join-Path $PSScriptRoot 'MainWindow.xaml'
[xml]$xaml = Get-Content -LiteralPath $xamlPath -Raw
$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [System.Windows.Markup.XamlReader]::Load($reader)

$txtAppTitle = $window.FindName('txtAppTitle')
$txtVersion  = $window.FindName('txtVersion')
# Installed version: the script header is the single source of truth for the
# sidebar label and the About panel.
$script:AppVersion = '0.0.0'
foreach ($headerLine in (Get-Content -LiteralPath $PSCommandPath -TotalCount 80)) {
    if ($headerLine -match '^\s*Version\s*:\s*([0-9][0-9\.]*[0-9])\s*$') { $script:AppVersion = $Matches[1]; break }
}
if ($txtVersion) { $txtVersion.Text = 'v' + $script:AppVersion }
$txtThemeLabel = $window.FindName('txtThemeLabel')
$toggleTheme   = $window.FindName('toggleTheme')

$btnViewPlan   = $window.FindName('btnViewPlan')
$btnViewReport = $window.FindName('btnViewReport')
$btnViewApply  = $window.FindName('btnViewApply')
$btnOptions    = $window.FindName('btnOptions')

$txtModuleTitle    = $window.FindName('txtModuleTitle')
$txtModuleSubtitle = $window.FindName('txtModuleSubtitle')

$btnBuildPlan       = $window.FindName('btnBuildPlan')
$btnLoadCollections = $window.FindName('btnLoadCollections')
$btnExportJson      = $window.FindName('btnExportJson')
$btnExportMarkdown  = $window.FindName('btnExportMarkdown')
$btnExportHtml      = $window.FindName('btnExportHtml')

$viewPlan   = $window.FindName('viewPlan')
$viewReport = $window.FindName('viewReport')
$viewApply  = $window.FindName('viewApply')

$lstWaves      = $window.FindName('lstWaves')
$btnAddWave    = $window.FindName('btnAddWave')
$btnRemoveWave = $window.FindName('btnRemoveWave')
$btnWaveUp     = $window.FindName('btnWaveUp')
$btnWaveDown   = $window.FindName('btnWaveDown')
$dpStartDate   = $window.FindName('dpStartDate')
$txtSpacing    = $window.FindName('txtSpacing')
$txtDeadline   = $window.FindName('txtDeadline')
$cboSeverity   = $window.FindName('cboSeverity')
$txtMaxUpdates = $window.FindName('txtMaxUpdates')
$chkWsus       = $window.FindName('chkWsus')
$txtPlanSummary = $window.FindName('txtPlanSummary')
$gridPlan      = $window.FindName('gridPlan')
$gridSkipped   = $window.FindName('gridSkipped')
$txtTabSkipped = $window.FindName('txtTabSkipped')

$rdoMarkdown  = $window.FindName('rdoMarkdown')
$rdoHtml      = $window.FindName('rdoHtml')
$btnOpenHtml  = $window.FindName('btnOpenHtml')
$btnCopyReport = $window.FindName('btnCopyReport')
$txtReport    = $window.FindName('txtReport')

$toggleActions = $window.FindName('toggleActions')
$btnDryRun     = $window.FindName('btnDryRun')
$btnApply      = $window.FindName('btnApply')
$gridPreview   = $window.FindName('gridPreview')
$gridResults   = $window.FindName('gridResults')

$progressOverlay  = $window.FindName('progressOverlay')
$txtProgressTitle = $window.FindName('txtProgressTitle')
$txtProgressStep  = $window.FindName('txtProgressStep')

$lblLogOutput = $window.FindName('lblLogOutput')
$txtLog       = $window.FindName('txtLog')
$txtStatus    = $window.FindName('txtStatus')
$txtStatusSiteCode = $window.FindName('txtSiteCode')
$txtStatusProvider = $window.FindName('txtSmsProvider')

$null = $txtAppTitle

function Add-LogLine {
    param([Parameter(Mandatory)][string]$Message)
    $ts = (Get-Date).ToString('HH:mm:ss')
    $line = '{0}  {1}' -f $ts, $Message
    if ([string]::IsNullOrWhiteSpace($txtLog.Text)) { $txtLog.Text = $line }
    else { $txtLog.AppendText([Environment]::NewLine + $line) }
    $txtLog.ScrollToEnd()
    try { Write-Log -Message $Message -Quiet } catch { $null = $_ }
}

function Set-StatusText {
    param([Parameter(Mandatory)][string]$Text)
    $txtStatus.Text = $Text
}

# === Title-bar drag fallback: SuiteCommon owns the hook ===
Install-TitleBarDragFallback -Window $window

# === Theme (palette, sidebar, title bar, dialogs: SuiteCommon) ===
[void][ControlzEx.Theming.ThemeManager]::Current.ChangeTheme($window, 'Dark.Steel')

$script:ViewButtons = @(
    @{ Name = 'Plan';   Button = $btnViewPlan }
    @{ Name = 'Report'; Button = $btnViewReport }
    @{ Name = 'Deploy'; Button = $btnViewApply }
)
$script:ActiveView = 'Plan'

# Contrast fixes of the SuiteCommon palette. The sidebar button border is 2.06:1 at #555555 on the
# dark window; #8A8A8A is 4.4:1. White title text is 2.6:1 on the light inactive title bar #4BA3E0;
# #595959 is 7.0:1. Window.Tests.ps1 reads this table, so the test checks the same values.
$script:SuiteBrushOverride = @{
    DarkButtonBorder = '#8A8A8A'
    TitleBarInactive = '#595959'
}
$__brushConverter = [System.Windows.Media.BrushConverter]::new()
$__suiteBrushes = @{}
foreach ($__key in $script:SuiteBrushOverride.Keys) { $__suiteBrushes[$__key] = $__brushConverter.ConvertFrom($script:SuiteBrushOverride[$__key]) }

Initialize-SuiteTheme -Window $window `
    -IsDarkGetter { [bool]$global:Prefs['DarkMode'] } `
    -ActiveViewGetter { $script:ActiveView } `
    -ViewButtons $script:ViewButtons `
    -OptionsButton $btnOptions `
    -LogLabel $lblLogOutput `
    -Brushes $__suiteBrushes

$__startIsDark = [bool]$global:Prefs['DarkMode']
$toggleTheme.IsOn = $__startIsDark
$txtThemeLabel.Text = if ($__startIsDark) { 'Dark Theme' } else { 'Light Theme' }
Update-SidebarButtonTheme

$toggleTheme.Add_Toggled({
    $isDark = [bool]$toggleTheme.IsOn
    if ($isDark) { [void][ControlzEx.Theming.ThemeManager]::Current.ChangeTheme($window, 'Dark.Steel'); $txtThemeLabel.Text = 'Dark Theme' }
    else         { [void][ControlzEx.Theming.ThemeManager]::Current.ChangeTheme($window, 'Light.Blue'); $txtThemeLabel.Text = 'Light Theme' }
    $global:Prefs['DarkMode'] = $isDark
    Save-UpPreferences -Prefs $global:Prefs
    Update-SidebarButtonTheme
    Update-TitleBarBrushes
    Add-LogLine ('Theme: {0}' -f $(if ($isDark) { 'dark' } else { 'light' }))
})

# === Crash handlers ===
$global:__crashLog = Join-Path $__txDir ('UpdatePlanner-crash-{0}.txt' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
$global:__writeCrash = {
    param($Source, $Exception)
    try {
        $lines = @(('=== ' + $Source + ' @ ' + (Get-Date -Format 'o') + ' ==='))
        $lines += ('Type   : ' + $Exception.GetType().FullName)
        $lines += ('Message: ' + $Exception.Message)
        if ($Exception -is [System.Management.Automation.IContainsErrorRecord] -and $Exception.ErrorRecord.InvocationInfo) { $lines += ('At     : ' + $Exception.ErrorRecord.InvocationInfo.PositionMessage) }
        $lines += ([string]$Exception.StackTrace).Split([Environment]::NewLine)
        [System.IO.File]::AppendAllText($global:__crashLog, (($lines -join [Environment]::NewLine) + [Environment]::NewLine))
    } catch { $null = $_ }
}
$window.Dispatcher.Add_UnhandledException({ param($s, $e) & $global:__writeCrash 'DispatcherUnhandledException' $e.Exception; $e.Handled = $false })
[AppDomain]::CurrentDomain.Add_UnhandledException({ param($s, $e) & $global:__writeCrash 'AppDomainUnhandledException' ([Exception]$e.ExceptionObject) })

# === State ===
$script:Plan        = $null
$script:CollectionData = $null
$script:WaveList    = @()
$script:IsBusy      = $false
$script:PickAfterLoad = $false
$script:LastResults = @()

# === Control state ===
function Update-ControlState {
    $hasPlan = [bool]$script:Plan
    $actionsOn = [bool]$toggleActions.IsOn
    $idle = -not $script:IsBusy
    $btnBuildPlan.IsEnabled       = $idle
    $btnOptions.IsEnabled         = $idle
    $btnLoadCollections.IsEnabled = $idle
    $btnAddWave.IsEnabled         = $idle
    $btnExportJson.IsEnabled      = $hasPlan
    $btnExportMarkdown.IsEnabled  = $hasPlan
    $btnExportHtml.IsEnabled      = $hasPlan
    $btnOpenHtml.IsEnabled        = $hasPlan
    $btnCopyReport.IsEnabled      = $hasPlan
    $btnDryRun.IsEnabled          = $idle -and $hasPlan -and $actionsOn
    $btnApply.IsEnabled           = $idle -and $hasPlan -and $actionsOn
    $hasSel = $lstWaves.SelectedIndex -ge 0
    $btnRemoveWave.IsEnabled      = $idle -and $hasSel
    $btnWaveUp.IsEnabled          = $idle -and $hasSel -and $lstWaves.SelectedIndex -gt 0
    $btnWaveDown.IsEnabled        = $idle -and $hasSel -and $lstWaves.SelectedIndex -lt ($script:WaveList.Count - 1)
}

# === View switching ===
$script:ViewMeta = @{
    'Plan'   = @{ Title = 'Plan';   Subtitle = 'Add the wave collections in the order of the rollout, set the dates, then click Build Plan. Building a plan changes nothing on the site.' }
    'Report' = @{ Title = 'Report'; Subtitle = 'The plan as the Markdown review text or as an HTML report.' }
    'Deploy' = @{ Title = 'Deploy'; Subtitle = 'Turn on Enable Actions to use the dry run and the deployment step. Every deployment asks for a confirmation.' }
}
function Set-ActiveView {
    param([Parameter(Mandatory)][ValidateSet('Plan', 'Report', 'Deploy')][string]$View)
    $script:ActiveView = $View
    $viewPlan.Visibility   = if ($View -eq 'Plan')   { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
    $viewReport.Visibility = if ($View -eq 'Report') { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
    $viewApply.Visibility  = if ($View -eq 'Deploy') { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
    $meta = $script:ViewMeta[$View]
    if ($meta) {
        $txtModuleTitle.Text    = $meta.Title
        $txtModuleSubtitle.Text = $meta.Subtitle
    }
    Update-SidebarButtonTheme
    Update-StatusBarSummary
}
$btnViewPlan.Add_Click({   Set-ActiveView -View 'Plan' })
$btnViewReport.Add_Click({ Set-ActiveView -View 'Report' })
$btnViewApply.Add_Click({  Set-ActiveView -View 'Deploy' })

function Update-StatusBarSummary {
    $txtStatusSiteCode.Text = if ($global:Prefs.SiteCode) { [string]$global:Prefs.SiteCode } else { 'not set' }
    $txtStatusProvider.Text = if ($global:Prefs.SMSProvider) { [string]$global:Prefs.SMSProvider } else { 'not set' }
    $parts = @()
    if (-not $global:Prefs.SMSProvider) { $parts += 'Open Options to set the SMS Provider' }
    $parts += ('{0} wave collections' -f $script:WaveList.Count)
    if ($script:Plan) { $parts += ('plan {0}: {1} assignments' -f $script:Plan.PlanId, $script:Plan.Summary.UpdateAssignmentsPlanned) }
    if ($toggleActions.IsOn) { $parts += 'actions enabled' } else { $parts += 'read only' }
    Set-StatusText ($parts -join '   |   ')
}

# === Wave list ===
function Update-WaveList {
    param([int]$Select = -1)
    $items = @()
    $i = 0
    foreach ($w in $script:WaveList) {
        $i++
        $items += ('{0}.  {1}   ({2})' -f $i, $w.Name, $w.Id)
    }
    $lstWaves.ItemsSource = $null
    $lstWaves.ItemsSource = $items
    if ($Select -ge 0 -and $Select -lt $items.Count) { $lstWaves.SelectedIndex = $Select }
    $global:Prefs['Waves'] = @($script:WaveList | ForEach-Object { '{0}|{1}' -f $_.Id, $_.Name })
    Update-ControlState
    Update-StatusBarSummary
}
foreach ($entry in @($global:Prefs['Waves'])) {
    $bits = ([string]$entry).Split('|', 2)
    if ($bits.Count -eq 2 -and $bits[0] -match '^[A-Za-z0-9]{8}$') { $script:WaveList += [pscustomobject]@{ Id = $bits[0]; Name = $bits[1] } }
}
$lstWaves.Add_SelectionChanged({ Update-ControlState })
$btnRemoveWave.Add_Click({
    $i = $lstWaves.SelectedIndex
    if ($i -lt 0) { return }
    $script:WaveList = @($script:WaveList | Where-Object { $_ -ne $script:WaveList[$i] })
    Update-WaveList -Select ([Math]::Min($i, $script:WaveList.Count - 1))
})
$btnWaveUp.Add_Click({
    $i = $lstWaves.SelectedIndex
    if ($i -lt 1) { return }
    $copy = @($script:WaveList)
    $copy[$i - 1], $copy[$i] = $copy[$i], $copy[$i - 1]
    $script:WaveList = $copy
    Update-WaveList -Select ($i - 1)
})
$btnWaveDown.Add_Click({
    $i = $lstWaves.SelectedIndex
    if ($i -lt 0 -or $i -ge ($script:WaveList.Count - 1)) { return }
    $copy = @($script:WaveList)
    $copy[$i + 1], $copy[$i] = $copy[$i], $copy[$i + 1]
    $script:WaveList = $copy
    Update-WaveList -Select ($i + 1)
})

# === Settings fields ===
$dpStartDate.SelectedDate = (Get-Date).Date.AddDays(1)
$txtSpacing.Text    = [string]$global:Prefs['WaveSpacingDays']
$txtDeadline.Text   = [string]$global:Prefs['DeadlineDays']
$txtMaxUpdates.Text = [string]$global:Prefs['MaxUpdates']
$chkWsus.IsChecked  = [bool]$global:Prefs['IncludeWsus']
foreach ($item in $cboSeverity.Items) { if ([string]$item.Content -eq [string]$global:Prefs['Severity']) { $item.IsSelected = $true } }

function Get-SeverityName {
    if ($cboSeverity.SelectedItem) { return [string]$cboSeverity.SelectedItem.Content }
    return 'All'
}

function Save-SettingsToPrefs {
    $global:Prefs['WaveSpacingDays'] = [string]$txtSpacing.Text
    $global:Prefs['DeadlineDays']    = [string]$txtDeadline.Text
    $global:Prefs['MaxUpdates']      = [string]$txtMaxUpdates.Text
    $global:Prefs['IncludeWsus']     = [bool]$chkWsus.IsChecked
    $global:Prefs['Severity']        = Get-SeverityName
    Save-UpPreferences -Prefs $global:Prefs
}

# === Bg runspace ===
$script:BgRunspace     = $null
$script:BgPowerShell   = $null
$script:BgInvokeHandle = $null
$script:BgState        = $null
$script:BgTimer        = $null
$script:BgGraveyard    = @()
$script:BgOnDone       = $null

function Initialize-BgRunspace {
    if ($script:BgRunspace -and $script:BgRunspace.RunspaceStateInfo.State -eq 'Opened') { return }
    $script:BgRunspace = New-SuiteBgRunspace -ModulePath $__modulePath -LogPath $script:ToolLogPath
}

function Stop-BackgroundWork {
    $script:BgGraveyard = @(Stop-SuiteBgWork -PowerShell $script:BgPowerShell -Timer $script:BgTimer -Graveyard $script:BgGraveyard)
    $script:BgTimer = $null
    $script:BgPowerShell = $null
    $script:BgInvokeHandle = $null
}

function Start-BackgroundWork {
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Step,
        [Parameter(Mandatory)][scriptblock]$Work,
        [Parameter(Mandatory)][hashtable]$Arguments,
        [Parameter(Mandatory)][scriptblock]$OnDone
    )
    Initialize-BgRunspace
    Stop-BackgroundWork
    $script:BgState = [hashtable]::Synchronized(@{ Step = $Step; Done = $false; Result = $null; ErrorMsg = $null })
    $script:BgOnDone = $OnDone
    $script:IsBusy = $true
    Update-ControlState
    $txtProgressTitle.Text = $Title
    $txtProgressStep.Text  = $Step
    $progressOverlay.Visibility = [System.Windows.Visibility]::Visible
    Set-StatusText ($Title + '...')

    $script:BgPowerShell = [powershell]::Create()
    $script:BgPowerShell.Runspace = $script:BgRunspace
    [void]$script:BgPowerShell.AddScript({
        param($WorkText, $Arguments, $State)
        try { $State.Result = & ([scriptblock]::Create($WorkText)) $Arguments $State }
        catch { $State.ErrorMsg = $_.Exception.Message }
        finally { $State.Done = $true }
    }).AddArgument($Work.ToString()).AddArgument($Arguments).AddArgument($script:BgState)

    $script:BgInvokeHandle = $script:BgPowerShell.BeginInvoke()
    $script:BgTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:BgTimer.Interval = [TimeSpan]::FromMilliseconds(150)
    $script:BgTimer.Add_Tick({
        if ($script:BgState) { $current = [string]$script:BgState.Step; if ($txtProgressStep.Text -ne $current) { $txtProgressStep.Text = $current } }
        if ($script:BgState -and $script:BgState.Done) {
            $script:BgTimer.Stop()
            try { [void]$script:BgPowerShell.EndInvoke($script:BgInvokeHandle) } catch { $null = $_ }
            try { $script:BgPowerShell.Dispose() } catch { $null = $_ }
            $script:BgPowerShell   = $null
            $script:BgInvokeHandle = $null
            $progressOverlay.Visibility = [System.Windows.Visibility]::Collapsed
            $script:IsBusy = $false
            Update-ControlState
            if ($script:BgState.ErrorMsg) {
                # The window shows a fixed message. The exception text goes to the log file only.
                try { Write-Log -Message ('Step failed: {0}' -f $script:BgState.ErrorMsg) -Level ERROR -Quiet } catch { $null = $_ }
                Add-LogLine 'The step failed. The log file has the details.'
                Set-StatusText 'The step failed. The log file has the details.'
                [void](Show-ThemedMessage -Owner $window -Title 'Step Failed' -Message 'The step failed. Check the site code, the SMS Provider and your account rights in Options. The log file has the details.' -Icon Error)
                return
            }
            & $script:BgOnDone $script:BgState.Result
        }
    })
    $script:BgTimer.Start()
}

# === Collections ===
$btnLoadCollections.Add_Click({ Invoke-LoadCollections -Pick $false })
function Invoke-LoadCollections {
    param([bool]$Pick)
    if (-not $global:Prefs.SMSProvider -or -not $global:Prefs.SiteCode) {
        Add-LogLine 'Load Collections: set the SMS Provider and the site code in Options first.'
        Set-StatusText 'Open Options to set the SMS Provider and the site code.'
        return
    }
    $script:PickAfterLoad = $Pick
    Add-LogLine ('Load Collections: provider={0}' -f $global:Prefs.SMSProvider)
    $args1 = @{ Provider = [string]$global:Prefs.SMSProvider; SiteCode = [string]$global:Prefs.SiteCode }
    Start-BackgroundWork -Title 'Loading Collections' -Step 'Reading device collections and console folders...' -Arguments $args1 -Work {
        param($A, $S)
        Get-UpdatePlannerCollection -ComputerName $A.Provider -SiteCode $A.SiteCode
    } -OnDone {
        param($r)
        $script:CollectionData = $r
        Add-LogLine ('Loaded {0} device collections in {1} folders (site {2}).' -f @($r.Collections).Count, @($r.Folders).Count, $r.SiteCode)
        Set-StatusText ('{0} device collections loaded.' -f @($r.Collections).Count)
        if ($script:PickAfterLoad) { $script:PickAfterLoad = $false; Show-WavePicker }
    }
}

function Show-WavePicker {
    $picked = Show-CollectionPickerDialog -Owner $window -Collections $script:CollectionData.Collections -Folders $script:CollectionData.Folders -Title 'Add Wave Collection'
    if (-not $picked) { return }
    if (@($script:WaveList | Where-Object { $_.Id -eq [string]$picked.CollectionID }).Count -gt 0) {
        Add-LogLine ('{0} is already in the wave list.' -f $picked.Name)
        return
    }
    $script:WaveList += [pscustomobject]@{ Id = [string]$picked.CollectionID; Name = [string]$picked.Name }
    Update-WaveList -Select ($script:WaveList.Count - 1)
    Add-LogLine ('Added wave {0}: {1} ({2})' -f $script:WaveList.Count, $picked.Name, $picked.CollectionID)
}

$btnAddWave.Add_Click({
    if (-not $global:Prefs.SMSProvider -or -not $global:Prefs.SiteCode) {
        Set-StatusText 'Open Options to set the SMS Provider and the site code.'
        Add-LogLine 'Add: set the SMS Provider and the site code in Options first.'
        return
    }
    if (-not $script:CollectionData) { Invoke-LoadCollections -Pick $true; return }
    Show-WavePicker
})

# === Plan ===
function Show-Plan {
    param($Plan)
    $script:Plan = $Plan
    $gridPlan.ItemsSource    = @(ConvertTo-UpdatePlanRow -Plan $Plan)
    $gridSkipped.ItemsSource = @(ConvertTo-UpdatePlanSkippedRow -Plan $Plan)
    $txtTabSkipped.Text = ('Skipped Updates ({0})' -f @($Plan.Skipped).Count)
    $s = $Plan.Summary
    $txtPlanSummary.Text = ('Plan {0} for site {1}. {2} waves, {3} planned assignments, {4} skipped and listed. Site: {5} updates, {6} needed, {7} superseded, {8} expired, {9} existing deployments.' -f
        $Plan.PlanId, $Plan.SiteCode, $s.WavesPlanned, $s.UpdateAssignmentsPlanned, $s.SkippedListed, $s.TotalUpdates, $s.NeededUpdates, $s.SupersededUpdates, $s.ExpiredUpdates, $s.ExistingDeployments)
    $gridPreview.ItemsSource = @(Get-UpdatePlanDeploymentPreview -Plan $Plan)
    $gridResults.ItemsSource = $null
    Update-ReportText
    Update-ControlState
    Update-StatusBarSummary
}

$btnBuildPlan.Add_Click({
    $setting = Resolve-UpdatePlannerSetting `
        -ComputerName ([string]$global:Prefs.SMSProvider) -SiteCode ([string]$global:Prefs.SiteCode) `
        -StartDateText $(if ($dpStartDate.SelectedDate) { ([datetime]$dpStartDate.SelectedDate).ToString('yyyy-MM-dd') } else { '' }) `
        -WaveSpacingText ([string]$txtSpacing.Text) -DeadlineText ([string]$txtDeadline.Text) `
        -SeverityName (Get-SeverityName) -MaxUpdatesText ([string]$txtMaxUpdates.Text) `
        -TargetCollection @($script:WaveList | ForEach-Object { $_.Id })
    if (-not $setting.IsValid) {
        Add-LogLine ('Build Plan: {0}' -f ($setting.Errors -join ' '))
        Set-StatusText $setting.Errors[0]
        [void](Show-ThemedMessage -Owner $window -Title 'Build Plan' -Message ($setting.Errors -join [Environment]::NewLine) -Icon Warn)
        return
    }
    Save-SettingsToPrefs
    Add-LogLine ('Build Plan: {0} waves, start {1}, spacing {2} days, deadline {3} days, lowest severity {4}' -f $setting.TargetCollection.Count, $setting.StartDate.ToString('yyyy-MM-dd'), $setting.WaveSpacingDays, $setting.DeadlineDays, (Get-SeverityName))
    $args2 = @{
        Provider = $setting.ComputerName; SiteCode = [string]$global:Prefs.SiteCode
        Target = $setting.TargetCollection; Start = $setting.StartDate; Spacing = $setting.WaveSpacingDays
        Deadline = $setting.DeadlineDays; Severity = $setting.MinimumSeverity; Max = $setting.MaxUpdatesPerWave
        Wsus = [bool]$chkWsus.IsChecked
    }
    Start-BackgroundWork -Title 'Building the Plan' -Step 'Connecting to the SMS Provider...' -Arguments $args2 -Work {
        param($A, $S)
        $p = @{ ComputerName = $A.Provider; SiteCode = $A.SiteCode; TargetCollection = $A.Target; IncludeWsus = $A.Wsus }
        $S.Step = 'Reading updates, collections and deployments...'
        $state = Get-UpdatePlannerState @p
        $S.Step = 'Building the waves...'
        New-UpdatePlan -State $state -StartDate $A.Start -WaveSpacingDays $A.Spacing -DeadlineDays $A.Deadline -MinimumSeverity $A.Severity -MaxUpdatesPerWave $A.Max
    } -OnDone {
        param($plan)
        Show-Plan -Plan $plan
        Add-LogLine ('Plan {0}: {1} waves, {2} assignments, {3} skipped.' -f $plan.PlanId, $plan.Summary.WavesPlanned, $plan.Summary.UpdateAssignmentsPlanned, $plan.Summary.SkippedListed)
    }
})

# === Report ===
function Get-ReportText {
    if (-not $script:Plan) { return 'Build a plan to see the report.' }
    if ($rdoHtml.IsChecked) { return (ConvertTo-UpdatePlanHtml -Plan $script:Plan) }
    return (ConvertTo-UpdatePlanMarkdown -Plan $script:Plan)
}
function Update-ReportText { $txtReport.Text = Get-ReportText }
$rdoMarkdown.Add_Checked({ Update-ReportText })
$rdoHtml.Add_Checked({ Update-ReportText })
$btnCopyReport.Add_Click({
    if ($script:Plan) { [System.Windows.Clipboard]::SetText((Get-ReportText)); Add-LogLine 'Report copied to the clipboard.' }
})

# === Exports ===
function Save-TextExport {
    param(
        [Parameter(Mandatory)][string]$Kind, [Parameter(Mandatory)][string]$Extension,
        [Parameter(Mandatory)][string]$Filter, [Parameter(Mandatory)][string]$Text
    )
    if (-not $script:Plan) { Add-LogLine ('Export {0}: build a plan first.' -f $Kind); return }
    $sfd = New-Object Microsoft.Win32.SaveFileDialog
    $sfd.Filter = $Filter
    $sfd.FileName = ('update-plan-{0}.{1}' -f $script:Plan.PlanId, $Extension)
    $reportsDir = Join-Path $PSScriptRoot 'Reports'
    if (-not (Test-Path -LiteralPath $reportsDir)) { New-Item -ItemType Directory -Path $reportsDir -Force | Out-Null }
    $sfd.InitialDirectory = $reportsDir
    if ($sfd.ShowDialog() -eq $true) {
        $written = Write-UpdatePlanFile -Path $sfd.FileName -Text $Text
        Add-LogLine ('Exported {0}: {1}' -f $Kind, $written)
    }
}
$btnExportJson.Add_Click({     Save-TextExport -Kind 'JSON'     -Extension 'json' -Filter 'JSON files (*.json)|*.json'     -Text (ConvertTo-UpdatePlanJson -Plan $script:Plan) })
$btnExportMarkdown.Add_Click({ Save-TextExport -Kind 'Markdown' -Extension 'md'   -Filter 'Markdown files (*.md)|*.md'     -Text (ConvertTo-UpdatePlanMarkdown -Plan $script:Plan) })
$btnExportHtml.Add_Click({     Save-TextExport -Kind 'HTML'     -Extension 'html' -Filter 'HTML files (*.html)|*.html'     -Text (ConvertTo-UpdatePlanHtml -Plan $script:Plan) })
$btnOpenHtml.Add_Click({
    if (-not $script:Plan) { return }
    $path = Join-Path (Join-Path $PSScriptRoot 'Reports') ('update-plan-{0}.html' -f $script:Plan.PlanId)
    $written = Write-UpdatePlanFile -Path $path -Text (ConvertTo-UpdatePlanHtml -Plan $script:Plan)
    Add-LogLine ('HTML report written: {0}' -f $written)
    Start-Process -FilePath $written
})

# === Deploy ===
function Write-ActionRecord {
    param([Parameter(Mandatory)][string]$Action, [Parameter(Mandatory)]$Results)
    try {
        Write-UpdatePlanAudit -Path $script:ActionLogPath -Record ([pscustomobject]@{
            Time     = (Get-Date).ToString('o')
            User     = ('{0}\{1}' -f [Environment]::UserDomainName, [Environment]::UserName)
            Computer = [Environment]::MachineName
            Action   = $Action
            PlanId   = $script:Plan.PlanId
            Site     = $script:Plan.SiteCode
            Provider = [string]$global:Prefs.SMSProvider
            Results  = @($Results)
        })
    } catch {
        try { Write-Log -Message ('The action log could not be written: {0}' -f $_.Exception.Message) -Level ERROR -Quiet } catch { $null = $_ }
        Add-LogLine 'The action log could not be written. The log file has the details.'
    }
}

function Show-DeployResult {
    param([string]$Action, $Results)
    $script:LastResults = @($Results)
    $gridResults.ItemsSource = @(ConvertTo-UpdatePlanResultRow -Result @($Results) -DryRun:($Action -eq 'DryRun'))
    Write-ActionRecord -Action $Action -Results $Results
    $created = @($Results | Where-Object { $_.Status -eq 'Created' }).Count
    $failed  = @($Results | Where-Object { $_.Status -eq 'Failed' }).Count
    Add-LogLine ('{0}: {1} results, {2} created, {3} failed.' -f $Action, @($Results).Count, $created, $failed)
    Set-StatusText ('{0} finished: {1} created, {2} failed.' -f $Action, $created, $failed)
}

$toggleActions.Add_Toggled({
    Update-ControlState
    Update-StatusBarSummary
    Add-LogLine ('Enable Actions: {0}' -f $(if ($toggleActions.IsOn) { 'on' } else { 'off' }))
})

$btnDryRun.Add_Click({
    if (-not $script:Plan -or -not $toggleActions.IsOn) { return }
    Add-LogLine ('Dry Run of plan {0} (-WhatIf).' -f $script:Plan.PlanId)
    Start-BackgroundWork -Title 'Dry Run' -Step 'Running the deploy step with -WhatIf...' -Arguments @{ Plan = $script:Plan; Provider = [string]$global:Prefs.SMSProvider } -Work {
        param($A, $S)
        @(Invoke-UpdatePlan -Plan $A.Plan -ComputerName $A.Provider -Apply -WhatIf)
    } -OnDone {
        param($r)
        Show-DeployResult -Action 'DryRun' -Results $r
    }
})

$btnApply.Add_Click({
    if (-not $script:Plan -or -not $toggleActions.IsOn) { return }
    $check = Test-UpdatePlanApplyAllowed -Plan $script:Plan
    if (-not $check.IsAllowed) {
        Add-LogLine ('Deploy blocked: {0}' -f ($check.Reasons -join ' '))
        [void](Show-ThemedMessage -Owner $window -Title 'Deploy Blocked' -Message ($check.Reasons -join [Environment]::NewLine) -Icon Warn)
        return
    }
    $preview = @(Get-UpdatePlanDeploymentPreview -Plan $script:Plan)
    $lines = @($preview | ForEach-Object { '{0}: {1} updates, {2} to {3}' -f $_.Collection, $_.UpdateCount, $_.Start, $_.Deadline })
    $message = ('Create {0} software update groups and {0} deployments on site {1} (provider {2})?' -f $preview.Count, $script:Plan.SiteCode, $global:Prefs.SMSProvider) +
        [Environment]::NewLine + [Environment]::NewLine + ($lines -join [Environment]::NewLine) +
        [Environment]::NewLine + [Environment]::NewLine +
        ('This changes the site. To undo, delete the deployments and the software update groups whose name holds the plan ID {0}. Update Planner never edits or deletes an existing deployment or group.' -f $script:Plan.PlanId)
    if (-not (Show-ConfirmDialog -Title 'Create Deployments' -Message $message -Owner $window)) {
        Add-LogLine 'Deploy cancelled.'
        return
    }
    Add-LogLine ('Deploy plan {0}: {1} deployments.' -f $script:Plan.PlanId, $preview.Count)
    Start-BackgroundWork -Title 'Creating Deployments' -Step 'Creating the deployments...' -Arguments @{ Plan = $script:Plan; Provider = [string]$global:Prefs.SMSProvider } -Work {
        param($A, $S)
        @(Invoke-UpdatePlan -Plan $A.Plan -ComputerName $A.Provider -Apply -Confirm:$false)
    } -OnDone {
        param($r)
        Show-DeployResult -Action 'Apply' -Results $r
    }
})

# === Options dialog ===
function Show-OptionsDialog {
    $dlgXaml = @'
<Controls:MetroWindow
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    xmlns:Controls="clr-namespace:MahApps.Metro.Controls;assembly=MahApps.Metro"
    Title="Options" Width="640" Height="400"
    MinWidth="560" MinHeight="380"
    WindowStartupLocation="CenterOwner" TitleCharacterCasing="Normal"
    GlowBrush="{DynamicResource MahApps.Brushes.Accent}"
    NonActiveGlowBrush="{DynamicResource MahApps.Brushes.Accent}"
    BorderThickness="1" ShowIconOnTitleBar="False">
    <Window.Resources>
        <ResourceDictionary>
            <ResourceDictionary.MergedDictionaries>
                <ResourceDictionary Source="pack://application:,,,/MahApps.Metro;component/Styles/Controls.xaml" />
                <ResourceDictionary Source="pack://application:,,,/MahApps.Metro;component/Styles/Fonts.xaml" />
                <ResourceDictionary Source="pack://application:,,,/MahApps.Metro;component/Styles/Themes/Dark.Steel.xaml" />
            </ResourceDictionary.MergedDictionaries>
            <!-- Contrast overrides, the same as in MainWindow.xaml. -->
            <SolidColorBrush x:Key="MahApps.Brushes.TextBox.Border" Color="#7F7F7F"/>
            <SolidColorBrush x:Key="MahApps.Brushes.WindowTitle.NonActive" Color="#595959"/>
            <!-- The one button template and the one button style, the same as in MainWindow.xaml. No color literal:
                 the colors come from the MahApps theme resources. -->
            <ControlTemplate x:Key="ThemedButtonTemplate" TargetType="Button">
                <Border Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}"
                        BorderThickness="{TemplateBinding BorderThickness}" SnapsToDevicePixels="True">
                    <ContentPresenter Name="Cp"
                                      HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}"
                                      VerticalAlignment="{TemplateBinding VerticalContentAlignment}"
                                      Margin="{TemplateBinding Padding}"
                                      RecognizesAccessKey="True"
                                      SnapsToDevicePixels="True"/>
                </Border>
                <ControlTemplate.Triggers>
                    <Trigger Property="IsMouseOver" Value="True">
                        <Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource MahApps.Brushes.ThemeForeground}"/>
                    </Trigger>
                    <Trigger Property="IsKeyboardFocused" Value="True">
                        <Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource MahApps.Brushes.ThemeForeground}"/>
                    </Trigger>
                    <Trigger Property="IsPressed" Value="True">
                        <Setter TargetName="Bd" Property="Background" Value="{DynamicResource MahApps.Brushes.ThemeForeground}"/>
                        <Setter TargetName="Cp" Property="TextElement.Foreground" Value="{DynamicResource MahApps.Brushes.ThemeBackground}"/>
                    </Trigger>
                </ControlTemplate.Triggers>
            </ControlTemplate>
            <Style x:Key="ThemedButtonStyle" TargetType="Button" BasedOn="{StaticResource MahApps.Styles.Button.Square}">
                <Setter Property="Template" Value="{StaticResource ThemedButtonTemplate}"/>
                <Setter Property="Foreground" Value="{DynamicResource MahApps.Brushes.ThemeForeground}"/>
                <Setter Property="BorderThickness" Value="1"/>
                <Setter Property="HorizontalContentAlignment" Value="Center"/>
                <Setter Property="VerticalContentAlignment" Value="Center"/>
                <Setter Property="Controls:ControlsHelper.ContentCharacterCasing" Value="Normal"/>
                <Style.Triggers>
                    <Trigger Property="IsEnabled" Value="False">
                        <Setter Property="Foreground" Value="{DynamicResource MahApps.Brushes.Gray.MouseOver}"/>
                        <Setter Property="BorderBrush" Value="{DynamicResource MahApps.Brushes.Gray2}"/>
                    </Trigger>
                </Style.Triggers>
            </Style>
            <Style x:Key="CategoryRowStyle" TargetType="Button" BasedOn="{StaticResource ThemedButtonStyle}">
                <Setter Property="Height" Value="36"/>
                <Setter Property="HorizontalContentAlignment" Value="Left"/>
                <Setter Property="Padding" Value="14,0,14,0"/>
                <Setter Property="FontSize" Value="13"/>
                <Setter Property="Margin" Value="0"/>
            </Style>
            <!-- The one secondary dialog style: a gray fill, the theme text color and a visible border. Cancel uses it.
                 The primary dialog style is DialogAccentButton. No other dialog button style sets a Background. -->
            <Style x:Key="DialogButton" TargetType="Button" BasedOn="{StaticResource ThemedButtonStyle}">
                <Setter Property="Background" Value="{DynamicResource MahApps.Brushes.Gray10}"/>
                <Setter Property="Foreground" Value="{DynamicResource MahApps.Brushes.ThemeForeground}"/>
                <Setter Property="BorderBrush" Value="{DynamicResource MahApps.Brushes.ThemeForeground}"/>
                <Setter Property="MinWidth" Value="90"/><Setter Property="Height" Value="32"/>
                <Setter Property="Margin" Value="0,0,8,0"/>
            </Style>
            <!-- The accent fill is the theme highlight (#4A5763 dark, #00589F light): white text is 7:1 on both.
                 The border is the theme foreground: the highlight alone is 2.1:1 on the dark dialog.
                 The plain accent fill of the light theme is 4.49:1. -->
            <Style x:Key="DialogAccentButton" TargetType="Button" BasedOn="{StaticResource ThemedButtonStyle}">
                <Setter Property="Background" Value="{DynamicResource MahApps.Brushes.Highlight}"/>
                <Setter Property="BorderBrush" Value="{DynamicResource MahApps.Brushes.ThemeForeground}"/>
                <Setter Property="Foreground" Value="{DynamicResource MahApps.Brushes.IdealForeground}"/>
                <Setter Property="MinWidth" Value="90"/><Setter Property="Height" Value="32"/>
                <Setter Property="Margin" Value="0,0,8,0"/>
                <Style.Triggers>
                    <Trigger Property="IsEnabled" Value="False">
                        <Setter Property="Background" Value="{DynamicResource MahApps.Brushes.ThemeBackground}"/>
                        <Setter Property="Foreground" Value="{DynamicResource MahApps.Brushes.Gray.MouseOver}"/>
                        <Setter Property="BorderBrush" Value="{DynamicResource MahApps.Brushes.Gray2}"/>
                    </Trigger>
                </Style.Triggers>
            </Style>
            <Style x:Key="OptLabel" TargetType="TextBlock">
                <Setter Property="FontSize" Value="11"/>
                <Setter Property="FontWeight" Value="Bold"/>
                <Setter Property="Foreground" Value="{DynamicResource MahApps.Brushes.Gray1}"/>
                <Setter Property="Margin" Value="0,12,0,2"/>
            </Style>
        </ResourceDictionary>
    </Window.Resources>
    <Grid>
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="180"/>
            <ColumnDefinition Width="1"/>
            <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>
        <Grid.RowDefinitions>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <Border Grid.Column="0" Grid.Row="0" Padding="6,12,0,12">
            <StackPanel>
                <Button x:Name="btnCatConnection" Content="Connection" Style="{StaticResource CategoryRowStyle}"/>
                <Button x:Name="btnCatAbout"      Content="About"      Style="{StaticResource CategoryRowStyle}"/>
            </StackPanel>
        </Border>
        <Border Grid.Column="1" Grid.Row="0" Background="{DynamicResource MahApps.Brushes.Gray8}"/>
        <Grid Grid.Column="2" Grid.Row="0" Margin="20,16,20,16">
            <StackPanel x:Name="paneConnection" Visibility="Visible">
                <TextBlock Text="Configuration Manager Connection" FontSize="13" FontWeight="Bold" Margin="0,0,0,10"/>
                <TextBlock Style="{StaticResource OptLabel}" FontSize="14" FontWeight="Bold" Margin="0,4,0,2" Text="SMS Provider FQDN"/>
                <TextBox x:Name="txtSmsProvider" FontSize="12" Padding="6,4,6,4"
                         Controls:TextBoxHelper.Watermark="e.g. sms01.example.com"/>
                <TextBlock Style="{StaticResource OptLabel}" FontSize="14" FontWeight="Bold" Text="Site Code"/>
                <TextBox x:Name="txtSiteCode" FontSize="12" Padding="6,4,6,4"
                         Controls:TextBoxHelper.Watermark="e.g. ABC. Three letters or digits." Width="240" HorizontalAlignment="Left"/>
                <TextBlock Text="The tool connects with the Windows account that runs it and stores no password. The tool needs the Configuration Manager console on this computer. A domain admin account that is a local administrator of the SMS Provider computer needs no Configuration Manager role. An account with fewer rights is not tested."
                           FontSize="11" TextWrapping="Wrap" Margin="0,16,0,0"
                           Foreground="{DynamicResource MahApps.Brushes.Gray1}"/>
            </StackPanel>
            <StackPanel x:Name="paneAbout" Visibility="Collapsed">
                <TextBlock Text="About" FontSize="13" FontWeight="Bold" Margin="0,0,0,10"/>
                <TextBlock x:Name="txtAboutVersion" Text="Update Planner v0.0.0" FontSize="13" FontWeight="Bold"/>
                <TextBlock Text="Plan software update rollouts for a Configuration Manager site: which updates go to which collection, in which wave, on which dates. Build the plan, review it as a grid or a report, export it, and create the deployments only when you choose to."
                           FontSize="12" TextWrapping="Wrap" Margin="0,8,0,0"/>
                <TextBlock Text="Author: Jason Ulbright. License: MIT."
                           FontSize="11" Margin="0,16,0,0" Foreground="{DynamicResource MahApps.Brushes.Gray1}"/>
            </StackPanel>
        </Grid>
        <Border Grid.Row="1" Grid.ColumnSpan="3" Padding="16,12,16,12">
            <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
                <Button x:Name="btnOk"     Content="OK"     Style="{StaticResource DialogAccentButton}" IsDefault="True"/>
                <Button x:Name="btnCancel" Content="Cancel" Style="{StaticResource DialogButton}"        IsCancel="True"/>
            </StackPanel>
        </Border>
    </Grid>
</Controls:MetroWindow>
'@
    [xml]$dx = $dlgXaml
    $reader2 = New-Object System.Xml.XmlNodeReader $dx
    $dlg = [System.Windows.Markup.XamlReader]::Load($reader2)
    $dlg.Owner = $window
    Install-TitleBarDragFallback -Window $dlg
    Set-DialogTheme -Dialog $dlg
    $btnCatConnection = $dlg.FindName('btnCatConnection')
    $btnCatAbout      = $dlg.FindName('btnCatAbout')
    $paneConnection   = $dlg.FindName('paneConnection')
    $paneAbout        = $dlg.FindName('paneAbout')
    $txtAboutVersion  = $dlg.FindName('txtAboutVersion')
    if ($txtAboutVersion) { $txtAboutVersion.Text = ($txtAboutVersion.Text -replace 'v[0-9][0-9\.]*[0-9]\s*$', ('v' + $script:AppVersion)) }
    $txtSiteCode    = $dlg.FindName('txtSiteCode')
    $txtSmsProvider = $dlg.FindName('txtSmsProvider')
    $btnOk          = $dlg.FindName('btnOk')
    $btnCancel      = $dlg.FindName('btnCancel')
    $txtSiteCode.Text    = [string]$global:Prefs.SiteCode
    $txtSmsProvider.Text = [string]$global:Prefs.SMSProvider
    $btnCatConnection.Add_Click({ $paneConnection.Visibility = [System.Windows.Visibility]::Visible; $paneAbout.Visibility = [System.Windows.Visibility]::Collapsed })
    $btnCatAbout.Add_Click({      $paneConnection.Visibility = [System.Windows.Visibility]::Collapsed; $paneAbout.Visibility = [System.Windows.Visibility]::Visible })
    $btnOk.Add_Click({
        $newSite     = ([string]$txtSiteCode.Text).Trim()
        $newProvider = ([string]$txtSmsProvider.Text).Trim()
        if ($newSite -and $newSite -notmatch '^[A-Za-z0-9]{3}$') {
            [void](Show-ThemedMessage -Owner $dlg -Title 'Update Planner' -Message 'The site code is three letters or digits.' -Icon Warn)
            return
        }
        if ($newProvider -and $newProvider -notmatch '^[A-Za-z0-9_.-]{1,255}$') {
            [void](Show-ThemedMessage -Owner $dlg -Title 'Update Planner' -Message 'The SMS Provider is a computer name or an FQDN.' -Icon Warn)
            return
        }
        $changed = ($newSite -ne [string]$global:Prefs.SiteCode) -or ($newProvider -ne [string]$global:Prefs.SMSProvider)
        $global:Prefs.SiteCode    = $newSite
        $global:Prefs.SMSProvider = $newProvider
        Save-UpPreferences -Prefs $global:Prefs
        if ($changed) {
            $script:CollectionData = $null
            $script:Plan = $null
            $gridPlan.ItemsSource = $null; $gridSkipped.ItemsSource = $null; $gridPreview.ItemsSource = $null; $gridResults.ItemsSource = $null
            $txtTabSkipped.Text = 'Skipped Updates'
            $txtPlanSummary.Text = 'No plan yet.'
            Update-ReportText
            Update-ControlState
        }
        $dlg.DialogResult = $true; $dlg.Close()
    })
    $btnCancel.Add_Click({ $dlg.DialogResult = $false; $dlg.Close() })
    [void]$dlg.ShowDialog()
    Update-StatusBarSummary
}
$btnOptions.Add_Click({ Show-OptionsDialog })

# === Window state (geometry logic: SuiteCommon) ===
$global:WindowStatePath = Join-Path $PSScriptRoot 'UpdatePlanner.windowstate.json'

$window.Add_Closing({
    Save-SettingsToPrefs
    Save-WindowState -Window $window -Path $global:WindowStatePath -ExtraState @{ ActiveView = $script:ActiveView }
    Stop-BackgroundWork
    Close-SuiteBgRunspace -Runspace $script:BgRunspace
})

$window.Add_Loaded({
    Restore-WindowState -Window $window -Path $global:WindowStatePath -OnStateLoaded {
        param($s)
        if ($s.ActiveView -in @('Plan', 'Report', 'Deploy')) { Set-ActiveView -View ([string]$s.ActiveView) }
    }
    $isDark = [bool]$global:Prefs['DarkMode']
    if (-not $isDark) { [void][ControlzEx.Theming.ThemeManager]::Current.ChangeTheme($window, 'Light.Blue') }
    Update-TitleBarBrushes
    Update-WaveList
    Update-ReportText
    Update-ControlState
    Update-StatusBarSummary
    Add-LogLine 'Update Planner ready. Set the SMS Provider in Options, add the wave collections, then click Build Plan.'
})

# Suite update notice: one shared daily lookup across the suite tools; the launcher installs.
$null = Start-SuiteUpdateNotice -Path $PSScriptRoot -OnResult { param($u) if ($u.Available) { Add-LogLine ('Suite update available: v{0}. Update from the AppPackager Suite Launcher.' -f $u.Latest) } }
[void]$window.ShowDialog()
try { Stop-Transcript | Out-Null } catch { $null = $_ }
