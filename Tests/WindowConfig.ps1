[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '', Justification = 'The STA runspace keeps the theme state and the message box probe in global variables, which WPF event handlers can read.')]
param()

# App-specific names for Window.Tests.ps1.
# The main window has three view containers. The shell shows one container at a time (Set-ActiveView).
# Each view lists the container, its sidebar button and the active view name the theme uses.
$script:AppConfig = @{
    Title         = 'Update Planner'
    Shell         = 'start-updateplanner.ps1'
    Xaml          = 'MainWindow.xaml'
    OptionsButton = 'btnOptions'
    LogLabel      = 'lblLogOutput'
    Views         = @(
        @{ Name = 'Plan';   Container = 'viewPlan';   Button = 'btnViewPlan' }
        @{ Name = 'Report'; Container = 'viewReport'; Button = 'btnViewReport' }
        @{ Name = 'Deploy'; Container = 'viewApply';  Button = 'btnViewApply' }
    )
    OptionsPanes  = @('paneConnection', 'paneAbout')
}

# Rows of the shape the shell gives to the grids, so the grids show real cell text.
# The module builds them from a small plan, the same way Show-Plan does.
function New-WindowSampleData {
    $root = Split-Path -Parent $PSScriptRoot
    Import-Module -Name (Join-Path $root 'Module\UpdatePlannerCommon.psd1') -Force
    $state = [pscustomobject]@{
        ComputerName = 'provider.example.test'
        SiteCode     = 'ABC'
        Sync         = [pscustomobject]@{ WsusServerName = 'wsus'; Source = 'Microsoft Update'; LastSuccessfulSyncTime = '2026-11-05 02:02'; LastSyncErrorCode = 0 }
        Wsus         = $null
        Updates      = @(
            [pscustomobject]@{ CIId = 1; ArticleId = '5001'; Title = 'Sample cumulative update for the test window'; Severity = 10; IsExpired = $false; IsSuperseded = $false; IsDeployed = $false; NumMissing = 3; NumPresent = 0; NumTotal = 4; DateRevised = [datetime]'2026-09-01' }
            [pscustomobject]@{ CIId = 2; ArticleId = '5002'; Title = 'Sample superseded update'; Severity = 8; IsExpired = $false; IsSuperseded = $true; IsDeployed = $false; NumMissing = 2; NumPresent = 0; NumTotal = 4; DateRevised = [datetime]'2026-09-01' }
        )
        Collections  = @(
            [pscustomobject]@{ CollectionId = 'ABC00001'; Name = 'Pilot'; MemberCount = 2; MaintenanceWindowCount = 0; MaintenanceWindows = @(); NeededByUpdate = @{ '1' = 1; '2' = 1 } }
            [pscustomobject]@{ CollectionId = 'ABC00002'; Name = 'Broad'; MemberCount = 9; MaintenanceWindowCount = 0; MaintenanceWindows = @(); NeededByUpdate = @{ '1' = 3 } }
        )
        Deployments  = @()
        Summary      = [pscustomobject]@{ TotalUpdates = 2; NeededUpdates = 2; InstalledUpdates = 0; SupersededUpdates = 1; ExpiredUpdates = 0; ExistingDeployments = 0 }
    }
    $plan = New-UpdatePlan -State $state -StartDate ([datetime]'2026-12-01') -WaveSpacingDays 7 -DeadlineDays 3
    $results = @([pscustomobject]@{ Status = 'Created'; Wave = 'Wave 1'; CollectionId = 'ABC00001'; UpdateCount = 1; AssignmentId = '16777217'; Message = 'Sample result row' })
    @{
        Plan     = @(ConvertTo-UpdatePlanRow -Plan $plan)
        Skipped  = @(ConvertTo-UpdatePlanSkippedRow -Plan $plan)
        Preview  = @(Get-UpdatePlanDeploymentPreview -Plan $plan)
        Results  = $results
        Report   = (ConvertTo-UpdatePlanMarkdown -Plan $plan)
        Waves    = @('1.  Pilot   (ABC00001)', '2.  Broad   (ABC00002)')
        Summary  = 'Plan sample for site ABC. 2 waves.'
    }
}

# Runs in the STA runspace. Opens the main window and measures every view in one theme and size.
# Arguments: Config, Dark, W, H, Sample, Brushes.
$script:MainMeasureScript = {
    $cfg = $Arguments.Config
    $s = $Arguments.Sample
    $w = Open-TestWindow -XamlPath (Join-Path $Root $cfg.Xaml) -Dark $Arguments.Dark -Width $Arguments.W -Height $Arguments.H
    $w.FindName('gridPlan').ItemsSource = @($s.Plan)
    $w.FindName('gridSkipped').ItemsSource = @($s.Skipped)
    $w.FindName('gridPreview').ItemsSource = @($s.Preview)
    $w.FindName('gridResults').ItemsSource = @($s.Results)
    $w.FindName('lstWaves').ItemsSource = @($s.Waves)
    $w.FindName('txtReport').Text = [string]$s.Report
    $w.FindName('txtPlanSummary').Text = [string]$s.Summary
    $w.FindName('txtLog').Text = '10:00:00  Update Planner ready.'
    $w.FindName('txtVersion').Text = 'v2026.11.07.0004'
    # Contrast is read only at 1440x900. Clipped text and off-screen controls are read at both sizes.
    $full = $Arguments.W -ge 1440
    $out = @()
    foreach ($view in $cfg.Views) {
        foreach ($v in $cfg.Views) { $w.FindName($v.Container).Visibility = if ($v.Name -eq $view.Name) { 'Visible' } else { 'Collapsed' } }
        Initialize-ShellTheme -Window $w -Dark $Arguments.Dark -Views $cfg.Views `
            -OptionsButtonName $cfg.OptionsButton -LogLabelName $cfg.LogLabel -ActiveView $view.Name -BrushColors $Arguments.Brushes
        $out += [PSCustomObject]@{
            View        = $view.Name
            Text        = if ($full) { @(Get-TextContrast $w) } else { @() }
            Clipped     = @(Get-ClippedText $w)
            Offscreen   = @(Get-OffscreenControls $w)
            Interactive = if ($full) { @(Get-InteractiveContrast $w) } else { @() }
            TitleBar    = if ($full) { Get-TitleBarContrast $w } else { $null }
        }
    }
    $w.Close()
    , $out
}

# Runs in the STA runspace. Opens the Options dialog from its XAML text at its declared and minimum size and
# measures every pane. Arguments: Xaml, Dark, Panes, Brushes.
$script:DialogMeasureScript = {
    [xml]$x = $Arguments.Xaml
    $probe = [System.Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $x))
    $sizes = @(, @($probe.Width, $probe.Height))
    if ($probe.MinWidth -gt 0 -and $probe.MinHeight -gt 0) { $sizes += , @($probe.MinWidth, $probe.MinHeight) }
    $probe = $null
    $panes = @($Arguments.Panes)
    $rows = foreach ($size in $sizes) {
        $w = Open-TestWindow -XamlText $Arguments.Xaml -Dark $Arguments.Dark -Width $size[0] -Height $size[1]
        # Entered text, so the contrast of the input text is measured too. The shell fills the version.
        $w.FindName('txtSiteCode').Text = 'ABC'
        $w.FindName('txtSmsProvider').Text = 'provider.example.test'
        $w.FindName('txtAboutVersion').Text = 'Update Planner v2026.11.07.0004'
        # The shell themes the dialog with Set-DialogTheme, which reads the palette of Initialize-SuiteTheme.
        $global:HarnessDark = $Arguments.Dark
        Initialize-SuiteTheme -Window $w -IsDarkGetter { [bool]$global:HarnessDark } -Brushes (ConvertTo-BrushTable $Arguments.Brushes)
        Set-DialogTheme -Dialog $w -IsDark $Arguments.Dark
        foreach ($pane in $panes) {
            foreach ($p in $panes) { $w.FindName($p).Visibility = if ($p -eq $pane) { 'Visible' } else { 'Collapsed' } }
            Wait-Layout $w
            [PSCustomObject]@{
                Pane = $pane; Size = ('{0}x{1}' -f $size[0], $size[1])
                Text = @(Get-TextContrast $w); Interactive = @(Get-InteractiveContrast $w)
                Clipped = @(Get-ClippedText $w); Offscreen = @(Get-OffscreenControls $w)
                Overflow = @(Get-PaneOverflow $w $panes)
                TitleBar = Get-TitleBarContrast $w
            }
        }
        $w.Close()
    }
    , @($rows)
}

# Runs in the STA runspace. Shows the owner window on screen, opens a SuiteCommon message box on it
# the way the shell does, and reads the title and the position of the message box when it has loaded.
# Arguments: Kind ('Main' or 'Options'), XamlPath or XamlText, Title, Dark, Brushes.
$script:MessageProbeScript = {
    if (-not $global:MessageProbeHooked) {
        # One class handler for the life of the runspace. It acts only while a probe is armed.
        [System.Windows.EventManager]::RegisterClassHandler([System.Windows.Window], [System.Windows.FrameworkElement]::LoadedEvent, [System.Windows.RoutedEventHandler] {
                param($source, $e)
                if (-not $global:MessageProbeArmed -or $source -eq $global:MessageProbeOwner) { return }
                $global:MessageProbeArmed = $false
                $global:MessageProbeWindow = $source
                [void]$source.Dispatcher.BeginInvoke([action] {
                        $m = $global:MessageProbeWindow
                        $global:MessageProbeResult = [PSCustomObject]@{
                            Title = $m.Title; OwnerTitle = $m.Owner.Title
                            Left = $m.Left; Top = $m.Top; Width = $m.ActualWidth; Height = $m.ActualHeight
                        }
                        $m.Close()
                    }, [System.Windows.Threading.DispatcherPriority]::ContextIdle)
            })
        $global:MessageProbeHooked = $true
    }
    $owner = if ($Arguments.Kind -eq 'Main') {
        Open-TestWindow -XamlPath $Arguments.XamlPath -Dark $Arguments.Dark -Width 1024 -Height 640 -Left 0 -Top 0
    }
    else {
        Open-TestWindow -XamlText $Arguments.XamlText -Dark $Arguments.Dark -Width 640 -Height 400 -Left 160 -Top 90
    }
    $global:HarnessDark = $Arguments.Dark
    Initialize-SuiteTheme -Window $owner -IsDarkGetter { [bool]$global:HarnessDark } -Brushes (ConvertTo-BrushTable $Arguments.Brushes)
    Wait-Layout $owner
    $global:MessageProbeOwner = $owner
    $global:MessageProbeResult = $null
    $global:MessageProbeArmed = $true
    try { [void](Show-ThemedMessage -Owner $owner -Title $Arguments.Title -Message 'The site code is three letters or digits.' -Icon Warn) }
    finally { $global:MessageProbeArmed = $false }
    $r = $global:MessageProbeResult
    $o = [PSCustomObject]@{
        OwnerTitle = $owner.Title; OwnerLeft = $owner.Left; OwnerTop = $owner.Top; OwnerWidth = $owner.ActualWidth; OwnerHeight = $owner.ActualHeight
        Shown = [bool]$r
        Title = if ($r) { $r.Title } else { $null }
        BoxOwnerTitle = if ($r) { $r.OwnerTitle } else { $null }
        Left = if ($r) { $r.Left } else { $null }; Top = if ($r) { $r.Top } else { $null }
        Width = if ($r) { $r.Width } else { $null }; Height = if ($r) { $r.Height } else { $null }
    }
    $owner.Close()
    $o
}
