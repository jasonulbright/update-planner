#Requires -Modules Pester
# Window tests. The main window and the Options dialog (built from XAML text in the start script)
# are opened off screen on an STA thread, in both themes and at 1024x720 and 1440x900, and measured.
# The message box test shows its owner on screen. The app-specific names live in WindowConfig.ps1.
# The tests that open a window run only with SUITE_ALLOW_WINDOW_TESTS=1 (CI sets it).

BeforeDiscovery {
    . "$PSScriptRoot\WindowHarness.ps1"
    . "$PSScriptRoot\WindowConfig.ps1"
    # No window opens unless this guard allows it (the opt-in must be set). The skipped tests report the reason.
    $script:WindowGuard = Test-WindowTestsAllowed
    if (-not $script:WindowGuard.Allowed) { Write-Host ('Window tests skipped: {0}' -f $script:WindowGuard.Reason) }
    $script:Matrix = foreach ($dark in $true, $false) {
        foreach ($size in @(@(1024, 720), @(1440, 900))) {
            @{ Dark = $dark; Theme = $(if ($dark) { 'dark' } else { 'light' }); W = $size[0]; H = $size[1]; Size = ('{0}x{1}' -f $size[0], $size[1]) }
        }
    }
    $script:ViewCases = @($script:AppConfig.Views | ForEach-Object { @{ View = $_.Name } })
    $script:PaneCases = @($script:AppConfig.OptionsPanes | ForEach-Object { @{ Pane = $_ } })
}

BeforeAll {
    . "$PSScriptRoot\WindowHarness.ps1"
    . "$PSScriptRoot\ContrastRules.ps1"
    . "$PSScriptRoot\WindowConfig.ps1"
    $script:Root = Split-Path -Parent $PSScriptRoot
    $script:ShellPath = Join-Path $script:Root $script:AppConfig.Shell
    $script:XamlPath = Join-Path $script:Root $script:AppConfig.Xaml
    $script:XamlText = [System.IO.File]::ReadAllText($script:XamlPath)
    $script:ShellText = [System.IO.File]::ReadAllText($script:ShellPath)
    $script:Brushes = Get-AppSuiteBrushOverride -ShellPath $script:ShellPath

    $ast = [System.Management.Automation.Language.Parser]::ParseFile($script:ShellPath, [ref]$null, [ref]$null)
    $script:ShellAst = $ast
    $script:DialogXaml = @($ast.FindAll({
                param($n)
                $n -is [System.Management.Automation.Language.StringConstantExpressionAst] -and $n.Value -match '^\s*<Controls:MetroWindow'
            }, $true) | ForEach-Object { $_.Value })
    $script:MainTitle = ([xml]$script:XamlText).DocumentElement.Title
    $script:OptionsTitle = ([xml]$script:DialogXaml[0]).DocumentElement.Title

    # Every themed message box and dialog that the start script opens: its owner, its title and its line.
    $script:MessageCalls = @($ast.FindAll({
                param($n)
                $n -is [System.Management.Automation.Language.CommandAst] -and
                $n.GetCommandName() -in 'Show-ThemedMessage', 'Show-ConfirmDialog', 'Show-CollectionPickerDialog'
            }, $true) | ForEach-Object {
            $cmd = $_
            $values = @{}
            for ($i = 0; $i -lt $cmd.CommandElements.Count; $i++) {
                $el = $cmd.CommandElements[$i]
                if ($el -is [System.Management.Automation.Language.CommandParameterAst] -and $i + 1 -lt $cmd.CommandElements.Count) {
                    $values[$el.ParameterName] = $cmd.CommandElements[$i + 1]
                }
            }
            $title = $values['Title']
            [PSCustomObject]@{
                Line  = $cmd.Extent.StartLineNumber
                Owner = if ($values['Owner']) { $values['Owner'].Extent.Text } else { '' }
                Title = if ($title -is [System.Management.Automation.Language.StringConstantExpressionAst]) { $title.Value } elseif ($title) { $title.Extent.Text } else { '' }
                Constant = $title -is [System.Management.Automation.Language.StringConstantExpressionAst]
            }
        })
    $script:OwnerTitles = @{ '$window' = $script:MainTitle; '$dlg' = $script:OptionsTitle }

    $script:Measured = @{}
    $script:DialogMeasured = @{}
    $script:WindowGuard = Test-WindowTestsAllowed
    if ($script:WindowGuard.Allowed) {
        $sample = New-WindowSampleData
        foreach ($case in @(
                @{ Dark = $true; W = 1024; H = 720 }, @{ Dark = $true; W = 1440; H = 900 },
                @{ Dark = $false; W = 1024; H = 720 }, @{ Dark = $false; W = 1440; H = 900 })) {
            $key = '{0}|{1}x{2}' -f $(if ($case.Dark) { 'dark' } else { 'light' }), $case.W, $case.H
            $case.Config = $script:AppConfig
            $case.Sample = $sample
            $case.Brushes = $script:Brushes
            $script:Measured[$key] = Invoke-WpfSta -Arguments $case -Script $script:MainMeasureScript
        }

        # The Options dialog: every pane, in both themes, at the declared size and at the minimum size.
        foreach ($dark in $true, $false) {
            $theme = if ($dark) { 'dark' } else { 'light' }
            $script:DialogMeasured[$theme] = Invoke-WpfSta -Arguments @{ Xaml = $script:DialogXaml[0]; Dark = $dark; Panes = $script:AppConfig.OptionsPanes; Brushes = $script:Brushes } -Script $script:DialogMeasureScript
        }
    }
}

AfterAll { Close-WpfSession }

Describe 'Main window XAML' -Skip:(-not $script:WindowGuard.Allowed) {
    It 'loads as a MetroWindow with the app title and a minimum size that fits 1024x720' {
        $r = Invoke-WpfSta -Arguments @{ Xaml = $script:AppConfig.Xaml } -Script {
            $w = Open-TestWindow -XamlPath (Join-Path $Root $Arguments.Xaml)
            $o = [PSCustomObject]@{ Type = $w.GetType().FullName; Title = $w.Title; MinW = $w.MinWidth; MinH = $w.MinHeight }
            $w.Close(); $o
        }
        $r.Type | Should -Be 'MahApps.Metro.Controls.MetroWindow'
        $r.Title | Should -Be $script:AppConfig.Title
        $r.MinW | Should -BeLessOrEqual 1024
        $r.MinH | Should -BeLessOrEqual 720
    }

    It 'shows the first view and keeps the others hidden' {
        $r = Invoke-WpfSta -Arguments @{ Config = $script:AppConfig } -Script {
            $w = Open-TestWindow -XamlPath (Join-Path $Root $Arguments.Config.Xaml)
            $o = foreach ($v in $Arguments.Config.Views) { [PSCustomObject]@{ Name = $v.Name; Vis = [string]$w.FindName($v.Container).Visibility } }
            $w.Close(); , @($o)
        }
        $first = $script:AppConfig.Views[0].Name
        ($r | Where-Object Name -eq $first).Vis | Should -Be 'Visible'
        @($r | Where-Object { $_.Name -ne $first -and $_.Vis -ne 'Collapsed' }) | Should -BeNullOrEmpty
    }
}

Describe 'Window XAML text' {
    It 'has the container and the sidebar button of view <View>' -ForEach @($script:AppConfig.Views | ForEach-Object { @{ View = $_.Name; Container = $_.Container; Button = $_.Button } }) {
        $script:XamlText | Should -Match ('x:Name="{0}"' -f $Container)
        $script:XamlText | Should -Match ('x:Name="{0}"' -f $Button)
    }

    It 'lists in the configuration every view that the script switches to' {
        $m = [regex]::Match($script:ShellText, "function Set-ActiveView[\s\S]*?ValidateSet\(([^)]*)\)")
        $m.Success | Should -BeTrue
        $views = @([regex]::Matches($m.Groups[1].Value, "'([^']+)'") | ForEach-Object { $_.Groups[1].Value })
        $configured = @($script:AppConfig.Views | ForEach-Object { $_.Name })
        @($views | Where-Object { $configured -notcontains $_ }) | Should -BeNullOrEmpty
        @($configured | Where-Object { $views -notcontains $_ }) | Should -BeNullOrEmpty
    }

    It 'gives every tab a TextBlock header with the TabHeaderText style, so that an unselected tab keeps its contrast' {
        [xml]$x = $script:XamlText
        $ns = New-Object System.Xml.XmlNamespaceManager $x.NameTable
        $ns.AddNamespace('p', 'http://schemas.microsoft.com/winfx/2006/xaml/presentation')
        $tabs = @($x.SelectNodes('//p:TabItem', $ns))
        $tabs.Count | Should -BeGreaterThan 0
        foreach ($t in $tabs) {
            $t.GetAttribute('Header') | Should -BeNullOrEmpty -Because ('tab {0} has a text header' -f $t.GetAttribute('Name', 'http://schemas.microsoft.com/winfx/2006/xaml'))
            $tb = $t.SelectSingleNode('p:TabItem.Header/p:TextBlock', $ns)
            $tb | Should -Not -BeNullOrEmpty
            $tb.GetAttribute('Style') | Should -Be '{StaticResource TabHeaderText}'
        }
    }
}

Describe 'Dialog windows' -Skip:(-not $script:WindowGuard.Allowed) {
    It 'parses the Options dialog as a MetroWindow with named controls' {
        $r = Invoke-WpfSta -Arguments @{ Xaml = $script:DialogXaml[0] } -Script {
            [xml]$x = $Arguments.Xaml
            $w = [System.Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $x))
            $names = [regex]::Matches($Arguments.Xaml, 'x:Name="([^"]+)"') | ForEach-Object { $_.Groups[1].Value }
            [PSCustomObject]@{ Type = $w.GetType().Name; Missing = @($names | Where-Object { -not $w.FindName($_) }); Count = @($names).Count }
        }
        $r.Type | Should -Be 'MetroWindow'
        $r.Missing | Should -BeNullOrEmpty
        $r.Count | Should -BeGreaterThan 0
    }

    It 'shows pane <Pane> of the Options dialog without clipped text, cut-off content or off-screen controls at its declared and minimum size in the <Theme> theme' -ForEach @(
        foreach ($c in $script:PaneCases) { foreach ($t in 'dark', 'light') { @{ Pane = $c.Pane; Theme = $t } } }
    ) {
        $rows = @($script:DialogMeasured[$Theme] | Where-Object Pane -eq $Pane)
        $rows.Count | Should -Be 2 -Because 'the dialog is measured at its declared size and at its minimum size'
        foreach ($m in $rows) {
            $m.Clipped | ForEach-Object { '{0}: {1}: needs {2}px, has {3}px' -f $m.Size, $_.Text, $_.Needed, $_.Actual } | Should -BeNullOrEmpty
            $m.Offscreen | ForEach-Object { '{0}: {1} at {2},{3} size {4}x{5}' -f $m.Size, $_.Name, $_.X, $_.Y, $_.W, $_.H } | Should -BeNullOrEmpty
            $m.Overflow | ForEach-Object { '{0}: {1} needs {2}x{3}, has {4}x{5}' -f $m.Size, $_.Name, $_.NeedW, $_.NeedH, $_.HasW, $_.HasH } | Should -BeNullOrEmpty
        }
    }

    It 'shows every text, control and title bar of the Options dialog at the contrast standard in the <Theme> theme' -ForEach @(@{ Theme = 'dark' }, @{ Theme = 'light' }) {
        $first = ($script:DialogMeasured[$Theme] | Select-Object -First 1).Size
        $views = @($script:DialogMeasured[$Theme] | Where-Object { $_.Size -eq $first })
        @($views | ForEach-Object { $_.Text }).Count | Should -BeGreaterThan 3
        Get-ContrastViolation -Views $views | Should -BeNullOrEmpty
    }
}

Describe 'Message boxes' {
    It 'gives every message box and dialog a title that differs from the title of its owner window' {
        $script:MessageCalls.Count | Should -BeGreaterThan 4
        $bad = foreach ($c in $script:MessageCalls) {
            $ownerTitle = $script:OwnerTitles[$c.Owner]
            if (-not $c.Constant) { 'line {0}: the title is not a fixed text: {1}' -f $c.Line, $c.Title; continue }
            if ($null -eq $ownerTitle) { 'line {0}: unknown owner {1}' -f $c.Line, $c.Owner; continue }
            if ([string]::IsNullOrWhiteSpace($c.Title)) { 'line {0}: empty title' -f $c.Line; continue }
            if ($c.Title -eq $ownerTitle) { 'line {0}: the title "{1}" equals the title of its owner {2}' -f $c.Line, $c.Title, $c.Owner }
        }
        @($bad) | Should -BeNullOrEmpty
    }
}

Describe 'Message box position' -Skip:(-not $script:WindowGuard.Allowed) {
    It 'centers the message box on its owner, the <Kind> window, in the <Theme> theme' -ForEach @(
        foreach ($k in 'Main', 'Options') { foreach ($t in 'dark', 'light') { @{ Kind = $k; Theme = $t } } }
    ) {
        $call = @($script:MessageCalls | Where-Object { $_.Owner -eq $(if ($Kind -eq 'Main') { '$window' } else { '$dlg' }) }) | Select-Object -First 1
        $call | Should -Not -BeNullOrEmpty
        $r = Invoke-WpfSta -Script $script:MessageProbeScript -Arguments @{
            Kind = $Kind; XamlPath = $script:XamlPath; XamlText = $script:DialogXaml[0]; Title = $call.Title
            Dark = ($Theme -eq 'dark'); Brushes = $script:Brushes
        }
        $r = @($r)[-1]
        $r.Shown | Should -BeTrue
        $r.BoxOwnerTitle | Should -Be $r.OwnerTitle
        $r.Title | Should -Not -Be $r.OwnerTitle
        $dx = ($r.Left + $r.Width / 2) - ($r.OwnerLeft + $r.OwnerWidth / 2)
        $dy = ($r.Top + $r.Height / 2) - ($r.OwnerTop + $r.OwnerHeight / 2)
        [math]::Abs($dx) | Should -BeLessOrEqual 2 -Because ('the box is at {0},{1} size {2}x{3}; the owner is at {4},{5} size {6}x{7}' -f $r.Left, $r.Top, $r.Width, $r.Height, $r.OwnerLeft, $r.OwnerTop, $r.OwnerWidth, $r.OwnerHeight)
        [math]::Abs($dy) | Should -BeLessOrEqual 2 -Because ('the box is at {0},{1} size {2}x{3}; the owner is at {4},{5} size {6}x{7}' -f $r.Left, $r.Top, $r.Width, $r.Height, $r.OwnerLeft, $r.OwnerTop, $r.OwnerWidth, $r.OwnerHeight)
    }
}

Describe 'Layout <Theme> <Size>' -ForEach $script:Matrix -Skip:(-not $script:WindowGuard.Allowed) {
    It 'has no clipped text in the <View> view' -ForEach $script:ViewCases {
        $m = ($script:Measured['{0}|{1}' -f $Theme, $Size] | Where-Object View -eq $View)
        $m.Clipped | ForEach-Object { '{0}: needs {1}px, has {2}px' -f $_.Text, $_.Needed, $_.Actual } | Should -BeNullOrEmpty
    }

    It 'keeps every button, box and list inside the window in the <View> view' -ForEach $script:ViewCases {
        $m = ($script:Measured['{0}|{1}' -f $Theme, $Size] | Where-Object View -eq $View)
        $m.Offscreen | ForEach-Object { '{0} at {1},{2} size {3}x{4}' -f $_.Name, $_.X, $_.Y, $_.W, $_.H } | Should -BeNullOrEmpty
    }
}

Describe 'Contrast <Theme>' -ForEach @(@{ Theme = 'dark' }, @{ Theme = 'light' }) -Skip:(-not $script:WindowGuard.Allowed) {
    It 'shows every text and control of the <View> view at the contrast standard, enabled and disabled' -ForEach $script:ViewCases {
        $m = ($script:Measured['{0}|1440x900' -f $Theme] | Where-Object View -eq $View)
        @($m.Text).Count | Should -BeGreaterThan 3
        @($m.Interactive).Count | Should -BeGreaterThan 3
        $copy = [PSCustomObject]@{ View = $m.View; Text = $m.Text; Interactive = $m.Interactive; TitleBar = $null }
        Get-ContrastViolation -Views @($copy) | Should -BeNullOrEmpty
    }

    It 'keeps the title text readable on the active and the inactive title bar' {
        $tb = ($script:Measured['{0}|1440x900' -f $Theme] | Select-Object -First 1).TitleBar
        $tb.Active | Should -BeGreaterOrEqual 4.5
        $tb.Inactive | Should -BeGreaterOrEqual 4.5
    }
}
