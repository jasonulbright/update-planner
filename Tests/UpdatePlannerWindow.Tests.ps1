[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingComputerNameHardcoded', '', Justification = 'Test inputs are fake computer names.')]
param ()

BeforeAll {
    $strTestsFolder = Split-Path -Path $PSCommandPath -Parent
    $script:strRepositoryRoot = Split-Path -Path $strTestsFolder -Parent
    $script:strManifestPath = Join-Path -Path (Join-Path -Path $script:strRepositoryRoot -ChildPath 'Module') -ChildPath 'UpdatePlannerCommon.psd1'
    Import-Module -Name $script:strManifestPath -Force

    function New-WindowTestPlan {
        $objState = [pscustomobject]@{
            ComputerName = 'cm01.contoso.com'
            SiteCode = 'ABC'
            Sync = [pscustomobject]@{ WsusServerName = 'wsus'; Source = 'Microsoft Update'; LastSuccessfulSyncTime = '2026-11-05 02:02'; LastSyncErrorCode = 0 }
            Wsus = $null
            Updates = @(
                [pscustomobject]@{ CIId = 1; ArticleId = '5001'; Title = 'Critical <update> & more'; Severity = 10; IsExpired = $false; IsSuperseded = $false; IsDeployed = $false; NumMissing = 3; NumPresent = 0; NumTotal = 4; DateRevised = [datetime]'2026-09-01' }
                [pscustomobject]@{ CIId = 2; ArticleId = ''; Title = 'No article'; Severity = 8; IsExpired = $false; IsSuperseded = $true; IsDeployed = $false; NumMissing = 2; NumPresent = 0; NumTotal = 4; DateRevised = [datetime]'2026-09-01' }
            )
            Collections = @(
                [pscustomobject]@{ CollectionId = 'ABC00001'; Name = 'Pilot'; MemberCount = 2; MaintenanceWindowCount = 0; MaintenanceWindows = @(); NeededByUpdate = @{ '1' = 1; '2' = 1 } }
                [pscustomobject]@{ CollectionId = 'ABC00002'; Name = 'Broad'; MemberCount = 9; MaintenanceWindowCount = 0; MaintenanceWindows = @(); NeededByUpdate = @{ '1' = 3 } }
            )
            Deployments = @()
            Summary = [pscustomobject]@{ TotalUpdates = 2; NeededUpdates = 2; InstalledUpdates = 0; SupersededUpdates = 1; ExpiredUpdates = 0; ExistingDeployments = 0 }
        }
        New-UpdatePlan -State $objState -StartDate ([datetime]'2026-12-01') -WaveSpacingDays 7 -DeadlineDays 3
    }
}

AfterAll {
    Remove-Module -Name UpdatePlannerCommon -Force -ErrorAction SilentlyContinue
}

Describe 'Resolve-UpdatePlannerSetting' {
    It 'accepts good values and returns typed values' {
        $objSetting = Resolve-UpdatePlannerSetting -ComputerName ' cm01.contoso.com ' -StartDateText '2026-12-01' -WaveSpacingText '7' -DeadlineText '3' -SeverityName 'Important' -MaxUpdatesText '25' -TargetCollection @('ABC00001', 'ABC00002')
        $objSetting.IsValid | Should -BeTrue
        $objSetting.Errors.Count | Should -Be 0
        $objSetting.ComputerName | Should -Be 'cm01.contoso.com'
        $objSetting.StartDate | Should -Be ([datetime]'2026-12-01')
        $objSetting.WaveSpacingDays | Should -Be 7
        $objSetting.DeadlineDays | Should -Be 3
        $objSetting.MinimumSeverity | Should -Be 8
        $objSetting.MaxUpdatesPerWave | Should -Be 25
        $objSetting.TargetCollection | Should -Be @('ABC00001', 'ABC00002')
    }

    It 'maps each severity name to its number' {
        $hashtableExpected = @{ All = 0; Low = 2; Moderate = 6; Important = 8; Critical = 10 }
        foreach ($strName in $hashtableExpected.Keys) {
            (Resolve-UpdatePlannerSetting -ComputerName 'cm01' -StartDateText '2026-12-01' -SeverityName $strName -TargetCollection 'ABC00001').MinimumSeverity | Should -Be $hashtableExpected[$strName]
        }
    }

    It 'reports one message for each wrong value' {
        $objSetting = Resolve-UpdatePlannerSetting -ComputerName '' -StartDateText 'not a date' -WaveSpacingText '-1' -DeadlineText 'x' -SeverityName 'Huge' -MaxUpdatesText '0' -TargetCollection @()
        $objSetting.IsValid | Should -BeFalse
        $objSetting.Errors.Count | Should -Be 7
    }

    It 'refuses a provider name that carries a query or a path' {
        (Resolve-UpdatePlannerSetting -ComputerName 'cm01;calc' -StartDateText '2026-12-01' -TargetCollection 'ABC00001').IsValid | Should -BeFalse
    }

    It 'refuses a collection that is in the wave list twice' {
        $objSetting = Resolve-UpdatePlannerSetting -ComputerName 'cm01' -StartDateText '2026-12-01' -TargetCollection @('ABC00001', 'ABC00001')
        $objSetting.IsValid | Should -BeFalse
        $objSetting.Errors | Should -Contain 'A collection is in the wave list more than once.'
    }
}

Describe 'Plan rows' {
    BeforeAll {
        $script:objPlan = New-WindowTestPlan
    }

    It 'makes one row for each planned update with the wave dates' {
        $arrRow = @(ConvertTo-UpdatePlanRow -Plan $script:objPlan)
        $arrRow.Count | Should -Be 2
        $arrRow[0].Wave | Should -Be 1
        $arrRow[0].Collection | Should -Be 'Pilot'
        $arrRow[0].Start | Should -Be '2026-12-01'
        $arrRow[0].Deadline | Should -Be '2026-12-04'
        $arrRow[0].Article | Should -Be 'KB5001'
        $arrRow[0].Severity | Should -Be 'Critical'
        $arrRow[1].Wave | Should -Be 2
        $arrRow[1].Start | Should -Be '2026-12-08'
    }

    It 'lists the superseded update that a device still needs as skipped' {
        $arrRow = @(ConvertTo-UpdatePlanSkippedRow -Plan $script:objPlan)
        $arrRow.Count | Should -BeGreaterThan 0
        $arrRow[0].Reason | Should -Be 'Superseded'
        $arrRow[0].Article | Should -Be ''
    }

    It 'previews one deployment for each wave that holds updates' {
        $arrPreview = @(Get-UpdatePlanDeploymentPreview -Plan $script:objPlan)
        $arrPreview.Count | Should -Be 2
        $arrPreview[0].Name | Should -Be ('UpdatePlanner {0} Wave 1 Pilot' -f $script:objPlan.PlanId)
        $arrPreview[0].CollectionId | Should -Be 'ABC00001'
        $arrPreview[0].UpdateCount | Should -Be 1
        $arrPreview[1].Deadline | Should -Be '2026-12-11'
    }

    It 'previews nothing for a plan whose waves hold no update' {
        $objEmpty = [pscustomobject]@{ PlanId = 'abcd1234'; Waves = @([pscustomobject]@{ Name = 'Wave 1 X'; CollectionId = 'ABC00001'; CollectionName = 'X'; StartDate = '2026-12-01'; DeadlineDate = '2026-12-04'; Updates = @() }) }
        @(Get-UpdatePlanDeploymentPreview -Plan $objEmpty).Count | Should -Be 0
    }
}

Describe 'Plan reports' {
    BeforeAll {
        $script:objPlan = New-WindowTestPlan
    }

    It 'returns the Markdown text that the file export writes' {
        $strText = ConvertTo-UpdatePlanMarkdown -Plan $script:objPlan
        $strText | Should -BeLike '# Update plan*'
        $strText | Should -BeLike '*## Wave 1: Wave 1 Pilot*'
        $strText | Should -BeLike '*KB5001*'
    }

    It 'returns JSON that reads back to the same plan' {
        $objBack = ConvertTo-UpdatePlanJson -Plan $script:objPlan | ConvertFrom-Json
        $objBack.PlanId | Should -Be $script:objPlan.PlanId
        @($objBack.Waves).Count | Should -Be 2
    }

    It 'returns an HTML page with encoded values, no script and no external resource' {
        $strHtml = ConvertTo-UpdatePlanHtml -Plan $script:objPlan
        $strHtml | Should -BeLike '<!DOCTYPE html>*'
        $strHtml | Should -BeLike '*Critical &lt;update&gt; &amp; more*'
        $strHtml | Should -Not -BeLike '*<update>*'
        $strHtml | Should -Not -BeLike '*<script*'
        $strHtml | Should -Not -BeLike '*http://*'
        $strHtml | Should -Not -BeLike '*https://*'
        $strHtml | Should -BeLike '*Wave 2: Wave 2 Broad*'
    }

    It 'writes a file as UTF-8 without a byte order mark and creates the folder' {
        $strPath = Join-Path -Path $TestDrive -ChildPath 'new\plan.html'
        $strWritten = Write-UpdatePlanFile -Path $strPath -Text 'caf'
        $strWritten | Should -Be $strPath
        $arrByte = [System.IO.File]::ReadAllBytes($strPath)
        $arrByte[0] | Should -Be 99
        $arrByte.Count | Should -Be 3
    }

    It 'appends one JSON line for each audit record' {
        $strPath = Join-Path -Path $TestDrive -ChildPath 'logs\actions.jsonl'
        Write-UpdatePlanAudit -Path $strPath -Record ([pscustomobject]@{ Action = 'DryRun'; PlanId = 'a' })
        Write-UpdatePlanAudit -Path $strPath -Record ([pscustomobject]@{ Action = 'Apply'; PlanId = 'a' })
        $arrLine = @(Get-Content -LiteralPath $strPath)
        $arrLine.Count | Should -Be 2
        ($arrLine[1] | ConvertFrom-Json).Action | Should -Be 'Apply'
    }
}

Describe 'ConvertTo-UpdatePlanResultRow' {
    It 'shows a skipped result of a dry run as a dry run row' {
        $arrResult = @([pscustomobject]@{ Wave = 'Wave 1 X'; CollectionId = 'ABC00001'; UpdateCount = 3; Status = 'Skipped'; AssignmentId = $null; Message = 'Not confirmed or WhatIf.' })
        $arrRow = @(ConvertTo-UpdatePlanResultRow -Result $arrResult -DryRun)
        $arrRow[0].Status | Should -Be 'Dry run'
        $arrRow[0].Message | Should -BeLike '*Nothing was created*'
        $arrRow[0].UpdateCount | Should -Be 3
    }

    It 'passes the results of a real run through unchanged' {
        $arrResult = @(
            [pscustomobject]@{ Wave = 'Wave 1 X'; CollectionId = 'ABC00001'; UpdateCount = 3; Status = 'Created'; AssignmentId = 16777549; Message = '' }
            [pscustomobject]@{ Wave = 'Wave 2 Y'; CollectionId = 'ABC00002'; UpdateCount = 1; Status = 'Failed'; AssignmentId = $null; Message = 'access denied' }
        )
        $arrRow = @(ConvertTo-UpdatePlanResultRow -Result $arrResult)
        $arrRow[0].Status | Should -Be 'Created'
        $arrRow[0].AssignmentId | Should -Be 16777549
        $arrRow[1].Status | Should -Be 'Failed'
        $arrRow[1].Message | Should -Be 'access denied'
    }

    It 'returns no row for an empty result list' {
        @(ConvertTo-UpdatePlanResultRow -Result @()).Count | Should -Be 0
    }
}
Describe 'Invoke-UpdatePlan built-in collection block' {
    It 'refuses a real apply to a built-in collection and creates nothing' {
        Mock -ModuleName UpdatePlannerCommon New-CimSession { }
        Mock -ModuleName UpdatePlannerCommon New-CimInstance { }
        $objPlan = New-WindowTestPlan
        $objPlan.Waves[0].CollectionId = 'SMS00001'
        { Invoke-UpdatePlan -Plan $objPlan -ComputerName 'cm01' -Apply -Confirm:$false } | Should -Throw '*built in*'
        Should -Invoke -ModuleName UpdatePlannerCommon New-CimInstance -Times 0 -Exactly
    }

    It 'still previews with -WhatIf for a built-in collection' {
        $objPlan = New-WindowTestPlan
        $objPlan.Waves[0].CollectionId = 'SMS00001'
        { Invoke-UpdatePlan -Plan $objPlan -ComputerName 'cm01' -Apply -WhatIf 6>$null } | Should -Not -Throw
    }
}
Describe 'Test-UpdatePlanApplyAllowed' {
    It 'allows a plan with updates for non built-in collections' {
        $objCheck = Test-UpdatePlanApplyAllowed -Plan (New-WindowTestPlan)
        $objCheck.IsAllowed | Should -BeTrue
        $objCheck.Reasons.Count | Should -Be 0
    }

    It 'blocks a wave that targets a built-in collection' {
        $objPlan = New-WindowTestPlan
        $objPlan.Waves[0].CollectionId = 'SMSDM003'
        $objCheck = Test-UpdatePlanApplyAllowed -Plan $objPlan
        $objCheck.IsAllowed | Should -BeFalse
        $objCheck.Reasons[0] | Should -BeLike '*built in*'
    }

    It 'blocks a plan that holds no update' {
        $objPlan = [pscustomobject]@{ Waves = @([pscustomobject]@{ Name = 'Wave 1 X'; CollectionId = 'ABC00001'; Updates = @() }) }
        $objCheck = Test-UpdatePlanApplyAllowed -Plan $objPlan
        $objCheck.IsAllowed | Should -BeFalse
        $objCheck.Reasons | Should -Contain 'The plan holds no update to deploy.'
    }
}
Describe 'Get-UpdatePlannerCollection' {
    It 'returns collections with their folder and the folder tree, from SELECT queries only' {
        Mock -ModuleName UpdatePlannerCommon New-CimSession { [System.Runtime.Serialization.FormatterServices]::GetUninitializedObject([Microsoft.Management.Infrastructure.CimSession]) }
        Mock -ModuleName UpdatePlannerCommon Remove-CimSession { }
        Mock -ModuleName UpdatePlannerCommon Invoke-UpCimQuery -ParameterFilter { $Query -like '*SMS_ProviderLocation*' } { [pscustomobject]@{ SiteCode = 'ABC' } }
        Mock -ModuleName UpdatePlannerCommon Invoke-UpCimQuery -ParameterFilter { $Query -like '*SMS_ObjectContainerItem*' } { [pscustomobject]@{ InstanceKey = 'ABC00010'; ContainerNodeID = 5 } }
        Mock -ModuleName UpdatePlannerCommon Invoke-UpCimQuery -ParameterFilter { $Query -like '*SMS_ObjectContainerNode*' } { [pscustomobject]@{ ContainerNodeID = 5; Name = 'Pilot rings'; ParentContainerNodeID = 0 } }
        Mock -ModuleName UpdatePlannerCommon Invoke-UpCimQuery -ParameterFilter { $Query -like '*FROM SMS_Collection*' } {
            [pscustomobject]@{ CollectionID = 'SMS00001'; Name = 'All Systems'; MemberCount = 12 }
            [pscustomobject]@{ CollectionID = 'ABC00010'; Name = 'Ring 0'; MemberCount = 3 }
        }
        $objList = Get-UpdatePlannerCollection -ComputerName 'cm01'
        $objList.SiteCode | Should -Be 'ABC'
        @($objList.Collections).Count | Should -Be 2
        $objRing = @($objList.Collections | Where-Object { $_.CollectionID -eq 'ABC00010' })[0]
        $objRing.FolderID | Should -Be 5
        $objRing.IsBuiltIn | Should -BeFalse
        @($objList.Collections | Where-Object { $_.CollectionID -eq 'SMS00001' })[0].IsBuiltIn | Should -BeTrue
        @($objList.Folders)[0].Name | Should -Be 'Pilot rings'
        Should -Invoke -ModuleName UpdatePlannerCommon Invoke-UpCimQuery -ParameterFilter { $Query -notlike 'SELECT *' } -Times 0 -Exactly
        Should -Invoke -ModuleName UpdatePlannerCommon Remove-CimSession -Times 1 -Exactly
    }
}

Describe 'Window files' {
    BeforeAll {
        $script:strXamlPath = Join-Path -Path $script:strRepositoryRoot -ChildPath 'MainWindow.xaml'
        $script:strStartPath = Join-Path -Path $script:strRepositoryRoot -ChildPath 'start-updateplanner.ps1'
    }

    It 'parses the window markup as XML' {
        { [xml](Get-Content -LiteralPath $script:strXamlPath -Raw) } | Should -Not -Throw
    }

    It 'has a control in the markup for every name the start script looks up' {
        $strXaml = Get-Content -LiteralPath $script:strXamlPath -Raw
        $arrDeclared = @([regex]::Matches($strXaml, 'x:Name="([A-Za-z0-9_]+)"') | ForEach-Object { $_.Groups[1].Value })
        $strStart = Get-Content -LiteralPath $script:strStartPath -Raw
        $arrLookup = @([regex]::Matches($strStart, "\`$window\.FindName\('([A-Za-z0-9_]+)'\)") | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
        $arrLookup.Count | Should -BeGreaterThan 20
        @($arrLookup | Where-Object { $arrDeclared -notcontains $_ }) | Should -BeNullOrEmpty
    }

    It 'declares every markup name only once' {
        $strXaml = Get-Content -LiteralPath $script:strXamlPath -Raw
        $arrDeclared = @([regex]::Matches($strXaml, 'x:Name="([A-Za-z0-9_]+)"') | ForEach-Object { $_.Groups[1].Value })
        @($arrDeclared | Group-Object | Where-Object { $_.Count -gt 1 }) | Should -BeNullOrEmpty
    }

    It 'parses the start script without error' {
        $arrError = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($script:strStartPath, [ref]$null, [ref]$arrError)
        $arrError.Count | Should -Be 0
    }

    It 'keeps the version equal in the manifest, the start script and the changelog' {
        $strManifestVersion = (Import-PowerShellDataFile -LiteralPath $script:strManifestPath).ModuleVersion
        (Get-Content -LiteralPath $script:strStartPath -Raw) | Should -Match ('(?m)^\s*Version\s*:\s*{0}\s*$' -f [regex]::Escape($strManifestVersion))
        (Get-Content -LiteralPath (Join-Path -Path $script:strRepositoryRoot -ChildPath 'CHANGELOG.md') -Raw) | Should -Match ('(?m)^## \[{0}\]' -f [regex]::Escape($strManifestVersion))
    }
}

Describe 'Module surface' {
    It 'exports the documented public functions' {
        $arrExported = @((Get-Module -Name UpdatePlannerCommon).ExportedFunctions.Keys | Sort-Object)
        $arrExported | Should -Be @(
            'ConvertTo-UpdatePlanHtml', 'ConvertTo-UpdatePlanJson', 'ConvertTo-UpdatePlanMarkdown', 'ConvertTo-UpdatePlanResultRow', 'ConvertTo-UpdatePlanRow',
            'ConvertTo-UpdatePlanSkippedRow', 'Export-UpdatePlan', 'Get-UpdatePlanDeploymentPreview', 'Get-UpdatePlannerCollection',
            'Get-UpdatePlannerState', 'Invoke-UpdatePlan', 'New-UpdatePlan', 'Resolve-UpdatePlannerSetting',
            'Test-UpdatePlanApplyAllowed', 'Write-UpdatePlanAudit', 'Write-UpdatePlanFile'
        )
    }

    It 'has help with an example on every public function' {
        foreach ($strName in (Get-Module -Name UpdatePlannerCommon).ExportedFunctions.Keys) {
            $objHelp = Get-Help -Name $strName -Full
            $objHelp.Synopsis | Should -Not -BeNullOrEmpty -Because $strName
            @($objHelp.examples.example).Count | Should -BeGreaterThan 0 -Because $strName
        }
    }
}
