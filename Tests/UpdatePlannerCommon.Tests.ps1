BeforeAll {
    $strTestsFolder = Split-Path -Path $PSCommandPath -Parent
    $strRepositoryRoot = Split-Path -Path $strTestsFolder -Parent
    $strSourceFolder = Join-Path -Path $strRepositoryRoot -ChildPath 'Module'
    $strManifestPath = Join-Path -Path $strSourceFolder -ChildPath 'UpdatePlannerCommon.psd1'
    Import-Module -Name $strManifestPath -Force

    function New-TestUpdate {
        param (
            [int]$CIId,
            [string]$ArticleId = '1000',
            [int]$Severity = 8,
            [bool]$IsExpired = $false,
            [bool]$IsSuperseded = $false,
            [int]$NumMissing = 1
        )
        [pscustomobject]@{
            CIId = $CIId
            ArticleId = $ArticleId
            Title = 'Update {0}' -f $CIId
            Severity = $Severity
            IsExpired = $IsExpired
            IsSuperseded = $IsSuperseded
            IsDeployed = $false
            NumMissing = $NumMissing
            NumPresent = 0
            NumTotal = 4
            DateRevised = [datetime]'2026-09-01'
        }
    }

    function New-TestState {
        $arrUpdate = @(
            (New-TestUpdate -CIId 1 -ArticleId '5001' -Severity 10 -NumMissing 3)
            (New-TestUpdate -CIId 2 -ArticleId '5002' -Severity 8 -NumMissing 5)
            (New-TestUpdate -CIId 3 -ArticleId '5003' -Severity 8 -NumMissing 2)
            (New-TestUpdate -CIId 4 -ArticleId '5004' -Severity 2 -NumMissing 1)
            (New-TestUpdate -CIId 5 -ArticleId '5005' -IsExpired $true -IsSuperseded $true -NumMissing 0)
            (New-TestUpdate -CIId 6 -ArticleId '5006' -IsSuperseded $true -NumMissing 2)
            (New-TestUpdate -CIId 7 -ArticleId '5007' -NumMissing 0)
        )
        [pscustomobject]@{
            ComputerName = 'CM01'
            SiteCode = 'ABC'
            Sync = $null
            Wsus = $null
            Updates = $arrUpdate
            Collections = @(
                [pscustomobject]@{
                    CollectionId = 'ABC00001'
                    Name = 'Pilot'
                    MemberCount = 2
                    MaintenanceWindowCount = 0
                    MaintenanceWindows = @()
                    NeededByUpdate = @{ '1' = 1; '2' = 2; '4' = 1 }
                }
                [pscustomobject]@{
                    CollectionId = 'ABC00002'
                    Name = 'Broad'
                    MemberCount = 10
                    MaintenanceWindowCount = 1
                    MaintenanceWindows = @([pscustomobject]@{ Description = 'Occurs every 1 weeks on Saturday'; WindowType = 4 })
                    NeededByUpdate = @{ '1' = 3; '2' = 5; '3' = 2; '4' = 1 }
                }
            )
            Deployments = @(
                [pscustomobject]@{
                    AssignmentId = 77
                    Name = 'Existing'
                    CollectionId = 'ABC00002'
                    AssignedCIds = @(4)
                    EnforcementDeadline = $null
                }
            )
            Summary = [pscustomobject]@{
                TotalUpdates = 7
                NeededUpdates = 5
                InstalledUpdates = 0
                SupersededUpdates = 2
                ExpiredUpdates = 1
                ExistingDeployments = 1
            }
        }
    }
}

Describe 'New-UpdatePlan' {
    BeforeAll {
        $script:objState = New-TestState
        $script:objPlan = New-UpdatePlan -State $script:objState -StartDate ([datetime]'2026-12-01') -WaveSpacingDays 7 -DeadlineDays 3
    }

    It 'creates one wave for each target collection, in order' {
        $arrWave = @($script:objPlan.Waves)
        $arrWave.Count | Should -Be 2
        $arrWave[0].CollectionId | Should -Be 'ABC00001'
        $arrWave[1].CollectionId | Should -Be 'ABC00002'
    }

    It 'sets start and deadline dates from the parameters' {
        $arrWave = @($script:objPlan.Waves)
        $arrWave.Count | Should -Be 2
        $arrWave[0].StartDate | Should -Be '2026-12-01'
        $arrWave[0].DeadlineDate | Should -Be '2026-12-04'
        $arrWave[1].StartDate | Should -Be '2026-12-08'
        $arrWave[1].DeadlineDate | Should -Be '2026-12-11'
    }

    It 'orders updates by severity, then by devices that need them' {
        $arrUpdate = @($script:objPlan.Waves[0].Updates)
        $arrUpdate.Count | Should -Be 3
        $arrUpdate[0].CIId | Should -Be 1
        $arrUpdate[1].CIId | Should -Be 2
        $arrUpdate[2].CIId | Should -Be 4
        $arrUpdate[0].Sequence | Should -Be 1
        $arrUpdate[2].Sequence | Should -Be 3
        $arrUpdate[0].SeverityName | Should -Be 'Critical'
    }

    It 'puts an update in a wave only when a device in the collection needs it' {
        $arrFirst = @($script:objPlan.Waves[0].Updates | ForEach-Object { $_.CIId })
        $arrFirst | Should -Not -Contain 3
        $arrSecond = @($script:objPlan.Waves[1].Updates | ForEach-Object { $_.CIId })
        $arrSecond | Should -Contain 3
    }

    It 'never plans expired, superseded or unneeded updates' {
        foreach ($objWave in $script:objPlan.Waves) {
            $arrIds = @($objWave.Updates | ForEach-Object { $_.CIId })
            $arrIds | Should -Not -Contain 5
            $arrIds | Should -Not -Contain 6
            $arrIds | Should -Not -Contain 7
        }
    }

    It 'lists a needed but superseded update as skipped' {
        $arrSkip = @($script:objPlan.Skipped | Where-Object { $_.CIId -eq 6 })
        $arrSkip.Count | Should -Be 1
        $arrSkip[0].Reason | Should -Be 'Superseded'
    }

    It 'skips an update that an existing deployment already targets at the collection' {
        $arrSecond = @($script:objPlan.Waves[1].Updates | ForEach-Object { $_.CIId })
        $arrSecond | Should -Not -Contain 4
        $arrSkip = @($script:objPlan.Skipped | Where-Object { $_.CIId -eq 4 -and $_.Reason -eq 'AlreadyDeployed' })
        $arrSkip.Count | Should -Be 1
        $arrSkip[0].Wave | Should -Be 'Wave 2 Broad'
    }

    It 'applies MinimumSeverity' {
        $objFiltered = New-UpdatePlan -State $script:objState -StartDate ([datetime]'2026-12-01') -MinimumSeverity 8
        $arrIds = @($objFiltered.Waves[0].Updates | ForEach-Object { $_.CIId })
        $arrIds | Should -Not -Contain 4
        $arrReason = @($objFiltered.Skipped | Where-Object { $_.CIId -eq 4 })
        $arrReason.Count | Should -Be 1
        $arrReason[0].Reason | Should -Be 'BelowMinimumSeverity'
    }

    It 'applies MaxUpdatesPerWave' {
        $objLimited = New-UpdatePlan -State $script:objState -StartDate ([datetime]'2026-12-01') -MaxUpdatesPerWave 1
        @($objLimited.Waves[0].Updates).Count | Should -Be 1
        $arrLimit = @($objLimited.Skipped | Where-Object { $_.Reason -eq 'WaveLimit' })
        $arrLimit.Count | Should -BeGreaterThan 0
    }

    It 'fills the summary counts' {
        $script:objPlan.Summary.WavesPlanned | Should -Be 2
        $script:objPlan.Summary.UpdateAssignmentsPlanned | Should -Be 6
        $script:objPlan.Summary.TotalUpdates | Should -Be 7
    }

    It 'returns waves with empty update lists when nothing is needed' {
        $objEmptyState = New-TestState
        foreach ($objCollection in $objEmptyState.Collections) {
            $objCollection.NeededByUpdate = @{}
        }
        $objEmpty = New-UpdatePlan -State $objEmptyState -StartDate ([datetime]'2026-12-01')
        $objEmpty.Summary.UpdateAssignmentsPlanned | Should -Be 0
        @($objEmpty.Waves).Count | Should -Be 2
    }

    It 'rejects a severity value that is not valid' {
        { New-UpdatePlan -State $script:objState -MinimumSeverity 5 } | Should -Throw
    }
}

Describe 'Export-UpdatePlan' {
    BeforeAll {
        $script:strOutputFolder = Join-Path -Path $TestDrive -ChildPath 'out'
        $script:objPlan = New-UpdatePlan -State (New-TestState) -StartDate ([datetime]'2026-12-01')
    }

    It 'writes a JSON file and a Markdown file without a byte order mark' {
        $strJson = Join-Path -Path $script:strOutputFolder -ChildPath 'plan.json'
        $objFile = Export-UpdatePlan -Plan $script:objPlan -Path $strJson
        Test-Path -LiteralPath $objFile.JsonPath | Should -BeTrue
        Test-Path -LiteralPath $objFile.MarkdownPath | Should -BeTrue
        $arrByte = [System.IO.File]::ReadAllBytes($objFile.JsonPath)
        $arrByte[0] | Should -Not -Be 0xEF
        $objRead = [System.IO.File]::ReadAllText($objFile.JsonPath) | ConvertFrom-Json
        $objRead.PlanId | Should -Be $script:objPlan.PlanId
        @($objRead.Waves).Count | Should -Be 2
    }

    It 'writes Markdown that states plan only mode and lists the waves' {
        $strJson = Join-Path -Path $script:strOutputFolder -ChildPath 'plan2.json'
        $objFile = Export-UpdatePlan -Plan $script:objPlan -Path $strJson
        $strMarkdown = [System.IO.File]::ReadAllText($objFile.MarkdownPath)
        $strMarkdown | Should -Match 'plan only'
        $strMarkdown | Should -Match '## Wave 1: Wave 1 Pilot'
        $strMarkdown | Should -Match 'KB5001'
        $strMarkdown | Should -Match 'Occurs every 1 weeks on Saturday'
    }

    It 'shows none for an update without an article ID' {
        $objState = New-TestState
        $objState.Updates[0].ArticleId = ''
        $objPlan = New-UpdatePlan -State $objState -StartDate ([datetime]'2026-12-01')
        $strJson = Join-Path -Path $script:strOutputFolder -ChildPath 'plan3.json'
        $objFile = Export-UpdatePlan -Plan $objPlan -Path $strJson
        $strMarkdown = [System.IO.File]::ReadAllText($objFile.MarkdownPath)
        $strMarkdown | Should -Match '\| 1 \| none \| Critical'
    }

    It 'writes nothing under -WhatIf' {
        $strJson = Join-Path -Path $script:strOutputFolder -ChildPath 'never.json'
        $objFile = Export-UpdatePlan -Plan $script:objPlan -Path $strJson -WhatIf
        $objFile | Should -BeNullOrEmpty
        Test-Path -LiteralPath $strJson | Should -BeFalse
    }
}

Describe 'Get-UpdatePlannerState' {
    BeforeAll {
        $script:strProvider = 'provider.test'
        Mock -ModuleName UpdatePlannerCommon New-CimSession { [System.Runtime.Serialization.FormatterServices]::GetUninitializedObject([Microsoft.Management.Infrastructure.CimSession]) }
        Mock -ModuleName UpdatePlannerCommon Remove-CimSession { }
        Mock -ModuleName UpdatePlannerCommon Invoke-UpCimQuery -ParameterFilter { $Query -like '*SMS_ProviderLocation*' } { [pscustomobject]@{ SiteCode = 'ABC' } }
        Mock -ModuleName UpdatePlannerCommon Invoke-UpCimQuery -ParameterFilter { $Query -like '*SMS_SUPSyncStatus*' } {
            [pscustomobject]@{ WSUSServerName = 'CM01'; WSUSSourceServer = 'Microsoft Update'; LastSuccessfulSyncTime = [datetime]'2026-11-05'; LastSyncErrorCode = 0 }
        }
        Mock -ModuleName UpdatePlannerCommon Invoke-UpCimQuery -ParameterFilter { $Query -like '*FROM SMS_SoftwareUpdate*' } {
            [pscustomobject]@{ CI_ID = 1; ArticleID = '5001'; LocalizedDisplayName = 'A'; Severity = 10; IsExpired = $false; IsSuperseded = $false; IsDeployed = $false; NumMissing = 2; NumPresent = 1; NumTotal = 3; DateRevised = [datetime]'2026-09-01' }
            [pscustomobject]@{ CI_ID = 2; ArticleID = '5002'; LocalizedDisplayName = 'B'; Severity = 8; IsExpired = $true; IsSuperseded = $true; IsDeployed = $false; NumMissing = 0; NumPresent = 0; NumTotal = 3; DateRevised = [datetime]'2026-09-01' }
        }
        Mock -ModuleName UpdatePlannerCommon Invoke-UpCimQuery -ParameterFilter { $Query -like '*SMS_UpdateComplianceStatus*' } {
            [pscustomobject]@{ MachineID = 100; CI_ID = 1 }
            [pscustomobject]@{ MachineID = 101; CI_ID = 1 }
            [pscustomobject]@{ MachineID = 999; CI_ID = 1 }
        }
        Mock -ModuleName UpdatePlannerCommon Invoke-UpCimQuery -ParameterFilter { $Query -like '*FROM SMS_Collection*' } {
            [pscustomobject]@{ CollectionID = 'ABC00001'; Name = 'Pilot'; CollectionType = 2; MemberCount = 2 }
        }
        Mock -ModuleName UpdatePlannerCommon Invoke-UpCimQuery -ParameterFilter { $Query -like '*SMS_FullCollectionMembership*' } {
            [pscustomobject]@{ ResourceID = 100 }
            [pscustomobject]@{ ResourceID = 101 }
        }
        Mock -ModuleName UpdatePlannerCommon Get-UpCollectionWindow { [pscustomobject]@{ Description = 'Occurs every 1 weeks on Saturday'; WindowType = 4 } }
        Mock -ModuleName UpdatePlannerCommon Invoke-UpCimQuery -ParameterFilter { $Query -like '*SMS_UpdatesAssignment*' } {
            [pscustomobject]@{ AssignmentID = 5; AssignmentName = 'X'; TargetCollectionID = 'ABC00001'; AssignedCIs = @(1); EnforcementDeadline = $null }
        }
    }

    It 'reads updates, counts and per-collection need' {
        $objState = Get-UpdatePlannerState -ComputerName $script:strProvider -TargetCollection 'Pilot'
        $objState.SiteCode | Should -Be 'ABC'
        $objState.Summary.TotalUpdates | Should -Be 2
        $objState.Summary.NeededUpdates | Should -Be 1
        $objState.Summary.ExpiredUpdates | Should -Be 1
        $objState.Summary.SupersededUpdates | Should -Be 1
        @($objState.Collections).Count | Should -Be 1
        $objState.Collections[0].NeededByUpdate['1'] | Should -Be 2
        $objState.Collections[0].MaintenanceWindowCount | Should -Be 1
        $objState.Collections[0].MaintenanceWindows[0].Description | Should -Be 'Occurs every 1 weeks on Saturday'
        @($objState.Deployments).Count | Should -Be 1
        $objState.Deployments[0].AssignedCIds | Should -Contain 1
    }

    It 'closes the CIM session' {
        [void](Get-UpdatePlannerState -ComputerName $script:strProvider -TargetCollection 'Pilot')
        Should -Invoke -ModuleName UpdatePlannerCommon Remove-CimSession -Times 1 -Scope It
    }

    It 'fails when a target collection is not found' {
        Mock -ModuleName UpdatePlannerCommon Invoke-UpCimQuery -ParameterFilter { $Query -like '*FROM SMS_Collection*' } { }
        { Get-UpdatePlannerState -ComputerName $script:strProvider -TargetCollection 'Missing' } | Should -Throw '*matched 0 collections*'
    }

    It 'fails when a target collection is a user collection' {
        Mock -ModuleName UpdatePlannerCommon Invoke-UpCimQuery -ParameterFilter { $Query -like '*FROM SMS_Collection*' } {
            [pscustomobject]@{ CollectionID = 'ABC00009'; Name = 'Users'; CollectionType = 1; MemberCount = 1 }
        }
        { Get-UpdatePlannerState -ComputerName $script:strProvider -TargetCollection 'Users' } | Should -Throw '*not a device collection*'
    }

    It 'warns and continues when WSUS is not reachable' {
        Mock -ModuleName UpdatePlannerCommon Invoke-Command { throw 'no remoting' }
        $objState = Get-UpdatePlannerState -ComputerName $script:strProvider -TargetCollection 'Pilot' -IncludeWsus -WarningVariable arrWarning -WarningAction SilentlyContinue
        $objState.Wsus | Should -BeNullOrEmpty
        @($arrWarning).Count | Should -Be 1
    }

    It 'never writes to the site' {
        Mock -ModuleName UpdatePlannerCommon New-CimInstance { }
        [void](Get-UpdatePlannerState -ComputerName $script:strProvider -TargetCollection 'Pilot')
        Should -Invoke -ModuleName UpdatePlannerCommon New-CimInstance -Times 0 -Scope It
    }
}

Describe 'Get-UpCollectionWindow' {
    It 'returns only windows of type 1 and 4' {
        InModuleScope UpdatePlannerCommon {
            Mock Invoke-UpCimQuery { [System.Runtime.Serialization.FormatterServices]::GetUninitializedObject([Microsoft.Management.Infrastructure.CimInstance]) }
            Mock Get-CimInstance {
                [pscustomobject]@{
                    ServiceWindows = @(
                        [pscustomobject]@{ Description = 'general'; ServiceWindowType = 1 }
                        [pscustomobject]@{ Description = 'updates'; ServiceWindowType = 4 }
                        [pscustomobject]@{ Description = 'osd'; ServiceWindowType = 5 }
                    )
                }
            }
            $objSession = [System.Runtime.Serialization.FormatterServices]::GetUninitializedObject([Microsoft.Management.Infrastructure.CimSession])
            $arrWindow = @(Get-UpCollectionWindow -CimSession $objSession -Namespace 'root\sms\site_ABC' -CollectionId 'ABC00001')
            $arrWindow.Count | Should -Be 2
            $arrWindow[1].Description | Should -Be 'updates'
        }
    }

    It 'returns nothing when the collection has no windows' {
        InModuleScope UpdatePlannerCommon {
            Mock Invoke-UpCimQuery { [System.Runtime.Serialization.FormatterServices]::GetUninitializedObject([Microsoft.Management.Infrastructure.CimInstance]) }
            Mock Get-CimInstance { [pscustomobject]@{ ServiceWindows = $null } }
            $objSession = [System.Runtime.Serialization.FormatterServices]::GetUninitializedObject([Microsoft.Management.Infrastructure.CimSession])
            $arrWindow = @(Get-UpCollectionWindow -CimSession $objSession -Namespace 'root\sms\site_ABC' -CollectionId 'ABC00001')
            $arrWindow.Count | Should -Be 0
        }
    }
}

Describe 'Invoke-UpdatePlan' {
    BeforeAll {
        $script:objPlan = New-UpdatePlan -State (New-TestState) -StartDate ([datetime]'2026-12-01')
        Mock -ModuleName UpdatePlannerCommon New-CimSession { [System.Runtime.Serialization.FormatterServices]::GetUninitializedObject([Microsoft.Management.Infrastructure.CimSession]) }
        Mock -ModuleName UpdatePlannerCommon Remove-CimSession { }
        Mock -ModuleName UpdatePlannerCommon New-CimInstance { [pscustomobject]@{ AssignmentID = 4242 } }
    }

    It 'changes nothing without -Apply' {
        $arrResult = @(Invoke-UpdatePlan -Plan $script:objPlan -WarningAction SilentlyContinue)
        $arrResult.Count | Should -Be 0
        Should -Invoke -ModuleName UpdatePlannerCommon New-CimInstance -Times 0 -Scope It
        Should -Invoke -ModuleName UpdatePlannerCommon New-CimSession -Times 0 -Scope It
    }

    It 'changes nothing with -Apply -WhatIf' {
        $arrResult = @(Invoke-UpdatePlan -Plan $script:objPlan -Apply -WhatIf)
        $arrResult.Count | Should -Be 2
        $arrResult[0].Status | Should -Be 'Skipped'
        Should -Invoke -ModuleName UpdatePlannerCommon New-CimInstance -Times 0 -Scope It
        Should -Invoke -ModuleName UpdatePlannerCommon New-CimSession -Times 0 -Scope It
    }

    It 'creates one deployment for each wave with -Apply' {
        $strPlanId = $script:objPlan.PlanId
        $arrResult = @(Invoke-UpdatePlan -Plan $script:objPlan -Apply -Confirm:$false)
        $arrResult.Count | Should -Be 2
        $arrResult[0].Status | Should -Be 'Created'
        $arrResult[0].AssignmentId | Should -Be 4242
        Should -Invoke -ModuleName UpdatePlannerCommon New-CimInstance -Times 2 -Exactly -Scope It -ParameterFilter {
            $ClassName -eq 'SMS_UpdatesAssignment' -and $Namespace -eq 'root\sms\site_ABC' -and $Property.AssignmentName -like ('UpdatePlanner {0} *' -f $strPlanId)
        }
    }

    It 'sets the collection, update IDs and dates from the wave' {
        [void](Invoke-UpdatePlan -Plan $script:objPlan -Apply -Confirm:$false)
        Should -Invoke -ModuleName UpdatePlannerCommon New-CimInstance -Times 1 -Exactly -Scope It -ParameterFilter {
            $Property.TargetCollectionID -eq 'ABC00001' -and $Property.AssignedCIs.Count -eq 3 -and $Property.EnforcementDeadline -eq [datetime]'2026-12-04'
        }
    }

    It 'reports a failure and continues with the next wave' {
        $script:intCall = 0
        Mock -ModuleName UpdatePlannerCommon New-CimInstance {
            $script:intCall++
            if ($script:intCall -eq 1) { throw 'provider error' }
            [pscustomobject]@{ AssignmentID = 9 }
        }
        $arrResult = @(Invoke-UpdatePlan -Plan $script:objPlan -Apply -Confirm:$false)
        $arrResult.Count | Should -Be 2
        $arrResult[0].Status | Should -Be 'Failed'
        $arrResult[0].Message | Should -Match 'provider error'
        $arrResult[1].Status | Should -Be 'Created'
    }

    It 'skips waves without updates' {
        $objEmptyState = New-TestState
        foreach ($objCollection in $objEmptyState.Collections) {
            $objCollection.NeededByUpdate = @{}
        }
        $objEmpty = New-UpdatePlan -State $objEmptyState -StartDate ([datetime]'2026-12-01')
        $arrResult = @(Invoke-UpdatePlan -Plan $objEmpty -Apply -Confirm:$false)
        $arrResult.Count | Should -Be 0
    }
}
