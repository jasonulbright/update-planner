#Requires -Modules Pester
# Per-site data (Q-112f). An old-layout tool folder is seeded in a temp folder. The path and prefs logic of the tool
# runs for site AB1, then site CD2, then AB1 again, and with no site. The tests check that the old files stay as they
# are, that AB1 data is copied once, that CD2 shows nothing of AB1 and writes only below sites\CD2.
# The site codes are fictional (AB1, CD2). The hosts use example.com.

BeforeAll {
    . "$PSScriptRoot\TestHelpers.ps1"
    Import-AppModule

    $script:envNames = 'APP_PACKAGER_DATA_ROOT', 'APP_PACKAGER_SITE', 'SUITE_CM_SITECODE', 'SUITE_CM_PROVIDER'
    $script:envSaved = @{}
    foreach ($n in $script:envNames) { $script:envSaved[$n] = [Environment]::GetEnvironmentVariable($n) }

    function Set-TestEnv {
        param([string]$Site, [string]$DataRoot)
        foreach ($n in $script:envNames) { [Environment]::SetEnvironmentVariable($n, $null) }
        [Environment]::SetEnvironmentVariable('APP_PACKAGER_DATA_ROOT', $DataRoot)
        if ($Site) { [Environment]::SetEnvironmentVariable('APP_PACKAGER_SITE', $Site) }
    }

    # The old single-site layout of the tool: files beside the script, site AB1.
    function New-OldLayout {
        param([Parameter(Mandatory)][string]$Base)
        $suite = Join-Path $Base 'suite'
        $tool = Join-Path $suite 'update-planner'
        New-Item -ItemType Directory -Path (Join-Path $tool 'Logs'), (Join-Path $tool 'Reports') -Force | Out-Null
        $prefs = [ordered]@{
            DarkMode = $false; SiteCode = 'AB1'; SMSProvider = 'ab1-sms.example.com'
            WaveSpacingDays = '14'; DeadlineDays = '5'; Severity = 'Critical'; MaxUpdates = '500'
            IncludeWsus = $true; Waves = @('AB100001|Pilot AB1', 'AB100002|Broad AB1')
        }
        $prefs | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $tool 'UpdatePlanner.prefs.json') -Encoding UTF8
        '{"Time":"2026-01-01T00:00:00.0000000+00:00","Action":"DryRun","PlanId":"P-AB1","Site":"AB1","Provider":"ab1-sms.example.com","Results":[]}' |
            Set-Content -LiteralPath (Join-Path $tool 'Logs\update-planner-actions.jsonl') -Encoding UTF8
        '<html><body>ab1 plan</body></html>' | Set-Content -LiteralPath (Join-Path $tool 'Reports\update-plan-P-AB1.html') -Encoding UTF8
        '{"PlanId":"P-AB1"}' | Set-Content -LiteralPath (Join-Path $tool 'Reports\update-plan-P-AB1.json') -Encoding UTF8
        return [pscustomobject]@{ Suite = $suite; Tool = $tool; Local = (Join-Path $Base 'local') }
    }

    function Get-OldFileHash {
        param([Parameter(Mandatory)][string]$Tool)
        $h = @{}
        foreach ($f in Get-ChildItem -LiteralPath $Tool -Recurse -File) { $h[$f.FullName] = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash }
        return $h
    }

    function Start-ToolForSite {
        param([Parameter(Mandatory)]$Layout, [string]$Site, [Parameter(Mandatory)][string]$DataRoot)
        Set-TestEnv -Site $Site -DataRoot $DataRoot
        $prefsPath = Join-Path $Layout.Tool 'UpdatePlanner.prefs.json'
        $siteInfo = Resolve-SuiteToolSite -Tool 'update-planner' -ToolRoot $Layout.Tool -LegacyPrefsPath $prefsPath -LocalRoot $Layout.Local
        $paths = Get-UpSitePath -Site $siteInfo -ToolRoot $Layout.Tool -Create
        $prefs = Read-UpPreference -Path $paths.PrefsPath -Site $siteInfo
        return [pscustomobject]@{ Site = $siteInfo; Paths = $paths; Prefs = $prefs }
    }
}

AfterAll {
    foreach ($n in $script:envNames) { [Environment]::SetEnvironmentVariable($n, $script:envSaved[$n]) }
}

Describe 'Update Planner keeps its data per site' {
    BeforeAll {
        $script:base = Join-Path $TestDrive 'iso'
        $script:layout = New-OldLayout -Base $script:base
        $script:data = Join-Path $script:base 'data'
        $script:before = Get-OldFileHash -Tool $script:layout.Tool
        $script:ab1 = Start-ToolForSite -Layout $script:layout -Site 'AB1' -DataRoot $script:data
        $script:afterAb1 = Get-OldFileHash -Tool $script:layout.Tool
    }

    It 'uses the site AB1 and a site folder below the data root' {
        $script:ab1.Site.Active | Should -BeTrue
        $script:ab1.Site.SiteFolder | Should -Be 'AB1'
        $script:ab1.Site.ToolFolder | Should -BeLike (Join-Path $script:data '*\sites\AB1\tools\update-planner')
    }

    It 'leaves every old file as it was after the copy (SHA-256)' {
        $script:afterAb1.Count | Should -Be $script:before.Count
        foreach ($k in $script:before.Keys) { $script:afterAb1[$k] | Should -Be $script:before[$k] }
    }

    It 'copies the AB1 stores into the site folder once' {
        $tf = $script:ab1.Site.ToolFolder
        foreach ($name in 'update-planner-actions.jsonl', 'reports\update-plan-P-AB1.html', 'reports\update-plan-P-AB1.json', 'prefs.json') {
            Test-Path -LiteralPath (Join-Path $tf $name) | Should -BeTrue -Because $name
        }
        (Get-FileHash -LiteralPath (Join-Path $tf 'update-planner-actions.jsonl')).Hash | Should -Be (Get-FileHash -LiteralPath (Join-Path $script:layout.Tool 'Logs\update-planner-actions.jsonl')).Hash
        (Get-FileHash -LiteralPath (Join-Path $tf 'reports\update-plan-P-AB1.html')).Hash | Should -Be (Get-FileHash -LiteralPath (Join-Path $script:layout.Tool 'Reports\update-plan-P-AB1.html')).Hash
        $marker = Join-Path $tf 'migrated.json'
        $stamp = (Get-Item -LiteralPath $marker).LastWriteTimeUtc
        $again = Start-ToolForSite -Layout $script:layout -Site 'AB1' -DataRoot $script:data
        $again.Site.Migration | Should -Be 'done earlier'
        (Get-Item -LiteralPath $marker).LastWriteTimeUtc | Should -Be $stamp
    }

    It 'points every store path at the site folder and keeps the prefs file beside the script' {
        $tf = $script:ab1.Site.ToolFolder
        $script:ab1.Paths.ActionLogPath | Should -Be (Join-Path $tf 'update-planner-actions.jsonl')
        $script:ab1.Paths.ReportsDir | Should -Be (Join-Path $tf 'reports')
        $script:ab1.Paths.PrefsPath | Should -Be (Join-Path $script:layout.Tool 'UpdatePlanner.prefs.json')
    }

    It 'reads the AB1 site values and keeps the global keys from the old prefs file' {
        $script:ab1.Prefs.SiteCode | Should -Be 'AB1'
        $script:ab1.Prefs.SMSProvider | Should -Be 'ab1-sms.example.com'
        @($script:ab1.Prefs.Waves) | Should -Be @('AB100001|Pilot AB1', 'AB100002|Broad AB1')
        $script:ab1.Prefs.DarkMode | Should -BeFalse
        $script:ab1.Prefs.MaxUpdates | Should -Be '500'
        $script:ab1.Prefs.Severity | Should -Be 'Critical'
    }

    It 'does not read the launcher variables when a site is active' {
        [Environment]::SetEnvironmentVariable('SUITE_CM_PROVIDER', 'launcher-sms.example.com')
        [Environment]::SetEnvironmentVariable('SUITE_CM_SITECODE', 'EF3')
        $p = Read-UpPreference -Path $script:ab1.Paths.PrefsPath -Site $script:ab1.Site
        $p.SMSProvider | Should -Be 'ab1-sms.example.com'
        $p.SiteCode | Should -Be 'AB1'
        [Environment]::SetEnvironmentVariable('SUITE_CM_PROVIDER', $null)
        [Environment]::SetEnvironmentVariable('SUITE_CM_SITECODE', $null)
    }

    Context 'site CD2' {
        BeforeAll {
            $script:cd2 = Start-ToolForSite -Layout $script:layout -Site 'CD2' -DataRoot $script:data
        }

        It 'shows none of the AB1 values' {
            $script:cd2.Site.SiteFolder | Should -Be 'CD2'
            $script:cd2.Prefs.SiteCode | Should -Be 'CD2'
            $script:cd2.Prefs.SMSProvider | Should -Not -Match 'ab1'
            @($script:cd2.Prefs.Waves).Count | Should -Be 0
        }

        It 'gets no copy of the AB1 stores' {
            $tf = $script:cd2.Site.ToolFolder
            foreach ($name in 'update-planner-actions.jsonl', 'reports\update-plan-P-AB1.html', 'reports\update-plan-P-AB1.json') {
                Test-Path -LiteralPath (Join-Path $tf $name) | Should -BeFalse -Because $name
            }
            @(Get-ChildItem -LiteralPath $script:cd2.Paths.ReportsDir -File -ErrorAction SilentlyContinue).Count | Should -Be 0
        }

        It 'writes only below sites\CD2' {
            $ab1Files = Get-OldFileHash -Tool $script:ab1.Site.ToolFolder
            $oldFolderBefore = Get-OldFileHash -Tool $script:layout.Tool
            $cd2Prefs = @{} + $script:cd2.Prefs
            $cd2Prefs.SMSProvider = 'cd2-sms.example.com'
            $cd2Prefs.Waves = @('CD200001|Pilot CD2')
            Save-UpPreference -Path $script:cd2.Paths.PrefsPath -Preference $cd2Prefs -Site $script:cd2.Site | Should -BeTrue
            Write-UpdatePlanAudit -Path $script:cd2.Paths.ActionLogPath -Record ([pscustomobject]@{ Action = 'DryRun'; PlanId = 'P-CD2'; Site = 'CD2' })
            $report = Write-UpdatePlanFile -Path (Join-Path $script:cd2.Paths.ReportsDir 'update-plan-P-CD2.html') -Text '<html>cd2 plan</html>'
            $cd2Folder = $script:cd2.Site.ToolFolder
            foreach ($p in $script:cd2.Paths.ActionLogPath, $report, (Join-Path $cd2Folder 'prefs.json')) {
                $p | Should -BeLike (Join-Path $script:data '*\sites\CD2\tools\update-planner\*')
                Test-Path -LiteralPath $p | Should -BeTrue -Because $p
            }
            # The AB1 site folder is unchanged.
            $now = Get-OldFileHash -Tool $script:ab1.Site.ToolFolder
            foreach ($k in $ab1Files.Keys) { $now[$k] | Should -Be $ab1Files[$k] -Because $k }
            $now.Count | Should -Be $ab1Files.Count
            # Nothing new appears beside the script. Only the old prefs file may change (its global keys).
            $oldFolderAfter = Get-OldFileHash -Tool $script:layout.Tool
            @($oldFolderAfter.Keys | Where-Object { -not $oldFolderBefore.ContainsKey($_) }) | Should -BeNullOrEmpty
            foreach ($k in $oldFolderBefore.Keys | Where-Object { $_ -notlike '*UpdatePlanner.prefs.json' }) { $oldFolderAfter[$k] | Should -Be $oldFolderBefore[$k] -Because $k }
            $oldPrefs = Get-Content -LiteralPath (Join-Path $script:layout.Tool 'UpdatePlanner.prefs.json') -Raw | ConvertFrom-Json
            $oldPrefs.SiteCode | Should -Be 'AB1'
            $oldPrefs.SMSProvider | Should -Be 'ab1-sms.example.com'
            @($oldPrefs.Waves) | Should -Be @('AB100001|Pilot AB1', 'AB100002|Broad AB1')
        }
    }

    Context 'back to site AB1' {
        It 'shows the AB1 values and stores again' {
            $back = Start-ToolForSite -Layout $script:layout -Site 'AB1' -DataRoot $script:data
            $back.Prefs.SiteCode | Should -Be 'AB1'
            $back.Prefs.SMSProvider | Should -Be 'ab1-sms.example.com'
            @($back.Prefs.Waves) | Should -Be @('AB100001|Pilot AB1', 'AB100002|Broad AB1')
            @(Get-Content -LiteralPath $back.Paths.ActionLogPath).Count | Should -Be 1
            (Get-Content -LiteralPath $back.Paths.ActionLogPath -Raw) | Should -Match 'P-AB1'
            Test-Path -LiteralPath (Join-Path $back.Paths.ReportsDir 'update-plan-P-AB1.html') | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $back.Paths.ReportsDir 'update-plan-P-CD2.html') | Should -BeFalse
        }
    }
}

Describe 'Update Planner with no site chosen' {
    BeforeAll {
        $script:base2 = Join-Path $TestDrive 'nosite'
        $script:layout2 = New-OldLayout -Base $script:base2
        # An old prefs file with no site code names no site.
        @{ DarkMode = $true; SiteCode = ''; SMSProvider = 'old-sms.example.com'; Waves = @('EF300001|Old wave') } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $script:layout2.Tool 'UpdatePlanner.prefs.json') -Encoding UTF8
        $script:none = Start-ToolForSite -Layout $script:layout2 -Site '' -DataRoot (Join-Path $script:base2 'data')
    }

    It 'is not active and keeps the old paths beside the script' {
        $script:none.Site.Active | Should -BeFalse
        $t = $script:layout2.Tool
        $script:none.Paths.ActionLogPath | Should -Be (Join-Path $t 'Logs\update-planner-actions.jsonl')
        $script:none.Paths.ReportsDir | Should -Be (Join-Path $t 'Reports')
        $script:none.Paths.PrefsPath | Should -Be (Join-Path $t 'UpdatePlanner.prefs.json')
    }

    It 'creates no site folder' {
        Test-Path -LiteralPath (Join-Path $script:base2 'data') | Should -BeFalse
    }

    It 'reads the old prefs file, with the wave list' {
        $script:none.Prefs.SMSProvider | Should -Be 'old-sms.example.com'
        $script:none.Prefs.SiteCode | Should -BeNullOrEmpty
        @($script:none.Prefs.Waves) | Should -Be @('EF300001|Old wave')
    }

    It 'fills an empty provider from the launcher provider variable only when no site is active' {
        Set-TestEnv -Site '' -DataRoot (Join-Path $script:base2 'data')
        @{ DarkMode = $true } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $script:layout2.Tool 'UpdatePlanner.prefs.json') -Encoding UTF8
        [Environment]::SetEnvironmentVariable('SUITE_CM_PROVIDER', 'launcher-sms.example.com')
        [Environment]::SetEnvironmentVariable('SUITE_CM_SITECODE', 'EF3')
        $noSite = [pscustomobject]@{ Active = $false }
        $p = Read-UpPreference -Path (Join-Path $script:layout2.Tool 'UpdatePlanner.prefs.json') -Site $noSite
        $p.SMSProvider | Should -Be 'launcher-sms.example.com'
        $p.SiteCode | Should -Be 'EF3'
        [Environment]::SetEnvironmentVariable('SUITE_CM_PROVIDER', $null)
        [Environment]::SetEnvironmentVariable('SUITE_CM_SITECODE', $null)
    }

    It 'saves to the old prefs file, the site keys included' {
        $noSite = [pscustomobject]@{ Active = $false }
        $p = Get-UpPreferenceDefault
        $p.SiteCode = 'EF3'
        $p.SMSProvider = 'ef3-sms.example.com'
        $p.Waves = @('EF300001|Pilot EF3')
        Save-UpPreference -Path $script:none.Paths.PrefsPath -Preference $p -Site $noSite | Should -BeTrue
        $saved = Get-Content -LiteralPath $script:none.Paths.PrefsPath -Raw | ConvertFrom-Json
        $saved.SiteCode | Should -Be 'EF3'
        @($saved.Waves) | Should -Be @('EF300001|Pilot EF3')
    }

    It 'throws when a site folder cannot be created, so that the caller falls back to the old paths for both stores' {
        # A folder name with a character that Windows refuses: the folder cannot be created.
        $broken = [pscustomobject]@{ Active = $true; ToolFolder = (Join-Path $TestDrive 'bad|name') }
        { Get-UpSitePath -Site $broken -ToolRoot $script:layout2.Tool -Create } | Should -Throw
    }
    It 'works with a null site like no site' {
        (Get-UpSitePath -Site $null -ToolRoot $script:layout2.Tool).ReportsDir | Should -Be (Join-Path $script:layout2.Tool 'Reports')
        (Read-UpPreference -Path $script:none.Paths.PrefsPath -Site $null).SMSProvider | Should -Be 'ef3-sms.example.com'
    }
}

Describe 'Update Planner source builds no site store from the script folder' {
    BeforeAll {
        $script:scriptText = Get-Content -LiteralPath (Join-Path $script:AppRoot 'start-updateplanner.ps1') -Raw
    }

    It 'builds no report or action log path from the script folder in the window script' {
        [regex]::IsMatch($script:scriptText, 'Join-Path \$PSScriptRoot ''Reports''') | Should -BeFalse
        [regex]::IsMatch($script:scriptText, 'Join-Path \(Join-Path \$PSScriptRoot ''Reports''\)') | Should -BeFalse
        [regex]::IsMatch($script:scriptText, 'Join-Path \$__txDir ''update-planner-actions\.jsonl''') | Should -BeFalse
        $script:scriptText.Contains('$script:ActionLogPath = $__sitePaths.ActionLogPath') | Should -BeTrue
        $script:scriptText.Contains('$script:ReportsDir = $__sitePaths.ReportsDir') | Should -BeTrue
    }

    It 'resolves the site before it reads the preferences' {
        $script:scriptText.IndexOf('Resolve-SuiteToolSite -Tool ''update-planner''') | Should -BeGreaterThan 0
        $script:scriptText.IndexOf('Resolve-SuiteToolSite') | Should -BeLessThan $script:scriptText.IndexOf('$global:Prefs = Get-UpPreferences')
    }

    It 'sets the Site Code field read-only with the launcher tooltip when a site is active' {
        $script:scriptText.Contains('$txtSiteCode.IsReadOnly = $true') | Should -BeTrue
        $script:scriptText.Contains('The site is chosen in the AppPackager Suite launcher. Restart this tool after you change it.') | Should -BeTrue
        $script:scriptText.Contains('Start-SuiteSiteWatch -Window $window -Site $script:Site') | Should -BeTrue
        $script:scriptText.IndexOf('Initialize-SuiteFooter') | Should -BeLessThan $script:scriptText.IndexOf('Start-SuiteSiteWatch')
        $script:scriptText.Contains('$newSite     = $(if ($script:Site.Active) { [string]$global:Prefs.SiteCode }') | Should -BeTrue
    }
}
