#Requires -Modules Pester
[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'The cut-out shell functions read these stand-in controls through scope.')]
[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '', Justification = 'The shell keeps its preferences in globals; the tests set the same names.')]
[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingComputerNameHardcoded', '', Justification = 'Test inputs are fake computer names.')]
param ()
# Logic of start-updateplanner.ps1. The script cannot be dot-sourced (it opens
# the window), so each function is cut out of its syntax tree and defined here,
# with plain objects in place of the window controls.

BeforeAll {
    . "$PSScriptRoot\TestHelpers.ps1"
    . "$PSScriptRoot\CMStubs.ps1"
    Import-AppModule
    # The preference functions read the site of the shell. No site is chosen here: the old prefs file is used.
    $script:Site = [pscustomobject]@{ Active = $false }
    $script:ShellPath = Join-Path $script:AppRoot 'start-updateplanner.ps1'
    $script:Ast = [System.Management.Automation.Language.Parser]::ParseFile($script:ShellPath, [ref]$null, [ref]$null)
    $wanted = 'Get-UpPreferences', 'Save-UpPreferences', 'Set-StatusText', 'Update-StatusBarSummary', 'Get-SeverityName',
        'Save-SettingsToPrefs', 'Update-ControlState', 'Update-WaveList', 'Get-ReportText', 'Write-ActionRecord'
    foreach ($n in $wanted) {
        $def = $script:Ast.Find({ param($x) $x -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -eq $n }, $true)
        if (-not $def) { throw "function $n not found in the script" }
        . ([scriptblock]::Create($def.Extent.Text))
    }
}

AfterAll {
    if (Get-Command Remove-CMTestStub -ErrorAction SilentlyContinue) { Remove-CMTestStub }
    Remove-Variable -Name Prefs, PrefsPath -Scope Global -ErrorAction SilentlyContinue
}

Describe 'Get-SeverityName' {
    It 'returns All when nothing is selected and the item content otherwise' {
        $cboSeverity = [PSCustomObject]@{ SelectedItem = $null }
        Get-SeverityName | Should -Be 'All'
        $cboSeverity = [PSCustomObject]@{ SelectedItem = [PSCustomObject]@{ Content = 'Critical' } }
        Get-SeverityName | Should -Be 'Critical'
    }
}

Describe 'Update-StatusBarSummary' {
    BeforeEach {
        $global:Prefs = @{ SiteCode = 'ABC'; SMSProvider = 'sms01' }
        $txtStatus = [PSCustomObject]@{ Text = '' }
        $toggleActions = [PSCustomObject]@{ IsOn = $false }
        $script:WaveList = @()
        $script:Plan = $null
    }

    It 'says what to do when the provider is missing' {
        $global:Prefs = @{ SiteCode = 'ABC'; SMSProvider = '' }
        Update-StatusBarSummary
        $txtStatus.Text | Should -Be 'Open Options to set the SMS Provider   |   0 wave collections   |   read only'
    }

    It 'shows the wave count and read only mode' {
        $script:WaveList = @(1, 2, 3)
        Update-StatusBarSummary
        $txtStatus.Text | Should -Be '3 wave collections   |   read only'
    }

    It 'shows the plan and that actions are enabled' {
        $script:Plan = [PSCustomObject]@{ PlanId = 'P1'; Summary = [PSCustomObject]@{ UpdateAssignmentsPlanned = 12 } }
        $toggleActions.IsOn = $true
        Update-StatusBarSummary
        $txtStatus.Text | Should -Be '0 wave collections   |   plan P1: 12 assignments   |   actions enabled'
    }
}

Describe 'Update-ControlState' {
    BeforeEach {
        $names = 'btnBuildPlan', 'btnOptions', 'btnLoadCollections', 'btnAddWave', 'btnExportJson', 'btnExportMarkdown', 'btnExportHtml', 'btnSendHandoff',
            'btnOpenHtml', 'btnCopyReport', 'btnDryRun', 'btnApply', 'btnRemoveWave', 'btnWaveUp', 'btnWaveDown'
        foreach ($n in $names) { Set-Variable -Name $n -Value ([PSCustomObject]@{ IsEnabled = $null }) }
        $toggleActions = [PSCustomObject]@{ IsOn = $false }
        $lstWaves = [PSCustomObject]@{ SelectedIndex = -1 }
        $script:WaveList = @()
        $script:Plan = $null
        $script:IsBusy = $false
    }

    It 'enables the setup buttons and nothing that needs a plan when idle with no plan' {
        Update-ControlState
        foreach ($n in 'btnBuildPlan', 'btnOptions', 'btnLoadCollections', 'btnAddWave') { (Get-Variable -Name $n -ValueOnly).IsEnabled | Should -BeTrue -Because $n }
        foreach ($n in 'btnExportJson', 'btnExportMarkdown', 'btnExportHtml', 'btnSendHandoff', 'btnOpenHtml', 'btnCopyReport', 'btnDryRun', 'btnApply', 'btnRemoveWave', 'btnWaveUp', 'btnWaveDown') {
            (Get-Variable -Name $n -ValueOnly).IsEnabled | Should -BeFalse -Because $n
        }
    }

    It 'disables the setup buttons while busy' {
        $script:IsBusy = $true
        Update-ControlState
        foreach ($n in 'btnBuildPlan', 'btnOptions', 'btnLoadCollections', 'btnAddWave') { (Get-Variable -Name $n -ValueOnly).IsEnabled | Should -BeFalse -Because $n }
    }

    It 'enables the exports with a plan, and the dry run and apply only when actions are on and idle' -ForEach @(
        @{ Case = 'actions off';        Actions = $false; Busy = $false; Expected = $false }
        @{ Case = 'actions on';         Actions = $true;  Busy = $false; Expected = $true }
        @{ Case = 'actions on and busy'; Actions = $true; Busy = $true;  Expected = $false }
    ) {
        $script:Plan = [PSCustomObject]@{ PlanId = 'P1' }
        $toggleActions.IsOn = $Actions
        $script:IsBusy = $Busy
        Update-ControlState
        foreach ($n in 'btnExportJson', 'btnExportMarkdown', 'btnExportHtml', 'btnSendHandoff', 'btnOpenHtml', 'btnCopyReport') { (Get-Variable -Name $n -ValueOnly).IsEnabled | Should -BeTrue -Because $n }
        $btnDryRun.IsEnabled | Should -Be $Expected -Because $Case
        $btnApply.IsEnabled | Should -Be $Expected -Because $Case
    }

    It 'allows the wave buttons by the selected position (<Index> of 3: remove <Remove>, up <Up>, down <Down>)' -ForEach @(
        @{ Index = -1; Remove = $false; Up = $false; Down = $false }
        @{ Index = 0;  Remove = $true;  Up = $false; Down = $true }
        @{ Index = 1;  Remove = $true;  Up = $true;  Down = $true }
        @{ Index = 2;  Remove = $true;  Up = $true;  Down = $false }
    ) {
        $script:WaveList = @(1, 2, 3)
        $lstWaves.SelectedIndex = $Index
        Update-ControlState
        $btnRemoveWave.IsEnabled | Should -Be $Remove
        $btnWaveUp.IsEnabled | Should -Be $Up
        $btnWaveDown.IsEnabled | Should -Be $Down
    }

    It 'disables the wave buttons while busy' {
        $script:WaveList = @(1, 2, 3)
        $lstWaves.SelectedIndex = 1
        $script:IsBusy = $true
        Update-ControlState
        $btnRemoveWave.IsEnabled | Should -BeFalse
        $btnWaveUp.IsEnabled | Should -BeFalse
        $btnWaveDown.IsEnabled | Should -BeFalse
    }
}

Describe 'Update-WaveList' {
    BeforeEach {
        Mock Update-ControlState { }
        Mock Update-StatusBarSummary { }
        $global:Prefs = @{ Waves = @() }
        $lstWaves = [PSCustomObject]@{ ItemsSource = $null; SelectedIndex = -1 }
        $script:WaveList = @([PSCustomObject]@{ Id = 'ABC00001'; Name = 'Pilot' }, [PSCustomObject]@{ Id = 'ABC00002'; Name = 'Broad | all' })
    }

    It 'numbers the waves, names the id, and stores them as id|name' {
        Update-WaveList
        @($lstWaves.ItemsSource) | Should -Be @('1.  Pilot   (ABC00001)', '2.  Broad | all   (ABC00002)')
        @($global:Prefs['Waves']) | Should -Be @('ABC00001|Pilot', 'ABC00002|Broad | all')
    }

    It 'selects the row asked for when it is in range' -ForEach @(
        @{ Select = 0; Expected = 0 }, @{ Select = 1; Expected = 1 }, @{ Select = 2; Expected = -1 }, @{ Select = -1; Expected = -1 }
    ) {
        Update-WaveList -Select $Select
        $lstWaves.SelectedIndex | Should -Be $Expected
    }

    It 'handles an empty list' {
        $script:WaveList = @()
        Update-WaveList
        @($lstWaves.ItemsSource).Count | Should -Be 0
        @($global:Prefs['Waves']).Count | Should -Be 0
    }

    It 'refreshes the control state and the status bar once' {
        Update-WaveList
        Should -Invoke Update-ControlState -Times 1 -Exactly -Scope It
        Should -Invoke Update-StatusBarSummary -Times 1 -Exactly -Scope It
    }
}

Describe 'Get-ReportText' {
    BeforeEach {
        Mock ConvertTo-UpdatePlanHtml { 'html-report' }
        Mock ConvertTo-UpdatePlanMarkdown { 'markdown-report' }
        $rdoHtml = [PSCustomObject]@{ IsChecked = $false }
        $script:Plan = $null
    }

    It 'asks for a plan when there is none, and builds nothing' {
        Get-ReportText | Should -Be 'Build a plan to see the report.'
        Should -Invoke ConvertTo-UpdatePlanMarkdown -Times 0 -Scope It
        Should -Invoke ConvertTo-UpdatePlanHtml -Times 0 -Scope It
    }

    It 'gives Markdown by default and HTML when the HTML option is on' {
        $script:Plan = [PSCustomObject]@{ PlanId = 'P1' }
        Get-ReportText | Should -Be 'markdown-report'
        $rdoHtml.IsChecked = $true
        Get-ReportText | Should -Be 'html-report'
    }
}

Describe 'Write-ActionRecord' {
    BeforeEach {
        Mock Write-UpdatePlanAudit { $script:Record = $Record; $script:AuditPath = $Path }
        $script:Added = [System.Collections.ArrayList]::new()
        function Add-LogLine { param([string]$Message) [void]$script:Added.Add($Message) }
        $script:ActionLogPath = Join-Path $TestDrive 'actions.jsonl'
        $script:Plan = [PSCustomObject]@{ PlanId = 'P1'; SiteCode = 'ABC' }
        $global:Prefs = @{ SMSProvider = 'sms01' }
        $script:Record = $null
    }

    It 'writes the action, the plan, the site, the provider and the results to the action log' {
        Write-ActionRecord -Action 'DryRun' -Results @('r1', 'r2')
        $script:AuditPath | Should -Be $script:ActionLogPath
        $script:Record.Action | Should -Be 'DryRun'
        $script:Record.PlanId | Should -Be 'P1'
        $script:Record.Site | Should -Be 'ABC'
        $script:Record.Provider | Should -Be 'sms01'
        @($script:Record.Results) | Should -Be @('r1', 'r2')
        $script:Record.User | Should -Match '^.+\\.+$'
        { [datetime]::Parse($script:Record.Time) } | Should -Not -Throw
    }

    It 'tells the user in plain words and does not throw when the log cannot be written' {
        Mock Write-UpdatePlanAudit { throw 'disk full' }
        { Write-ActionRecord -Action 'Apply' -Results @() } | Should -Not -Throw
        $script:Added | Should -Contain 'The action log could not be written. The log file has the details.'
        ($script:Added -join ' ') | Should -Not -Match 'disk full'
    }
}

Describe 'Preferences file' {
    BeforeEach { $global:PrefsPath = Join-Path $TestDrive ('prefs-{0}.json' -f [guid]::NewGuid().ToString('N')) }

    It 'gives the defaults on first run' {
        $p = Get-UpPreferences
        $p.DarkMode | Should -BeTrue
        $p.SiteCode | Should -Be ''
        $p.SMSProvider | Should -Be ''
        $p.WaveSpacingDays | Should -Be '7'
        $p.DeadlineDays | Should -Be '3'
        $p.Severity | Should -Be 'All'
        $p.MaxUpdates | Should -Be '1000'
        $p.IncludeWsus | Should -BeFalse
        @($p.Waves).Count | Should -Be 0
    }

    It 'gives the defaults for a <Case> file' -ForEach @(
        @{ Case = 'corrupt'; Content = '{ not json' }
        @{ Case = 'empty'; Content = '' }
        @{ Case = 'array'; Content = '[1,2,3]' }
    ) {
        Set-Content -LiteralPath $global:PrefsPath -Value $Content
        (Get-UpPreferences).SiteCode | Should -Be ''
        (Get-UpPreferences).MaxUpdates | Should -Be '1000'
    }

    It 'ignores a key it does not know' {
        Set-Content -LiteralPath $global:PrefsPath -Value '{ "SiteCode": "ABC", "Evil": "x" }'
        $p = Get-UpPreferences
        $p.SiteCode | Should -Be 'ABC'
        $p.ContainsKey('Evil') | Should -BeFalse
    }

    It 'round-trips the value <Case>' -ForEach @(
        @{ Case = 'plain'; Value = 'ABC' }
        @{ Case = 'accented and wide characters'; Value = ('{0}n{1}-{2}{3}' -f [char]0x00DC, [char]0x00EF, [char]0x65E5, [char]0x672C) }
        @{ Case = 'quote and backslash'; Value = 'a "q" \ b' }
        @{ Case = 'long'; Value = ('x' * 5000) }
    ) {
        Save-UpPreferences -Prefs @{ DarkMode = $false; SiteCode = $Value; SMSProvider = 'sms01'; Waves = @('ABC00001|Pilot') }
        $p = Get-UpPreferences
        $p.SiteCode | Should -Be $Value
        $p.DarkMode | Should -BeFalse
        @($p.Waves) | Should -Be @('ABC00001|Pilot')
    }

    It 'does not throw when the file cannot be written' {
        $global:PrefsPath = Join-Path $TestDrive 'dir-in-the-way'
        New-Item -ItemType Directory -Path $global:PrefsPath | Out-Null
        { Save-UpPreferences -Prefs @{ DarkMode = $true; SiteCode = 'X'; SMSProvider = '' } } | Should -Not -Throw
    }
}

Describe 'Save-SettingsToPrefs' {
    BeforeEach {
        $global:PrefsPath = Join-Path $TestDrive ('prefs-{0}.json' -f [guid]::NewGuid().ToString('N'))
        $global:Prefs = Get-UpPreferences
        $txtSpacing = [PSCustomObject]@{ Text = '14' }
        $txtDeadline = [PSCustomObject]@{ Text = '5' }
        $txtMaxUpdates = [PSCustomObject]@{ Text = '250' }
        $chkWsus = [PSCustomObject]@{ IsChecked = $true }
        $cboSeverity = [PSCustomObject]@{ SelectedItem = [PSCustomObject]@{ Content = 'Important' } }
    }

    It 'copies the settings fields into the preferences and saves them' {
        Save-SettingsToPrefs
        $p = Get-UpPreferences
        $p.WaveSpacingDays | Should -Be '14'
        $p.DeadlineDays | Should -Be '5'
        $p.MaxUpdates | Should -Be '250'
        $p.IncludeWsus | Should -BeTrue
        $p.Severity | Should -Be 'Important'
    }

    It 'saves the wave list that Update-WaveList stored' {
        $global:Prefs['Waves'] = @('ABC00001|Pilot')
        Save-SettingsToPrefs
        @((Get-UpPreferences).Waves) | Should -Be @('ABC00001|Pilot')
    }

    It 'saves an unchecked box as false and no selection as All' {
        $chkWsus.IsChecked = $null
        $cboSeverity.SelectedItem = $null
        Save-SettingsToPrefs
        $p = Get-UpPreferences
        $p.IncludeWsus | Should -BeFalse
        $p.Severity | Should -Be 'All'
    }
}

Describe 'Script contract' {
    It 'calls only commands that exist' {
        $own = @($script:Ast.FindAll({ param($x) $x -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object Name)
        $called = @($script:Ast.FindAll({ param($x) $x -is [System.Management.Automation.Language.CommandAst] }, $true) |
                ForEach-Object { $_.GetCommandName() } | Where-Object { $_ } | Sort-Object -Unique)
        Import-Module (Join-Path $script:AppRoot 'Lib\SuiteCommon\SuiteCommon.psd1') -Global -DisableNameChecking -ErrorAction SilentlyContinue
        $missing = @($called | Where-Object { $_ -notin $own -and -not (Get-Command $_ -ErrorAction SilentlyContinue) })
        $missing | Where-Object { $_ -notmatch '^(Get|Set|New|Remove|Start|Invoke|Add|Copy)-CM' } | Should -BeNullOrEmpty
    }
}
