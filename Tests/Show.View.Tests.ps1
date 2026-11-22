#Requires -Modules Pester
[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'The cut-out shell functions read these stand-in controls through scope.')]
[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '', Justification = 'The shell keeps its preferences in globals; the tests set the same names.')]
param ()
# The plan, the skipped updates, the preview, the results and the wave list reach the screen.
# The Build Plan step runs in the background and hands its plan to Show-Plan. These tests run
# Show-Plan, Show-DeployResult and Update-WaveList of the script with a plan that the module
# builds from site data, with real WPF controls (not shown), and read the rows that each grid
# holds and the text that the user sees. A test that checks only that a control exists, or that
# a function was called, passes while a grid is empty.
#
# The script cannot be dot-sourced (it opens the window), so each function is cut out of its
# syntax tree and defined here.

BeforeAll {
    . "$PSScriptRoot\TestHelpers.ps1"
    Import-AppModule
    Add-Type -AssemblyName PresentationFramework
    # WPF controls need an STA thread. Windows PowerShell and PowerShell 7 start in STA; a harness that starts MTA must add -STA.
    if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') { throw 'These tests create WPF controls and need an STA thread. Start the host with -STA.' }
    $script:Ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $script:AppRoot 'start-updateplanner.ps1'), [ref]$null, [ref]$null)

    # A column binds to a property by name. A renamed or missing property leaves the column blank, with no error.
    # The check reads the column bindings of the grid from MainWindow.xaml and looks for each name on the first row.
    [xml]$script:MainXaml = Get-Content -LiteralPath (Join-Path $script:AppRoot 'MainWindow.xaml') -Raw
    $script:MainXamlNs = New-Object System.Xml.XmlNamespaceManager($script:MainXaml.NameTable)
    $script:MainXamlNs.AddNamespace('w', 'http://schemas.microsoft.com/winfx/2006/xaml/presentation')
    $script:MainXamlNs.AddNamespace('x', 'http://schemas.microsoft.com/winfx/2006/xaml')
    function Assert-GridBinding {
        param($Grid, [string]$GridName)
        $node = $script:MainXaml.SelectSingleNode(('//w:DataGrid[@x:Name=''{0}'']' -f $GridName), $script:MainXamlNs)
        if (-not $node) { throw "grid $GridName not found in MainWindow.xaml" }
        $columns = $node.SelectSingleNode('*[contains(local-name(), ''Columns'')]')
        $text = if ($columns) { $columns.OuterXml } else { '' }
        # One {Binding ...} body at a time (one level of nested braces). A binding to the item of another element is not a row property.
        $paths = @($(foreach ($m in [regex]::Matches($text, '\{Binding((?:[^{}]|\{[^{}]*\})*)\}')) {
                $body = $m.Groups[1].Value
                if ($body -match 'RelativeSource|ElementName|Source=') { continue }
                if ($body -match '^\s*(?:Path=)?([A-Za-z_][A-Za-z0-9_]*)\s*(?:[,}]|$)') { $Matches[1] }
                elseif ($body -match 'Path=([A-Za-z_][A-Za-z0-9_]*)') { $Matches[1] }
            }) | Sort-Object -Unique)
        $paths.Count | Should -BeGreaterThan 0 -Because "the grid $GridName has bound columns"
        $Grid.Items.Count | Should -BeGreaterThan 0 -Because "the grid $GridName needs a row to check"
        # WPF binds by exact name, so the match is case-sensitive.
        $names = @($Grid.Items[0].PSObject.Properties.Name)
        foreach ($path in $paths) { ($names -ccontains $path) | Should -BeTrue -Because "a column of $GridName binds to $path" }
    }
    foreach ($n in 'Show-Plan', 'Show-DeployResult', 'Update-WaveList', 'Get-ReportText', 'Update-ReportText', 'Update-ControlState', 'Update-StatusBarSummary') {
        $def = $script:Ast.Find({ param($x) $x -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -eq $n }, $true)
        if (-not $def) { throw "function $n not found in the script" }
        . ([scriptblock]::Create($def.Extent.Text))
    }
    function Add-LogLine { param([string]$Text) $script:LogLines += $Text }
    function Set-StatusText { param([string]$Text) $script:StatusText = $Text }
    function Write-ActionRecord { param($Action, $Results) $script:ActionRecords += $Action }

    # Site data as the background read returns it: three updates (one superseded), two collections.
    $script:SampleState = [pscustomobject]@{
        ComputerName = 'provider.example.test'
        SiteCode     = 'ABC'
        Sync         = [pscustomobject]@{ WsusServerName = 'wsus'; Source = 'Microsoft Update'; LastSuccessfulSyncTime = '2026-11-05 02:02'; LastSyncErrorCode = 0 }
        Wsus         = $null
        Updates      = @(
            [pscustomobject]@{ CIId = 1; ArticleId = '5001'; Title = 'Cumulative update A'; Severity = 10; IsExpired = $false; IsSuperseded = $false; IsDeployed = $false; NumMissing = 3; NumPresent = 0; NumTotal = 4; DateRevised = [datetime]'2026-09-01' }
            [pscustomobject]@{ CIId = 2; ArticleId = '5002'; Title = 'Superseded update B'; Severity = 8; IsExpired = $false; IsSuperseded = $true; IsDeployed = $false; NumMissing = 2; NumPresent = 0; NumTotal = 4; DateRevised = [datetime]'2026-09-01' }
            [pscustomobject]@{ CIId = 3; ArticleId = '5003'; Title = 'Security update C'; Severity = 10; IsExpired = $false; IsSuperseded = $false; IsDeployed = $false; NumMissing = 1; NumPresent = 0; NumTotal = 4; DateRevised = [datetime]'2026-09-01' }
        )
        Collections  = @(
            [pscustomobject]@{ CollectionId = 'ABC00001'; Name = 'Pilot'; MemberCount = 2; MaintenanceWindowCount = 0; MaintenanceWindows = @(); NeededByUpdate = @{ '1' = 1; '2' = 1; '3' = 1 } }
            [pscustomobject]@{ CollectionId = 'ABC00002'; Name = 'Broad'; MemberCount = 9; MaintenanceWindowCount = 0; MaintenanceWindows = @(); NeededByUpdate = @{ '1' = 3; '3' = 2 } }
        )
        Deployments  = @()
        Summary      = [pscustomobject]@{ TotalUpdates = 3; NeededUpdates = 3; InstalledUpdates = 0; SupersededUpdates = 1; ExpiredUpdates = 0; ExistingDeployments = 0 }
    }
    $script:SamplePlan = New-UpdatePlan -State $script:SampleState -StartDate ([datetime]'2026-12-01') -WaveSpacingDays 7 -DeadlineDays 3
}

AfterAll {
    Remove-Variable -Name Prefs -Scope Global -ErrorAction SilentlyContinue
}

Describe 'Show-Plan puts the plan on the screen' {
    BeforeEach {
        $script:LogLines = @(); $script:StatusText = ''; $script:ActionRecords = @()
        $global:Prefs = @{ SiteCode = 'ABC'; SMSProvider = 'provider.example.test' }
        $script:Plan = $null; $script:IsBusy = $false; $script:WaveList = @()
        $gridPlan = New-Object System.Windows.Controls.DataGrid
        $gridSkipped = New-Object System.Windows.Controls.DataGrid
        $gridPreview = New-Object System.Windows.Controls.DataGrid
        $gridResults = New-Object System.Windows.Controls.DataGrid
        $lstWaves = New-Object System.Windows.Controls.ListBox
        $txtTabSkipped = New-Object System.Windows.Controls.TextBlock
        $txtPlanSummary = New-Object System.Windows.Controls.TextBlock
        $txtReport = New-Object System.Windows.Controls.TextBox
        $rdoHtml = [PSCustomObject]@{ IsChecked = $false }
        $toggleActions = [PSCustomObject]@{ IsOn = $false }
        foreach ($b in 'btnBuildPlan', 'btnOptions', 'btnLoadCollections', 'btnAddWave', 'btnExportJson', 'btnExportMarkdown', 'btnExportHtml', 'btnOpenHtml',
            'btnCopyReport', 'btnDryRun', 'btnApply', 'btnRemoveWave', 'btnWaveUp', 'btnWaveDown') { Set-Variable -Name $b -Value ([PSCustomObject]@{ IsEnabled = $false }) }
    }

    It 'has a plan with assignments, a skipped update and two waves to show' {
        @(ConvertTo-UpdatePlanRow -Plan $script:SamplePlan).Count | Should -BeGreaterThan 1
        @(ConvertTo-UpdatePlanSkippedRow -Plan $script:SamplePlan).Count | Should -Be 1
        $script:SamplePlan.Summary.WavesPlanned | Should -Be 2
    }

    It 'fills the plan grid, the skipped grid and the preview grid with the rows of the plan' {
        Show-Plan -Plan $script:SamplePlan
        $gridPlan.Items.Count | Should -Be $script:SamplePlan.Summary.UpdateAssignmentsPlanned
        $gridSkipped.Items.Count | Should -Be 1
        $gridPreview.Items.Count | Should -Be 2
        $gridPlan.Items[0].Wave | Should -Not -BeNullOrEmpty
        $gridPlan.Items[0].Article | Should -Not -BeNullOrEmpty
        @($gridPlan.Items | ForEach-Object Article) | Should -Contain 'KB5001'
        @($gridSkipped.Items | ForEach-Object Article) | Should -Contain 'KB5002'
        @($gridPreview.Items | ForEach-Object Collection) | Should -Contain 'Pilot'
        Assert-GridBinding -Grid $gridPlan -GridName 'gridPlan'
        Assert-GridBinding -Grid $gridSkipped -GridName 'gridSkipped'
        Assert-GridBinding -Grid $gridPreview -GridName 'gridPreview'
    }

    It 'says what the plan holds in the summary text, the skipped tab title and the report' {
        Show-Plan -Plan $script:SamplePlan
        $txtPlanSummary.Text | Should -Match ([regex]::Escape($script:SamplePlan.PlanId))
        $txtPlanSummary.Text | Should -Match '2 waves'
        $txtTabSkipped.Text | Should -Be 'Skipped Updates (1)'
        $txtReport.Text | Should -Match ([regex]::Escape($script:SamplePlan.PlanId))
        $txtReport.Text | Should -Match 'Pilot'
        $script:StatusText | Should -Match ([regex]::Escape($script:SamplePlan.PlanId))
    }

    It 'turns on the export buttons and keeps Dry Run and Deploy off while Enable Actions is off' {
        Show-Plan -Plan $script:SamplePlan
        $btnExportJson.IsEnabled | Should -BeTrue
        $btnExportHtml.IsEnabled | Should -BeTrue
        $btnDryRun.IsEnabled | Should -BeFalse
        $btnApply.IsEnabled | Should -BeFalse
    }

    It 'shows a plan with exactly one assignment and one skipped update as one row each (a single object is not a list)' {
        $oneState = $script:SampleState.PSObject.Copy()
        $oneState.Updates = @($script:SampleState.Updates[0], $script:SampleState.Updates[1])
        $oneState.Collections = @([pscustomobject]@{ CollectionId = 'ABC00001'; Name = 'Pilot'; MemberCount = 2; MaintenanceWindowCount = 0; MaintenanceWindows = @(); NeededByUpdate = @{ '1' = 1; '2' = 1 } })
        $one = New-UpdatePlan -State $oneState -StartDate ([datetime]'2026-12-01') -WaveSpacingDays 7 -DeadlineDays 3
        $one.Summary.UpdateAssignmentsPlanned | Should -Be 1
        @($one.Skipped).Count | Should -Be 1
        { Show-Plan -Plan $one } | Should -Not -Throw
        $gridPlan.Items.Count | Should -Be 1
        $gridSkipped.Items.Count | Should -Be 1
        $gridPreview.Items.Count | Should -Be 1
    }
}

Describe 'Show-DeployResult puts the results on the screen' {
    BeforeEach {
        $script:LogLines = @(); $script:StatusText = ''; $script:ActionRecords = @()
        $gridResults = New-Object System.Windows.Controls.DataGrid
    }

    It 'shows one row for each result, with the status and the message, and counts created and failed in the status text' {
        $results = @(
            [pscustomobject]@{ Status = 'Created'; Wave = 'Pilot'; CollectionId = 'ABC00001'; UpdateCount = 2; AssignmentId = 16777217; Message = 'Created' }
            [pscustomobject]@{ Status = 'Failed'; Wave = 'Broad'; CollectionId = 'ABC00002'; UpdateCount = 2; AssignmentId = $null; Message = 'The site refused the deployment' })
        Show-DeployResult -Action 'Apply' -Results $results
        $gridResults.Items.Count | Should -Be 2
        $gridResults.Items[0].Status | Should -Be 'Created'
        $gridResults.Items[0].Wave | Should -Be 'Pilot'
        $gridResults.Items[1].Status | Should -Be 'Failed'
        $gridResults.Items[1].Message | Should -Be 'The site refused the deployment'
        $script:StatusText | Should -Match '1 created, 1 failed'
        $script:ActionRecords | Should -Contain 'Apply'
        Assert-GridBinding -Grid $gridResults -GridName 'gridResults'
    }

    It 'shows the one result of a one-wave dry run as a Dry run row (the module result for -WhatIf is Skipped)' {
        Show-DeployResult -Action 'DryRun' -Results ([pscustomobject]@{ Status = 'Skipped'; Wave = 'Pilot'; CollectionId = 'ABC00001'; UpdateCount = 2; AssignmentId = $null; Message = 'Not confirmed or WhatIf.' })
        $gridResults.Items.Count | Should -Be 1
        $gridResults.Items[0].Status | Should -Be 'Dry run'
        $gridResults.Items[0].Message | Should -Match 'Nothing was created'
    }
}

Describe 'Update-WaveList puts the wave collections in the list' {
    BeforeEach {
        $script:LogLines = @(); $script:StatusText = ''
        $global:Prefs = @{ SiteCode = 'ABC'; SMSProvider = 'provider.example.test' }
        $script:Plan = $null; $script:IsBusy = $false
        $lstWaves = New-Object System.Windows.Controls.ListBox
        $toggleActions = [PSCustomObject]@{ IsOn = $false }
        foreach ($b in 'btnBuildPlan', 'btnOptions', 'btnLoadCollections', 'btnAddWave', 'btnExportJson', 'btnExportMarkdown', 'btnExportHtml', 'btnOpenHtml',
            'btnCopyReport', 'btnDryRun', 'btnApply', 'btnRemoveWave', 'btnWaveUp', 'btnWaveDown') { Set-Variable -Name $b -Value ([PSCustomObject]@{ IsEnabled = $false }) }
    }

    It 'lists one line for each wave, in order, with the id the user picked' -ForEach @(
        @{ Count = 1 }, @{ Count = 2 }, @{ Count = 5 }
    ) {
        $script:WaveList = @(1..$Count | ForEach-Object { [pscustomobject]@{ Id = 'ABC0000{0}' -f $_; Name = 'Wave {0}' -f $_ } })
        Update-WaveList
        $lstWaves.Items.Count | Should -Be $Count
        @($lstWaves.Items) | Should -Be @(1..$Count | ForEach-Object { '{0}.  Wave {0}   (ABC0000{0})' -f $_ })
        @($global:Prefs['Waves']).Count | Should -Be $Count
    }

    It 'lists nothing for an empty wave list' {
        $script:WaveList = @()
        Update-WaveList
        $lstWaves.Items.Count | Should -Be 0
    }
}
