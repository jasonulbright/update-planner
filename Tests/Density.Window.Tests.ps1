#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.1.0' }

<#
.SYNOPSIS
    Pester 5.x window test for the compact 1080p density and for vacant space. The main window is opened off screen, in both
    themes, at the work area of the session (1920x1032 on a 1080p screen at 100 percent) and at 1024x720, and measured:
    sidebar buttons, inline buttons, single-line inputs, grid rows and headers, the width that the content uses, and the
    vacant area of every view (the free width at the right and the free height at the bottom of the last content element).
    The visible run prints the work area of the session (SystemParameters.WorkArea).
#>

BeforeDiscovery {
    . "$PSScriptRoot\WindowHarness.ps1"
    $script:WindowGuard = Test-WindowTestsAllowed
    if (-not $script:WindowGuard.Allowed -and -not $env:SUITE_WINDOW_GUARD_REPORTED) { Write-Host ('Window tests skipped: {0}.' -f $script:WindowGuard.Reason) }
    $script:Cases = @(foreach ($dark in $true, $false) {
            $design = Get-DesignSize
            foreach ($size in @(@(1024, 720), @($design.W, $design.H))) {
                @{ Dark = $dark; Theme = $(if ($dark) { 'dark' } else { 'light' }); W = $size[0]; H = $size[1]; Size = ('{0}x{1}' -f $size[0], $size[1]); IsDesign = ($size[0] -ne 1024) }
            }
        })
}

BeforeAll {
    . "$PSScriptRoot\WindowHarness.ps1"
    $script:WindowGuard = Test-WindowTestsAllowed
    if (-not $script:WindowGuard.Allowed) { return }
    . "$PSScriptRoot\WindowConfig.ps1"
    $script:Design = Get-DesignSize
    Add-Type -AssemblyName PresentationFramework
    $wa = [System.Windows.SystemParameters]::WorkArea
    Write-Host ('Work area of this session: {0}x{1}' -f $wa.Width, $wa.Height)
    $sample = New-WindowSampleData
    $script:Measured = @{}
    foreach ($case in @(
            @{ Dark = $true; W = 1024; H = 720 }, @{ Dark = $true; W = $script:Design.W; H = $script:Design.H },
            @{ Dark = $false; W = 1024; H = 720 }, @{ Dark = $false; W = $script:Design.W; H = $script:Design.H })) {
        $key = '{0}|{1}x{2}' -f $(if ($case.Dark) { 'dark' } else { 'light' }), $case.W, $case.H
        $case.Config = $script:AppConfig
        $case.Sample = $sample
        $script:Measured[$key] = Invoke-WpfSta -Arguments $case -Script {
            $dsCfg = $Arguments.Config
            $dsS = $Arguments.Sample
            $dsW = $null
            try {
                $dsW = Open-TestWindow -XamlPath (Join-Path $Root $dsCfg.Xaml) -Dark $Arguments.Dark -Width $Arguments.W -Height $Arguments.H
                $dsW.FindName('gridPlan').ItemsSource = @($dsS.Plan)
                $dsW.FindName('gridSkipped').ItemsSource = @($dsS.Skipped)
                $dsW.FindName('gridPreview').ItemsSource = @($dsS.Preview)
                $dsW.FindName('gridResults').ItemsSource = @($dsS.Results)
                $dsW.FindName('lstWaves').ItemsSource = @($dsS.Waves)
                $dsW.FindName('txtReport').Text = [string]$dsS.Report
                Wait-Layout $dsW
                $dsSidebar = @(foreach ($dsB in @($dsCfg.Views | ForEach-Object { $dsW.FindName($_.Button) }) + @($dsW.FindName($dsCfg.OptionsButton))) {
                        $dsP = $dsB.TransformToAncestor($dsW).Transform([System.Windows.Point]::new(0, 0))
                        [pscustomobject]@{ Name = $dsB.Name; Bottom = $dsP.Y + $dsB.ActualHeight; Height = $dsB.ActualHeight }
                    })
                $dsViews = @(foreach ($dsView in $dsCfg.Views) {
                        foreach ($dsV in $dsCfg.Views) { $dsW.FindName($dsV.Container).Visibility = if ($dsV.Name -eq $dsView.Name) { 'Visible' } else { 'Collapsed' } }
                        Wait-Layout $dsW
                        $dsC = $dsW.FindName($dsView.Container)
                        $dsAll = @(Get-VisualDescendants $dsC)
                        $dsInline = @(foreach ($dsEl in $dsAll) { if ($dsEl -is [System.Windows.Controls.Button] -and (Test-VisibleInTree $dsEl) -and $dsEl.Name) { [pscustomobject]@{ Name = $dsEl.Name; Height = $dsEl.ActualHeight } } })
                        $dsBoxes = @(foreach ($dsEl in $dsAll) { if (($dsEl -is [System.Windows.Controls.TextBox] -or $dsEl -is [System.Windows.Controls.ComboBox] -or $dsEl -is [System.Windows.Controls.DatePicker]) -and $dsEl.Name -in 'txtSpacing', 'txtDeadline', 'txtMaxUpdates', 'cboSeverity', 'dpStartDate' -and (Test-VisibleInTree $dsEl)) { [pscustomobject]@{ Name = $dsEl.Name; Height = $dsEl.ActualHeight } } })
                        $dsGrids = @(foreach ($dsEl in $dsAll) {
                                if ($dsEl -is [System.Windows.Controls.DataGrid] -and (Test-VisibleInTree $dsEl)) {
                                    $dsHdr = $null; foreach ($dsX in (Get-VisualDescendants $dsEl)) { if ($dsX -is [System.Windows.Controls.Primitives.DataGridColumnHeadersPresenter]) { $dsHdr = $dsX; break } }
                                    $dsRow = $null; foreach ($dsX in (Get-VisualDescendants $dsEl)) { if ($dsX -is [System.Windows.Controls.DataGridRow]) { $dsRow = $dsX; break } }
                                    [pscustomobject]@{ Name = $dsEl.Name; Width = $dsEl.ActualWidth; Height = $dsEl.ActualHeight; HeaderHeight = $(if ($dsHdr) { $dsHdr.ActualHeight } else { $null }); RowHeight = $(if ($dsRow) { $dsRow.ActualHeight } else { $null }) }
                                }
                            })
                        # Vacant space: the right and bottom edge of the last element that has content or a background, against the view.
                        $dsRight = 0.0; $dsBottom = 0.0
                        foreach ($dsEl in $dsAll) {
                            if ($dsEl -isnot [System.Windows.FrameworkElement] -or $dsEl.ActualWidth -le 0 -or $dsEl.ActualHeight -le 0 -or -not (Test-VisibleInTree $dsEl)) { continue }
                            $dsHas = ($dsEl -is [System.Windows.Controls.Control] -and $dsEl -isnot [System.Windows.Controls.ScrollViewer]) -or
                            ($dsEl -is [System.Windows.Controls.TextBlock] -and -not [string]::IsNullOrWhiteSpace($dsEl.Text)) -or
                            (($dsEl -is [System.Windows.Controls.Border] -or $dsEl -is [System.Windows.Controls.Panel]) -and $dsEl.Background -is [System.Windows.Media.SolidColorBrush] -and $dsEl.Background.Color.A -gt 0)
                            if (-not $dsHas) { continue }
                            $dsP = $dsEl.TransformToAncestor($dsC).Transform([System.Windows.Point]::new(0, 0))
                            $dsRight = [Math]::Max($dsRight, $dsP.X + $dsEl.ActualWidth); $dsBottom = [Math]::Max($dsBottom, $dsP.Y + $dsEl.ActualHeight)
                        }
                        [pscustomobject]@{ View = $dsView.Name; Width = $dsC.ActualWidth; Height = $dsC.ActualHeight; VacantWidth = [Math]::Max(0, $dsC.ActualWidth - $dsRight); VacantHeight = [Math]::Max(0, $dsC.ActualHeight - $dsBottom); Buttons = $dsInline; Boxes = $dsBoxes; Grids = $dsGrids }
                    })
                [pscustomobject]@{ Width = $dsW.ActualWidth; Height = $dsW.ActualHeight; Sidebar = $dsSidebar; Views = $dsViews }
            }
            finally { if ($dsW) { $dsW.Close() } }
        }
    }
}

AfterAll {
    if ($script:WindowGuard.Allowed) { Close-WpfSession }
}

Describe 'Density <Theme> <Size>' -ForEach $script:Cases -Skip:(-not $script:WindowGuard.Allowed) {
    It 'sizes every sidebar view button between 34 and 36 px and fits all of them without scrolling' {
        $m = $script:Measured['{0}|{1}' -f $Theme, $Size]
        foreach ($b in $m.Sidebar | Where-Object { $_.Name -ne 'btnOptions' }) { $b.Height | Should -BeIn 34, 35, 36 -Because $b.Name }
        ($m.Sidebar | Select-Object -Last 1).Bottom | Should -BeLessThan $m.Height
    }

    It 'sizes the inline buttons and the single-line inputs in the <View> view' -ForEach @(@{ View = 'Plan' }, @{ View = 'Report' }, @{ View = 'Deploy' }) {
        $m = ($script:Measured['{0}|{1}' -f $Theme, $Size].Views | Where-Object View -eq $View)
        foreach ($b in $m.Buttons | Where-Object { $_.Name -notmatch '^btnView|^btnOptions' }) { $b.Height | Should -BeLessOrEqual 28 -Because $b.Name }
        foreach ($b in $m.Boxes) { $b.Height | Should -BeIn 26, 27, 28 -Because $b.Name }
    }

    It 'gives grid rows 24 to 26 px and headers 26 px in the <View> view' -ForEach @(@{ View = 'Plan' }, @{ View = 'Report' }, @{ View = 'Deploy' }) {
        $m = ($script:Measured['{0}|{1}' -f $Theme, $Size].Views | Where-Object View -eq $View)
        foreach ($g in $m.Grids) {
            if ($null -ne $g.HeaderHeight) { $g.HeaderHeight | Should -BeLessOrEqual 26.5 -Because $g.Name }
            if ($null -ne $g.RowHeight) { [math]::Round($g.RowHeight) | Should -BeIn 24, 25, 26 -Because $g.Name }
        }
    }

    It 'lets the content fill the width in the <View> view' -ForEach @(@{ View = 'Plan' }, @{ View = 'Report' }, @{ View = 'Deploy' }) {
        $mm = $script:Measured['{0}|{1}' -f $Theme, $Size]
        $m = $mm.Views | Where-Object View -eq $View
        $m.Width | Should -BeGreaterOrEqual ($mm.Width - 300)
        foreach ($g in $m.Grids) { $g.Width | Should -BeGreaterOrEqual ($m.Width * 0.3) -Because $g.Name }
    }

    It 'leaves no vacant area of more than 120 px in height or 160 px in width in any view' -Skip:(-not $IsDesign) {
        $mm = $script:Measured['{0}|{1}' -f $Theme, $Size]
        $bad = @($mm.Views | Where-Object { $_.VacantHeight -gt 120 -or $_.VacantWidth -gt 160 } | ForEach-Object { '{0}: vacant {1} px wide and {2} px high in a view of {3}x{4}' -f $_.View, [int]$_.VacantWidth, [int]$_.VacantHeight, [int]$_.Width, [int]$_.Height })
        $bad | Should -BeNullOrEmpty -Because ('vacant space at the work area: ' + ($bad -join '; '))
    }
}
