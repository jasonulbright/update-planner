# Logging and settings come from the vendored SuiteCommon copy. The guard keeps a
# -Force import of this module (the background runspace does one) from resetting
# SuiteCommon state during a session.
if (-not (Get-Module -Name SuiteCommon)) {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\Lib\SuiteCommon\SuiteCommon.psd1') -Global -DisableNameChecking
}

Set-StrictMode -Version Latest

#region Private helpers

function Invoke-UpCimQuery {
    # .SYNOPSIS
    # Runs one WQL query against the ConfigMgr SMS Provider and streams the results.
    #
    # .DESCRIPTION
    # Thin wrapper around Get-CimInstance. It exists so that tests can replace the
    # only point where the module reads from the site.
    #
    # .PARAMETER CimSession
    # The open CIM session to the SMS Provider computer.
    #
    # .PARAMETER Namespace
    # The WMI namespace, for example root\sms\site_ABC.
    #
    # .PARAMETER Query
    # The WQL query text.
    #
    # .EXAMPLE
    # $arrRows = @(Invoke-UpCimQuery -CimSession $objSession -Namespace 'root\sms\site_ABC' -Query 'SELECT * FROM SMS_Collection')
    #
    # # Returns zero or more CIM instances.
    #
    # .INPUTS
    # None. You can't pipe objects to this function.
    #
    # .OUTPUTS
    # [Microsoft.Management.Infrastructure.CimInstance] One object for each row.
    #
    # .NOTES
    # PRIVATE/INTERNAL HELPER. This function is not part of the public API surface.
    # Its parameters, return shape, and positional contract may change without notice.
    #
    # This function does not support positional parameters.
    #
    # Version: 1.0.20261105.0
    [CmdletBinding(PositionalBinding = $false)]
    [OutputType([Microsoft.Management.Infrastructure.CimInstance])]
    param (
        [Parameter(Mandatory = $true)]
        [object]$CimSession,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Namespace,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Query
    )

    process {
        Write-Debug -Message ('WQL: {0}' -f $Query)
        try {
            Get-CimInstance -CimSession $CimSession -Namespace $Namespace -Query $Query -ErrorAction Stop
        } catch {
            Write-Debug -Message ('WQL failed: {0}' -f $_.Exception.Message)
            throw
        }
    }
}

function Get-UpCollectionWindow {
    # .SYNOPSIS
    # Reads the maintenance windows that apply to software updates on one collection.
    #
    # .DESCRIPTION
    # Reads SMS_CollectionSettings for the collection and then reads the object again
    # with Get-CimInstance -InputObject, because the ServiceWindows property is a lazy
    # property that the first query does not return. Only windows of type 1 (all
    # deployments) and type 4 (software updates) are returned.
    #
    # .PARAMETER CimSession
    # The open CIM session to the SMS Provider computer.
    #
    # .PARAMETER Namespace
    # The WMI namespace, for example root\sms\site_ABC.
    #
    # .PARAMETER CollectionId
    # The collection ID.
    #
    # .EXAMPLE
    # $arrWindow = @(Get-UpCollectionWindow -CimSession $objSession -Namespace 'root\sms\site_ABC' -CollectionId 'ABC00001')
    #
    # # $arrWindow[0].Description = 'Occurs every 1 weeks on Saturday effective 8/15/2026 6:00 AM'
    #
    # .INPUTS
    # None. You can't pipe objects to this function.
    #
    # .OUTPUTS
    # [pscustomobject] One object for each window. Properties: Description, WindowType.
    #
    # .NOTES
    # PRIVATE/INTERNAL HELPER. This function is not part of the public API surface.
    # Its parameters, return shape, and positional contract may change without notice.
    #
    # This function does not support positional parameters.
    #
    # Version: 1.0.20261105.0
    [CmdletBinding(PositionalBinding = $false)]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory = $true)]
        [object]$CimSession,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Namespace,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$CollectionId
    )

    process {
        $strQuery = 'SELECT * FROM SMS_CollectionSettings WHERE CollectionID = ''{0}''' -f $CollectionId
        foreach ($objSetting in (Invoke-UpCimQuery -CimSession $CimSession -Namespace $Namespace -Query $strQuery)) {
            $objFull = Get-CimInstance -InputObject $objSetting -ErrorAction Stop
            foreach ($objWindow in @($objFull.ServiceWindows)) {
                if ($null -ne $objWindow -and ([int]$objWindow.ServiceWindowType -eq 1 -or [int]$objWindow.ServiceWindowType -eq 4)) {
                    [pscustomobject]@{
                        Description = [string]$objWindow.Description
                        WindowType = [int]$objWindow.ServiceWindowType
                    }
                }
            }
        }
    }
}

function ConvertTo-UpSeverityName {
    # .SYNOPSIS
    # Converts a ConfigMgr update severity number to its name.
    #
    # .DESCRIPTION
    # SMS_SoftwareUpdate stores severity as a number: 2 Low, 6 Moderate, 8 Important,
    # 10 Critical. Any other value maps to None.
    #
    # .PARAMETER Severity
    # The severity number.
    #
    # .EXAMPLE
    # $strName = ConvertTo-UpSeverityName -Severity 10
    #
    # # $strName = 'Critical'
    #
    # .INPUTS
    # None. You can't pipe objects to this function.
    #
    # .OUTPUTS
    # [string] One of Critical, Important, Moderate, Low, None.
    #
    # .NOTES
    # PRIVATE/INTERNAL HELPER. This function is not part of the public API surface.
    # Its parameters, return shape, and positional contract may change without notice.
    #
    # This function does not support positional parameters.
    #
    # Version: 1.0.20261105.0
    [CmdletBinding(PositionalBinding = $false)]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true)]
        [int]$Severity
    )

    process {
        switch ($Severity) {
            10 { 'Critical' }
            8 { 'Important' }
            6 { 'Moderate' }
            2 { 'Low' }
            default { 'None' }
        }
    }
}

function ConvertTo-UpMarkdown {
    # .SYNOPSIS
    # Renders an update plan as a Markdown review document.
    #
    # .DESCRIPTION
    # Builds one text for a human reviewer: summary counts, one table for each wave,
    # and one table of the skipped updates with the reason for each.
    #
    # .PARAMETER Plan
    # The plan object that New-UpdatePlan returns.
    #
    # .EXAMPLE
    # $strText = ConvertTo-UpMarkdown -Plan $objPlan
    #
    # # $strText holds the Markdown text.
    #
    # .INPUTS
    # None. You can't pipe objects to this function.
    #
    # .OUTPUTS
    # [string] The Markdown text.
    #
    # .NOTES
    # PRIVATE/INTERNAL HELPER. This function is not part of the public API surface.
    # Its parameters, return shape, and positional contract may change without notice.
    #
    # This function does not support positional parameters.
    #
    # Version: 1.0.20261105.0
    [CmdletBinding(PositionalBinding = $false)]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Plan
    )

    process {
        $listLine = New-Object -TypeName 'System.Collections.Generic.List[string]'
        $listLine.Add('# Update plan')
        $listLine.Add('')
        $listLine.Add(('Plan ID: {0}' -f $Plan.PlanId))
        $listLine.Add(('Generated: {0}' -f $Plan.GeneratedAt))
        $listLine.Add(('Site: {0} on {1}' -f $Plan.SiteCode, $Plan.ComputerName))
        $listLine.Add('Mode: plan only. This file changes nothing on the site.')
        $listLine.Add('')
        $listLine.Add('## Site state')
        $listLine.Add('')
        foreach ($objProperty in $Plan.Summary.PSObject.Properties) {
            $listLine.Add(('- {0}: {1}' -f $objProperty.Name, $objProperty.Value))
        }
        if ($null -ne $Plan.Sync) {
            $listLine.Add(('- Last successful WSUS synchronization: {0} (error code {1}, source {2})' -f $Plan.Sync.LastSuccessfulSyncTime, $Plan.Sync.LastSyncErrorCode, $Plan.Sync.Source))
        }
        if ($null -ne $Plan.Wsus) {
            $listLine.Add(('- WSUS: {0} updates, {1} approved, {2} declined, {3} expired, {4} computers' -f $Plan.Wsus.UpdateCount, $Plan.Wsus.ApprovedUpdateCount, $Plan.Wsus.DeclinedUpdateCount, $Plan.Wsus.ExpiredUpdateCount, $Plan.Wsus.ComputerTargetCount))
        }
        $listLine.Add('')
        foreach ($objWave in $Plan.Waves) {
            $listLine.Add(('## Wave {0}: {1}' -f $objWave.Order, $objWave.Name))
            $listLine.Add('')
            $strDeviceNoun = if ([int]$objWave.MemberCount -eq 1) { 'device' } else { 'devices' }
            $listLine.Add(('- Collection: {0} ({1}), {2} {3}' -f $objWave.CollectionName, $objWave.CollectionId, $objWave.MemberCount, $strDeviceNoun))
            $listLine.Add(('- Start: {0}' -f $objWave.StartDate))
            $listLine.Add(('- Deadline: {0}' -f $objWave.DeadlineDate))
            $listLine.Add(('- Maintenance windows on the collection: {0}' -f $objWave.MaintenanceWindowCount))
            foreach ($strWindow in @($objWave.MaintenanceWindows)) {
                $listLine.Add(('  - {0}' -f $strWindow))
            }
            if ($objWave.MaintenanceWindowCount -gt 0) {
                $listLine.Add('- Review: the planner does not move the deadline into a window. Check the deadline against these windows.')
            }
            $listLine.Add(('- Updates in this wave: {0}' -f @($objWave.Updates).Count))
            $listLine.Add('')
            if (@($objWave.Updates).Count -gt 0) {
                $listLine.Add('| Seq | Article | Severity | Devices that need it | Title |')
                $listLine.Add('|---|---|---|---|---|')
                foreach ($objUpdate in $objWave.Updates) {
                    $strArticle = if ([string]::IsNullOrEmpty($objUpdate.ArticleId)) { 'none' } else { 'KB{0}' -f $objUpdate.ArticleId }
                    $listLine.Add(('| {0} | {1} | {2} | {3} | {4} |' -f $objUpdate.Sequence, $strArticle, $objUpdate.SeverityName, $objUpdate.NeededDevices, $objUpdate.Title))
                }
                $listLine.Add('')
            }
        }
        $listLine.Add('## Skipped updates')
        $listLine.Add('')
        if (@($Plan.Skipped).Count -eq 0) {
            $listLine.Add('None.')
        } else {
            $listLine.Add('| Reason | Wave | Article | Title |')
            $listLine.Add('|---|---|---|---|')
            foreach ($objSkip in $Plan.Skipped) {
                $strArticle = if ([string]::IsNullOrEmpty($objSkip.ArticleId)) { 'none' } else { 'KB{0}' -f $objSkip.ArticleId }
                $listLine.Add(('| {0} | {1} | {2} | {3} |' -f $objSkip.Reason, $objSkip.Wave, $strArticle, $objSkip.Title))
            }
        }
        $listLine.Add('')
        $listLine -join [System.Environment]::NewLine
    }
}

function Write-UpTextFile {
    # .SYNOPSIS
    # Writes a text file as UTF-8 without a byte order mark.
    #
    # .DESCRIPTION
    # Resolves the path to an absolute path, creates the parent folder when it is
    # missing, and writes the text with the .NET file API so that Windows PowerShell
    # 5.1 and PowerShell 7 write the same bytes.
    #
    # .PARAMETER Path
    # The target file path.
    #
    # .PARAMETER Text
    # The text to write.
    #
    # .EXAMPLE
    # $strFullPath = Write-UpTextFile -Path '.\plan.json' -Text '{}'
    #
    # # $strFullPath = 'C:\work\plan.json'
    #
    # .INPUTS
    # None. You can't pipe objects to this function.
    #
    # .OUTPUTS
    # [string] The absolute path of the file that was written.
    #
    # .NOTES
    # PRIVATE/INTERNAL HELPER. This function is not part of the public API surface.
    # Its parameters, return shape, and positional contract may change without notice.
    #
    # This function does not support positional parameters.
    #
    # Version: 1.0.20261105.0
    [CmdletBinding(PositionalBinding = $false)]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Text
    )

    process {
        $strFullPath = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($Path)
        $strFolder = [System.IO.Path]::GetDirectoryName($strFullPath)
        [void][System.IO.Directory]::CreateDirectory($strFolder)
        $objEncoding = New-Object -TypeName 'System.Text.UTF8Encoding' -ArgumentList $false
        [System.IO.File]::WriteAllText($strFullPath, $Text, $objEncoding)
        $strFullPath
    }
}

#endregion Private helpers

#region Public functions

function Get-UpdatePlannerState {
    # .SYNOPSIS
    # Reads the software update state of a ConfigMgr site. Read only.
    #
    # .DESCRIPTION
    # Connects to the SMS Provider with a CIM session and reads: the update catalog
    # (needed, installed, superseded and expired counts), the last WSUS synchronization,
    # the target device collections with their members and maintenance windows, the
    # devices that need each update in each target collection, and the existing
    # update deployments. With -IncludeWsus it also reads update counts from the
    # WSUS server through PowerShell remoting. The function changes nothing.
    #
    # .PARAMETER ComputerName
    # The computer that runs the SMS Provider. The default is the local computer.
    #
    # .PARAMETER Credential
    # An optional credential for the CIM session and for WSUS remoting.
    #
    # .PARAMETER SiteCode
    # The site code. When omitted, the function reads it from the SMS Provider.
    #
    # .PARAMETER TargetCollection
    # The device collections that receive updates, as names or collection IDs.
    # The order of this list is the order of the waves.
    #
    # .PARAMETER IncludeWsus
    # Also reads update counts from the WSUS server with Get-WsusServer on the
    # provider computer. A failure here is a warning, not an error.
    #
    # .EXAMPLE
    # $objState = Get-UpdatePlannerState -ComputerName 'CM01' -Credential $objCredential -TargetCollection 'Pilot','Broad'
    #
    # # $objState.Summary.NeededUpdates = 5
    #
    # .INPUTS
    # None. You can't pipe objects to this function.
    #
    # .OUTPUTS
    # [pscustomobject] The site state. Properties: ComputerName, SiteCode, Sync, Wsus,
    # Updates, Collections, Deployments, Summary.
    #
    # .NOTES
    # This function does not support positional parameters.
    #
    # Version: 1.0.20261105.0
    [CmdletBinding(PositionalBinding = $false)]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$ComputerName = $env:COMPUTERNAME,

        [Parameter(Mandatory = $false)]
        [System.Management.Automation.PSCredential]$Credential,

        [Parameter(Mandatory = $false)]
        [ValidatePattern('^[A-Za-z0-9]{3}$')]
        [string]$SiteCode,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$TargetCollection,

        [Parameter(Mandatory = $false)]
        [switch]$IncludeWsus
    )

    process {
        $objSession = $null
        try {
            $hashtableSession = @{ ComputerName = $ComputerName; ErrorAction = 'Stop' }
            if ($PSBoundParameters.ContainsKey('Credential')) {
                $hashtableSession['Credential'] = $Credential
            }
            Write-Verbose -Message ('Opening CIM session to {0}' -f $ComputerName)
            $objSession = New-CimSession @hashtableSession

            if ([string]::IsNullOrEmpty($SiteCode)) {
                $arrLocation = @(Invoke-UpCimQuery -CimSession $objSession -Namespace 'root\sms' -Query 'SELECT SiteCode FROM SMS_ProviderLocation WHERE ProviderForLocalSite = TRUE')
                if ($arrLocation.Count -lt 1) {
                    throw 'The SMS Provider reports no local site code.'
                }
                $SiteCode = [string]$arrLocation[0].SiteCode
            }
            $strNamespace = 'root\sms\site_{0}' -f $SiteCode

            $objSyncRow = Invoke-UpCimQuery -CimSession $objSession -Namespace $strNamespace -Query 'SELECT * FROM SMS_SUPSyncStatus' | Select-Object -First 1
            $objSync = $null
            if ($null -ne $objSyncRow) {
                $objSync = [pscustomobject]@{
                    WsusServerName = [string]$objSyncRow.WSUSServerName
                    Source = [string]$objSyncRow.WSUSSourceServer
                    LastSuccessfulSyncTime = $objSyncRow.LastSuccessfulSyncTime
                    LastSyncErrorCode = $objSyncRow.LastSyncErrorCode
                }
            }

            $listUpdate = New-Object -TypeName 'System.Collections.Generic.List[pscustomobject]'
            $strUpdateQuery = 'SELECT CI_ID, ArticleID, LocalizedDisplayName, Severity, IsExpired, IsSuperseded, IsDeployed, NumMissing, NumPresent, NumTotal, DateRevised FROM SMS_SoftwareUpdate'
            foreach ($objRow in (Invoke-UpCimQuery -CimSession $objSession -Namespace $strNamespace -Query $strUpdateQuery)) {
                $listUpdate.Add([pscustomobject]@{
                        CIId = [int]$objRow.CI_ID
                        ArticleId = [string]$objRow.ArticleID
                        Title = [string]$objRow.LocalizedDisplayName
                        Severity = [int]$objRow.Severity
                        IsExpired = [bool]$objRow.IsExpired
                        IsSuperseded = [bool]$objRow.IsSuperseded
                        IsDeployed = [bool]$objRow.IsDeployed
                        NumMissing = [int]$objRow.NumMissing
                        NumPresent = [int]$objRow.NumPresent
                        NumTotal = [int]$objRow.NumTotal
                        DateRevised = $objRow.DateRevised
                    })
            }

            # Status 2 means "update is required" on a device.
            $hashtableRequired = @{}
            foreach ($objRow in (Invoke-UpCimQuery -CimSession $objSession -Namespace $strNamespace -Query 'SELECT MachineID, CI_ID FROM SMS_UpdateComplianceStatus WHERE Status = 2')) {
                $strKey = [string]$objRow.CI_ID
                if (-not $hashtableRequired.ContainsKey($strKey)) {
                    $hashtableRequired[$strKey] = New-Object -TypeName 'System.Collections.Generic.HashSet[int]'
                }
                [void]$hashtableRequired[$strKey].Add([int]$objRow.MachineID)
            }

            $listCollection = New-Object -TypeName 'System.Collections.Generic.List[pscustomobject]'
            foreach ($strTarget in $TargetCollection) {
                $strEscaped = $strTarget.Replace('\', '\\').Replace("'", "''")
                $arrFound = @()
                if ($strTarget -match '^[A-Za-z0-9]{8}$') {
                    $arrFound = @(Invoke-UpCimQuery -CimSession $objSession -Namespace $strNamespace -Query ("SELECT CollectionID, Name, CollectionType, MemberCount FROM SMS_Collection WHERE CollectionID = '{0}'" -f $strEscaped))
                }
                if ($arrFound.Count -eq 0) {
                    $arrFound = @(Invoke-UpCimQuery -CimSession $objSession -Namespace $strNamespace -Query ("SELECT CollectionID, Name, CollectionType, MemberCount FROM SMS_Collection WHERE Name = '{0}'" -f $strEscaped))
                }
                if ($arrFound.Count -ne 1) {
                    throw ('Target collection "{0}" matched {1} collections. It must match exactly one.' -f $strTarget, $arrFound.Count)
                }
                $objFound = $arrFound[0]
                if ([int]$objFound.CollectionType -ne 2) {
                    throw ('Target collection "{0}" is not a device collection.' -f $strTarget)
                }
                $strCollectionId = [string]$objFound.CollectionID
                $hashtableMember = New-Object -TypeName 'System.Collections.Generic.HashSet[int]'
                foreach ($objMember in (Invoke-UpCimQuery -CimSession $objSession -Namespace $strNamespace -Query ('SELECT ResourceID FROM SMS_FullCollectionMembership WHERE CollectionID = ''{0}''' -f $strCollectionId))) {
                    [void]$hashtableMember.Add([int]$objMember.ResourceID)
                }
                $hashtableNeeded = @{}
                foreach ($strKey in $hashtableRequired.Keys) {
                    $intCount = 0
                    foreach ($intResource in $hashtableRequired[$strKey]) {
                        if ($hashtableMember.Contains($intResource)) {
                            $intCount++
                        }
                    }
                    if ($intCount -gt 0) {
                        $hashtableNeeded[$strKey] = $intCount
                    }
                }
                $arrWindow = @(Get-UpCollectionWindow -CimSession $objSession -Namespace $strNamespace -CollectionId $strCollectionId)
                $listCollection.Add([pscustomobject]@{
                        CollectionId = $strCollectionId
                        Name = [string]$objFound.Name
                        MemberCount = $hashtableMember.Count
                        MaintenanceWindowCount = $arrWindow.Count
                        MaintenanceWindows = $arrWindow
                        NeededByUpdate = $hashtableNeeded
                    })
            }

            $listDeployment = New-Object -TypeName 'System.Collections.Generic.List[pscustomobject]'
            foreach ($objRow in (Invoke-UpCimQuery -CimSession $objSession -Namespace $strNamespace -Query 'SELECT AssignmentID, AssignmentName, TargetCollectionID, AssignedCIs, EnforcementDeadline FROM SMS_UpdatesAssignment')) {
                $listDeployment.Add([pscustomobject]@{
                        AssignmentId = [int]$objRow.AssignmentID
                        Name = [string]$objRow.AssignmentName
                        CollectionId = [string]$objRow.TargetCollectionID
                        AssignedCIds = @($objRow.AssignedCIs | ForEach-Object { [int]$_ })
                        EnforcementDeadline = $objRow.EnforcementDeadline
                    })
            }

            $objWsus = $null
            if ($IncludeWsus) {
                try {
                    $hashtableRemote = @{ ComputerName = $ComputerName; ErrorAction = 'Stop' }
                    if ($PSBoundParameters.ContainsKey('Credential')) {
                        $hashtableRemote['Credential'] = $Credential
                    }
                    $objWsus = Invoke-Command @hashtableRemote -ScriptBlock {
                        $objServer = Get-WsusServer -Name 'localhost' -PortNumber 8530
                        $objStatus = $objServer.GetStatus()
                        [pscustomobject]@{
                            UpdateCount = $objStatus.UpdateCount
                            ApprovedUpdateCount = $objStatus.ApprovedUpdateCount
                            DeclinedUpdateCount = $objStatus.DeclinedUpdateCount
                            ExpiredUpdateCount = $objStatus.ExpiredUpdateCount
                            ComputerTargetCount = $objStatus.ComputerTargetCount
                        }
                    }
                } catch {
                    Write-Warning -Message ('WSUS state is not available: {0}' -f $_.Exception.Message)
                }
            }

            $intExpired = 0
            $intSuperseded = 0
            $intNeeded = 0
            $intInstalledSomewhere = 0
            foreach ($objUpdate in $listUpdate) {
                if ($objUpdate.IsExpired) { $intExpired++ }
                if ($objUpdate.IsSuperseded) { $intSuperseded++ }
                if ($objUpdate.NumMissing -gt 0) { $intNeeded++ }
                if ($objUpdate.NumPresent -gt 0) { $intInstalledSomewhere++ }
            }
            [pscustomobject]@{
                ComputerName = $ComputerName
                SiteCode = $SiteCode
                Sync = $objSync
                Wsus = $objWsus
                Updates = $listUpdate.ToArray()
                Collections = $listCollection.ToArray()
                Deployments = $listDeployment.ToArray()
                Summary = [pscustomobject]@{
                    TotalUpdates = $listUpdate.Count
                    NeededUpdates = $intNeeded
                    InstalledUpdates = $intInstalledSomewhere
                    SupersededUpdates = $intSuperseded
                    ExpiredUpdates = $intExpired
                    ExistingDeployments = $listDeployment.Count
                }
            }
        } catch {
            Write-Debug -Message ('Get-UpdatePlannerState failed: {0}' -f $_.Exception.Message)
            throw
        } finally {
            if ($null -ne $objSession) {
                Remove-CimSession -CimSession $objSession -ErrorAction SilentlyContinue
            }
        }
    }
}

function New-UpdatePlan {
    # .SYNOPSIS
    # Builds an update plan from a site state. Pure computation, no site access.
    #
    # .DESCRIPTION
    # Takes the state from Get-UpdatePlannerState and decides which updates go to
    # which collection, in which order, in which wave, and on which dates.
    #
    # Rules:
    # 1. An expired update is skipped (Expired).
    # 2. A superseded update is skipped (Superseded).
    # 3. An update that no device needs is skipped (NotNeeded).
    # 4. One wave exists for each target collection, in the order given. Wave n
    #    starts StartDate + (n - 1) * WaveSpacingDays. The deadline is the start
    #    plus DeadlineDays.
    # 5. A wave holds the remaining updates that at least one device in its
    #    collection needs. Others are skipped for that wave (NotNeededInCollection).
    # 6. An update that an existing deployment already targets at the collection is
    #    skipped for that wave (AlreadyDeployed).
    # 7. Updates below MinimumSeverity are skipped (BelowMinimumSeverity).
    # 8. Order inside a wave: severity high to low, then devices that need the
    #    update high to low, then article ID, then CI ID.
    # 9. A wave holds at most MaxUpdatesPerWave updates. The rest are skipped
    #    (WaveLimit).
    #
    # .PARAMETER State
    # The object that Get-UpdatePlannerState returns.
    #
    # .PARAMETER StartDate
    # The start date of the first wave. The default is tomorrow.
    #
    # .PARAMETER WaveSpacingDays
    # Days between wave start dates. The default is 7.
    #
    # .PARAMETER DeadlineDays
    # Days from the start of a wave to its deadline. The default is 3.
    #
    # .PARAMETER MinimumSeverity
    # The lowest severity number to plan: 0 all, 2 Low, 6 Moderate, 8 Important,
    # 10 Critical. The default is 0.
    #
    # .PARAMETER MaxUpdatesPerWave
    # The most updates in one wave. The default is 1000, the ConfigMgr limit for
    # one software update group.
    #
    # .EXAMPLE
    # $objPlan = New-UpdatePlan -State $objState -StartDate ([datetime]'2026-12-01')
    #
    # # $objPlan.Waves[0].StartDate = '2026-12-01'
    #
    # .INPUTS
    # None. You can't pipe objects to this function.
    #
    # .OUTPUTS
    # [pscustomobject] The plan. Properties: PlanId, GeneratedAt, ComputerName,
    # SiteCode, Parameters, Summary, Waves, Skipped.
    #
    # .NOTES
    # This function does not support positional parameters.
    #
    # Version: 1.0.20261105.0
    [CmdletBinding(PositionalBinding = $false)]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory = $true)]
        [pscustomobject]$State,

        [Parameter(Mandatory = $false)]
        [datetime]$StartDate = (Get-Date).Date.AddDays(1),

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 365)]
        [int]$WaveSpacingDays = 7,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 365)]
        [int]$DeadlineDays = 3,

        [Parameter(Mandatory = $false)]
        [ValidateSet(0, 2, 6, 8, 10)]
        [int]$MinimumSeverity = 0,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 1000)]
        [int]$MaxUpdatesPerWave = 1000
    )

    process {
        $listSkipped = New-Object -TypeName 'System.Collections.Generic.List[pscustomobject]'
        $listCandidate = New-Object -TypeName 'System.Collections.Generic.List[pscustomobject]'
        $intTotalSkippedGlobal = 0

        foreach ($objUpdate in $State.Updates) {
            $strReason = $null
            if ($objUpdate.IsExpired) {
                $strReason = 'Expired'
            } elseif ($objUpdate.IsSuperseded) {
                $strReason = 'Superseded'
            } elseif ($objUpdate.NumMissing -le 0) {
                $strReason = 'NotNeeded'
            } elseif ($objUpdate.Severity -lt $MinimumSeverity) {
                $strReason = 'BelowMinimumSeverity'
            }
            if ($null -ne $strReason) {
                $intTotalSkippedGlobal++
                # Only report updates that could matter. Unneeded and expired catalog
                # entries are counted in the summary but not listed one by one.
                if (($strReason -eq 'Superseded' -and $objUpdate.NumMissing -gt 0) -or $strReason -eq 'BelowMinimumSeverity') {
                    $listSkipped.Add([pscustomobject]@{
                            Reason = $strReason
                            Wave = ''
                            CIId = $objUpdate.CIId
                            ArticleId = $objUpdate.ArticleId
                            Title = $objUpdate.Title
                        })
                }
            } else {
                $listCandidate.Add($objUpdate)
            }
        }

        $arrOrdered = @($listCandidate | Sort-Object -Property @{ Expression = 'Severity'; Descending = $true }, @{ Expression = 'NumMissing'; Descending = $true }, 'ArticleId', 'CIId')

        $listWave = New-Object -TypeName 'System.Collections.Generic.List[pscustomobject]'
        $intWaveNumber = 0
        $intPlannedTotal = 0
        foreach ($objCollection in $State.Collections) {
            $intWaveNumber++
            $datetimeStart = $StartDate.Date.AddDays(($intWaveNumber - 1) * $WaveSpacingDays)
            $datetimeDeadline = $datetimeStart.AddDays($DeadlineDays)
            $setDeployedHere = New-Object -TypeName 'System.Collections.Generic.HashSet[int]'
            foreach ($objDeployment in $State.Deployments) {
                if ($objDeployment.CollectionId -eq $objCollection.CollectionId) {
                    foreach ($intAssigned in @($objDeployment.AssignedCIds)) {
                        [void]$setDeployedHere.Add([int]$intAssigned)
                    }
                }
            }
            $strWaveName = 'Wave {0} {1}' -f $intWaveNumber, $objCollection.Name
            $listWaveUpdate = New-Object -TypeName 'System.Collections.Generic.List[pscustomobject]'
            foreach ($objUpdate in $arrOrdered) {
                $strKey = [string]$objUpdate.CIId
                $intDevices = 0
                if ($objCollection.NeededByUpdate.ContainsKey($strKey)) {
                    $intDevices = [int]$objCollection.NeededByUpdate[$strKey]
                }
                $strReason = $null
                if ($intDevices -le 0) {
                    $strReason = 'NotNeededInCollection'
                } elseif ($setDeployedHere.Contains([int]$objUpdate.CIId)) {
                    $strReason = 'AlreadyDeployed'
                } elseif ($listWaveUpdate.Count -ge $MaxUpdatesPerWave) {
                    $strReason = 'WaveLimit'
                }
                if ($null -ne $strReason) {
                    # NotNeededInCollection is the normal case for most of the catalog.
                    # It is counted on the wave, not listed.
                    if ($strReason -ne 'NotNeededInCollection') {
                        $listSkipped.Add([pscustomobject]@{
                                Reason = $strReason
                                Wave = $strWaveName
                                CIId = $objUpdate.CIId
                                ArticleId = $objUpdate.ArticleId
                                Title = $objUpdate.Title
                            })
                    }
                    continue
                }
                $listWaveUpdate.Add([pscustomobject]@{
                        Sequence = $listWaveUpdate.Count + 1
                        CIId = $objUpdate.CIId
                        ArticleId = $objUpdate.ArticleId
                        Title = $objUpdate.Title
                        Severity = $objUpdate.Severity
                        SeverityName = ConvertTo-UpSeverityName -Severity $objUpdate.Severity
                        NeededDevices = $intDevices
                    })
            }
            $intPlannedTotal += $listWaveUpdate.Count
            $listWave.Add([pscustomobject]@{
                    Order = $intWaveNumber
                    Name = $strWaveName
                    CollectionId = $objCollection.CollectionId
                    CollectionName = $objCollection.Name
                    MemberCount = $objCollection.MemberCount
                    MaintenanceWindowCount = $objCollection.MaintenanceWindowCount
                    MaintenanceWindows = @($objCollection.MaintenanceWindows | ForEach-Object { $_.Description })
                    StartDate = $datetimeStart.ToString('yyyy-MM-dd')
                    DeadlineDate = $datetimeDeadline.ToString('yyyy-MM-dd')
                    Updates = $listWaveUpdate.ToArray()
                })
        }

        [pscustomobject]@{
            PlanId = [guid]::NewGuid().ToString('N').Substring(0, 8)
            GeneratedAt = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
            ComputerName = $State.ComputerName
            SiteCode = $State.SiteCode
            Parameters = [pscustomobject]@{
                StartDate = $StartDate.ToString('yyyy-MM-dd')
                WaveSpacingDays = $WaveSpacingDays
                DeadlineDays = $DeadlineDays
                MinimumSeverity = $MinimumSeverity
                MaxUpdatesPerWave = $MaxUpdatesPerWave
            }
            Summary = [pscustomobject]@{
                TotalUpdates = $State.Summary.TotalUpdates
                NeededUpdates = $State.Summary.NeededUpdates
                InstalledUpdates = $State.Summary.InstalledUpdates
                SupersededUpdates = $State.Summary.SupersededUpdates
                ExpiredUpdates = $State.Summary.ExpiredUpdates
                ExistingDeployments = $State.Summary.ExistingDeployments
                UpdatesNotCandidates = $intTotalSkippedGlobal
                WavesPlanned = $listWave.Count
                UpdateAssignmentsPlanned = $intPlannedTotal
                SkippedListed = $listSkipped.Count
            }
            Sync = $State.Sync
            Wsus = $State.Wsus
            Waves = $listWave.ToArray()
            Skipped = $listSkipped.ToArray()
        }
    }
}

function Export-UpdatePlan {
    # .SYNOPSIS
    # Writes an update plan to a JSON file and a Markdown review file.
    #
    # .DESCRIPTION
    # Writes the plan as JSON (the file that Invoke-UpdatePlan reads) and as Markdown
    # (the file a person reviews). Both files use UTF-8 without a byte order mark.
    # The function only writes the two files. It does not touch the site.
    #
    # .PARAMETER Plan
    # The plan that New-UpdatePlan returns.
    #
    # .PARAMETER Path
    # The path of the JSON file. The Markdown file gets the same name with the
    # extension .md.
    #
    # .EXAMPLE
    # $objFile = Export-UpdatePlan -Plan $objPlan -Path 'C:\plans\plan.json'
    #
    # # $objFile.JsonPath = 'C:\plans\plan.json'
    #
    # .INPUTS
    # None. You can't pipe objects to this function.
    #
    # .OUTPUTS
    # [pscustomobject] Properties JsonPath and MarkdownPath, the absolute paths written.
    #
    # .NOTES
    # This function does not support positional parameters.
    #
    # Version: 1.0.20261105.0
    [CmdletBinding(PositionalBinding = $false, SupportsShouldProcess = $true)]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Plan,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    process {
        $strJsonPath = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($Path)
        $strMarkdownPath = [System.IO.Path]::ChangeExtension($strJsonPath, '.md')
        if (-not $PSCmdlet.ShouldProcess($strJsonPath, 'Write update plan files')) {
            return
        }
        try {
            $strJson = $Plan | ConvertTo-Json -Depth 8
            [void](Write-UpTextFile -Path $strJsonPath -Text $strJson)
            [void](Write-UpTextFile -Path $strMarkdownPath -Text (ConvertTo-UpMarkdown -Plan $Plan))
        } catch {
            Write-Debug -Message ('Export-UpdatePlan failed: {0}' -f $_.Exception.Message)
            throw
        }
        [pscustomobject]@{
            JsonPath = $strJsonPath
            MarkdownPath = $strMarkdownPath
        }
    }
}

function Invoke-UpdatePlan {
    # .SYNOPSIS
    # Applies an update plan to the site. Needs the explicit -Apply switch.
    #
    # .DESCRIPTION
    # Without -Apply the function changes nothing and writes a warning. With -Apply
    # it creates one software update deployment (SMS_UpdatesAssignment) for each
    # wave that holds updates, targeted at the wave collection, with the planned
    # start time and deadline. Each deployment is named "UpdatePlanner <PlanId>
    # <wave name>". The function supports -WhatIf and asks for confirmation before
    # each deployment (ConfirmImpact is High). It never deletes or edits an existing
    # deployment. To undo a run, delete the deployments that carry the plan ID.
    #
    # .PARAMETER Plan
    # The plan that New-UpdatePlan returns, or the object read from the JSON file.
    #
    # .PARAMETER ComputerName
    # The computer that runs the SMS Provider. The default is the plan computer.
    #
    # .PARAMETER Credential
    # An optional credential for the CIM session.
    #
    # .PARAMETER Apply
    # Required to change anything on the site.
    #
    # .EXAMPLE
    # Invoke-UpdatePlan -Plan $objPlan -Apply -WhatIf
    #
    # # Shows each deployment that would be created. Creates nothing.
    #
    # .EXAMPLE
    # $arrResult = @(Invoke-UpdatePlan -Plan $objPlan -Apply -Confirm:$false)
    #
    # # $arrResult[0].Status = 'Created'
    #
    # .INPUTS
    # None. You can't pipe objects to this function.
    #
    # .OUTPUTS
    # [pscustomobject] One object for each wave with updates. Properties: Wave,
    # CollectionId, UpdateCount, Status (Created, Skipped, Failed), AssignmentId, Message.
    #
    # .NOTES
    # This function does not support positional parameters.
    #
    # Version: 1.0.20261105.0
    [CmdletBinding(PositionalBinding = $false, SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Plan,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$ComputerName,

        [Parameter(Mandatory = $false)]
        [System.Management.Automation.PSCredential]$Credential,

        [Parameter(Mandatory = $false)]
        [switch]$Apply
    )

    process {
        if (-not $Apply) {
            Write-Warning -Message 'Plan only. No change was made. Add -Apply to create the deployments.'
            return
        }
        if ([string]::IsNullOrEmpty($ComputerName)) {
            $ComputerName = [string]$Plan.ComputerName
        }
        if (-not $WhatIfPreference) {
            foreach ($objCheckWave in @($Plan.Waves)) {
                if (@($objCheckWave.Updates).Count -gt 0 -and ([string]$objCheckWave.CollectionId).StartsWith('SMS', [System.StringComparison]::OrdinalIgnoreCase)) {
                    throw ('{0}: the collection {1} is built in. Deployments to built-in collections are blocked.' -f $objCheckWave.Name, $objCheckWave.CollectionId)
                }
            }
        }
        $strNamespace = 'root\sms\site_{0}' -f $Plan.SiteCode
        $objSession = $null
        try {
            if ($WhatIfPreference) {
                Write-Verbose -Message 'WhatIf: no CIM session is opened.'
            } else {
                $hashtableSession = @{ ComputerName = $ComputerName; ErrorAction = 'Stop' }
                if ($PSBoundParameters.ContainsKey('Credential')) {
                    $hashtableSession['Credential'] = $Credential
                }
                $objSession = New-CimSession @hashtableSession
            }
            foreach ($objWave in $Plan.Waves) {
                $arrUpdate = @($objWave.Updates)
                if ($arrUpdate.Count -eq 0) {
                    continue
                }
                $strName = 'UpdatePlanner {0} {1}' -f $Plan.PlanId, $objWave.Name
                $strTarget = '{0} ({1} updates to {2})' -f $strName, $arrUpdate.Count, $objWave.CollectionId
                if (-not $PSCmdlet.ShouldProcess($strTarget, 'Create software update deployment')) {
                    [pscustomobject]@{
                        Wave = $objWave.Name
                        CollectionId = $objWave.CollectionId
                        UpdateCount = $arrUpdate.Count
                        Status = 'Skipped'
                        AssignmentId = $null
                        Message = 'Not confirmed or WhatIf.'
                    }
                    continue
                }
                try {
                    $datetimeStart = [datetime]::ParseExact([string]$objWave.StartDate, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
                    $datetimeDeadline = [datetime]::ParseExact([string]$objWave.DeadlineDate, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
                    [uint32[]]$arrCIId = @($arrUpdate | ForEach-Object { [uint32]$_.CIId })
                    $hashtableProperty = @{
                        AssignmentName = $strName
                        AssignmentDescription = 'Created by Update Planner plan {0}' -f $Plan.PlanId
                        AssignedCIs = $arrCIId
                        TargetCollectionID = [string]$objWave.CollectionId
                        StartTime = $datetimeStart
                        EnforcementDeadline = $datetimeDeadline
                        AssignmentType = [uint32]1
                        DesiredConfigType = [uint32]1
                        ApplyToSubTargets = $false
                        UseGMTTimes = $false
                        NotifyUser = $true
                        OverrideServiceWindows = $false
                        RebootOutsideOfServiceWindows = $false
                        SuppressReboot = [uint32]0
                        WoLEnabled = $false
                        LocaleID = [uint32]1033
                    }
                    $objCreated = New-CimInstance -CimSession $objSession -Namespace $strNamespace -ClassName 'SMS_UpdatesAssignment' -Property $hashtableProperty -ErrorAction Stop
                    [pscustomobject]@{
                        Wave = $objWave.Name
                        CollectionId = $objWave.CollectionId
                        UpdateCount = $arrUpdate.Count
                        Status = 'Created'
                        AssignmentId = [int]$objCreated.AssignmentID
                        Message = ''
                    }
                } catch {
                    Write-Debug -Message ('Deployment failed: {0}' -f $_.Exception.Message)
                    [pscustomobject]@{
                        Wave = $objWave.Name
                        CollectionId = $objWave.CollectionId
                        UpdateCount = $arrUpdate.Count
                        Status = 'Failed'
                        AssignmentId = $null
                        Message = $_.Exception.Message
                    }
                }
            }
        } finally {
            if ($null -ne $objSession) {
                Remove-CimSession -CimSession $objSession -ErrorAction SilentlyContinue
            }
        }
    }
}

#endregion Public functions

#region Window support

function Get-UpdatePlannerCollection {
    # .SYNOPSIS
    # Reads the device collections and the console folders of a site. Read only.
    #
    # .DESCRIPTION
    # Runs three SELECT queries against the SMS Provider and returns the data in the
    # shape that the collection picker of the window needs: collections with a
    # folder ID, and the folder tree.
    #
    # .PARAMETER ComputerName
    # The computer that runs the SMS Provider.
    #
    # .PARAMETER Credential
    # An optional credential for the CIM session.
    #
    # .PARAMETER SiteCode
    # The site code. When omitted, the function reads it from the SMS Provider.
    #
    # .EXAMPLE
    # $objList = Get-UpdatePlannerCollection -ComputerName 'cm01.contoso.com'
    #
    # # $objList.Collections holds one object for each device collection.
    #
    # .INPUTS
    # None. You can't pipe objects to this function.
    #
    # .OUTPUTS
    # [pscustomobject] Properties SiteCode, Collections (CollectionID, Name, MemberCount,
    # FolderID, IsBuiltIn) and Folders (FolderID, ParentID, Name).
    #
    # .NOTES
    # This function does not support positional parameters.
    #
    # Version: 1.0.20261106.0
    [CmdletBinding(PositionalBinding = $false)]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ComputerName,

        [Parameter(Mandatory = $false)]
        [System.Management.Automation.PSCredential]$Credential,

        [Parameter(Mandatory = $false)]
        [ValidatePattern('^[A-Za-z0-9]{3}$')]
        [string]$SiteCode
    )

    process {
        $objSession = $null
        try {
            $hashtableSession = @{ ComputerName = $ComputerName; ErrorAction = 'Stop' }
            if ($PSBoundParameters.ContainsKey('Credential')) {
                $hashtableSession['Credential'] = $Credential
            }
            $objSession = New-CimSession @hashtableSession
            if ([string]::IsNullOrEmpty($SiteCode)) {
                $arrLocation = @(Invoke-UpCimQuery -CimSession $objSession -Namespace 'root\sms' -Query 'SELECT SiteCode FROM SMS_ProviderLocation WHERE ProviderForLocalSite = TRUE')
                if ($arrLocation.Count -lt 1) {
                    throw 'The SMS Provider reports no local site code.'
                }
                $SiteCode = [string]$arrLocation[0].SiteCode
            }
            $strNamespace = 'root\sms\site_{0}' -f $SiteCode

            $hashtableFolderOf = @{}
            foreach ($objItem in (Invoke-UpCimQuery -CimSession $objSession -Namespace $strNamespace -Query 'SELECT InstanceKey, ContainerNodeID FROM SMS_ObjectContainerItem WHERE ObjectType = 5000')) {
                $hashtableFolderOf[[string]$objItem.InstanceKey] = [int]$objItem.ContainerNodeID
            }
            $listFolder = New-Object -TypeName 'System.Collections.Generic.List[pscustomobject]'
            foreach ($objNode in (Invoke-UpCimQuery -CimSession $objSession -Namespace $strNamespace -Query 'SELECT ContainerNodeID, Name, ParentContainerNodeID FROM SMS_ObjectContainerNode WHERE ObjectType = 5000')) {
                $listFolder.Add([pscustomobject]@{
                        FolderID = [int]$objNode.ContainerNodeID
                        ParentID = [int]$objNode.ParentContainerNodeID
                        Name = [string]$objNode.Name
                    })
            }
            $listCollection = New-Object -TypeName 'System.Collections.Generic.List[pscustomobject]'
            foreach ($objRow in (Invoke-UpCimQuery -CimSession $objSession -Namespace $strNamespace -Query 'SELECT CollectionID, Name, MemberCount FROM SMS_Collection WHERE CollectionType = 2')) {
                $strId = [string]$objRow.CollectionID
                $intFolder = 0
                if ($hashtableFolderOf.ContainsKey($strId)) {
                    $intFolder = $hashtableFolderOf[$strId]
                }
                $listCollection.Add([pscustomobject]@{
                        CollectionID = $strId
                        Name = [string]$objRow.Name
                        MemberCount = [int]$objRow.MemberCount
                        FolderID = $intFolder
                        IsBuiltIn = $strId.StartsWith('SMS', [System.StringComparison]::OrdinalIgnoreCase)
                    })
            }
            [pscustomobject]@{
                SiteCode = $SiteCode
                Collections = $listCollection.ToArray()
                Folders = $listFolder.ToArray()
            }
        } catch {
            Write-Debug -Message ('Get-UpdatePlannerCollection failed: {0}' -f $_.Exception.Message)
            throw
        } finally {
            if ($null -ne $objSession) {
                Remove-CimSession -CimSession $objSession -ErrorAction SilentlyContinue
            }
        }
    }
}

function Resolve-UpdatePlannerSetting {
    # .SYNOPSIS
    # Checks the plan settings that a person typed in the window.
    #
    # .DESCRIPTION
    # Converts the text of each setting to its typed value and collects one message
    # for each wrong value. The function reads nothing and changes nothing.
    #
    # .PARAMETER ComputerName
    # The SMS Provider computer name as typed.
    #
    # .PARAMETER StartDateText
    # The start date of wave 1.
    #
    # .PARAMETER WaveSpacingText
    # Days between wave start dates, 0 to 365.
    #
    # .PARAMETER DeadlineText
    # Days from a wave start to its deadline, 0 to 365.
    #
    # .PARAMETER SeverityName
    # One of All, Low, Moderate, Important, Critical.
    #
    # .PARAMETER MaxUpdatesText
    # The most updates in one wave, 1 to 1000.
    #
    # .PARAMETER TargetCollection
    # The wave collections, as IDs, in wave order.
    #
    # .EXAMPLE
    # $objSetting = Resolve-UpdatePlannerSetting -ComputerName 'cm01' -StartDateText '2026-11-09' -TargetCollection 'MCM00015'
    #
    # # $objSetting.IsValid = $true
    #
    # .INPUTS
    # None. You can't pipe objects to this function.
    #
    # .OUTPUTS
    # [pscustomobject] Properties IsValid, Errors and the typed values.
    #
    # .NOTES
    # This function does not support positional parameters.
    #
    # Version: 1.0.20261106.0
    [CmdletBinding(PositionalBinding = $false)]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$ComputerName = '',

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$StartDateText = '',

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$WaveSpacingText = '7',

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$DeadlineText = '3',

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$SeverityName = 'All',

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$MaxUpdatesText = '1000',

        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [string[]]$TargetCollection = @()
    )

    process {
        $listError = New-Object -TypeName 'System.Collections.Generic.List[string]'
        $strComputer = $ComputerName.Trim()
        if ($strComputer -notmatch '^[A-Za-z0-9_.-]{1,255}$') {
            $listError.Add('Enter the SMS Provider computer name in Options.')
        }
        $datetimeStart = [datetime]::MinValue
        if (-not [datetime]::TryParse($StartDateText.Trim(), [System.Globalization.CultureInfo]::CurrentCulture, [System.Globalization.DateTimeStyles]::None, [ref]$datetimeStart)) {
            $listError.Add('The start date is not a date.')
        }
        $intSpacing = 0
        if (-not [int]::TryParse($WaveSpacingText.Trim(), [ref]$intSpacing) -or $intSpacing -lt 0 -or $intSpacing -gt 365) {
            $listError.Add('Days between waves must be a whole number from 0 to 365.')
        }
        $intDeadline = 0
        if (-not [int]::TryParse($DeadlineText.Trim(), [ref]$intDeadline) -or $intDeadline -lt 0 -or $intDeadline -gt 365) {
            $listError.Add('Days to the deadline must be a whole number from 0 to 365.')
        }
        $hashtableSeverity = @{ All = 0; Low = 2; Moderate = 6; Important = 8; Critical = 10 }
        $intSeverity = 0
        if ($hashtableSeverity.ContainsKey($SeverityName)) {
            $intSeverity = [int]$hashtableSeverity[$SeverityName]
        } else {
            $listError.Add('The lowest severity must be All, Low, Moderate, Important or Critical.')
        }
        $intMaxUpdates = 0
        if (-not [int]::TryParse($MaxUpdatesText.Trim(), [ref]$intMaxUpdates) -or $intMaxUpdates -lt 1 -or $intMaxUpdates -gt 1000) {
            $listError.Add('The most updates in a wave must be a whole number from 1 to 1000.')
        }
        $arrTarget = @($TargetCollection | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($arrTarget.Count -eq 0) {
            $listError.Add('Add at least one wave collection.')
        }
        if (@($arrTarget | Select-Object -Unique).Count -ne $arrTarget.Count) {
            $listError.Add('A collection is in the wave list more than once.')
        }
        [pscustomobject]@{
            IsValid = ($listError.Count -eq 0)
            Errors = $listError.ToArray()
            ComputerName = $strComputer
            StartDate = $datetimeStart.Date
            WaveSpacingDays = $intSpacing
            DeadlineDays = $intDeadline
            MinimumSeverity = $intSeverity
            MaxUpdatesPerWave = $intMaxUpdates
            TargetCollection = $arrTarget
        }
    }
}

function ConvertTo-UpdatePlanRow {
    # .SYNOPSIS
    # Flattens the waves of a plan into one row for each planned update.
    #
    # .PARAMETER Plan
    # The plan that New-UpdatePlan returns.
    #
    # .EXAMPLE
    # $arrRow = ConvertTo-UpdatePlanRow -Plan $objPlan
    #
    # # One row for each update in each wave.
    #
    # .INPUTS
    # None. You can't pipe objects to this function.
    #
    # .OUTPUTS
    # [pscustomobject] Properties Wave, Collection, Start, Deadline, Sequence, Article,
    # Severity, Devices, Title.
    #
    # .NOTES
    # This function does not support positional parameters.
    #
    # Version: 1.0.20261106.0
    [CmdletBinding(PositionalBinding = $false)]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Plan
    )

    process {
        foreach ($objWave in @($Plan.Waves)) {
            foreach ($objUpdate in @($objWave.Updates)) {
                $strArticle = ''
                if (-not [string]::IsNullOrEmpty($objUpdate.ArticleId)) {
                    $strArticle = 'KB{0}' -f $objUpdate.ArticleId
                }
                [pscustomobject]@{
                    Wave = [int]$objWave.Order
                    Collection = [string]$objWave.CollectionName
                    Start = [string]$objWave.StartDate
                    Deadline = [string]$objWave.DeadlineDate
                    Sequence = [int]$objUpdate.Sequence
                    Article = $strArticle
                    Severity = [string]$objUpdate.SeverityName
                    Devices = [int]$objUpdate.NeededDevices
                    Title = [string]$objUpdate.Title
                }
            }
        }
    }
}

function ConvertTo-UpdatePlanSkippedRow {
    # .SYNOPSIS
    # Flattens the skipped updates of a plan into rows for a grid.
    #
    # .PARAMETER Plan
    # The plan that New-UpdatePlan returns.
    #
    # .EXAMPLE
    # $arrRow = ConvertTo-UpdatePlanSkippedRow -Plan $objPlan
    #
    # # One row for each skipped update.
    #
    # .INPUTS
    # None. You can't pipe objects to this function.
    #
    # .OUTPUTS
    # [pscustomobject] Properties Reason, Wave, Article, Title.
    #
    # .NOTES
    # This function does not support positional parameters.
    #
    # Version: 1.0.20261106.0
    [CmdletBinding(PositionalBinding = $false)]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Plan
    )

    process {
        foreach ($objSkip in @($Plan.Skipped)) {
            $strArticle = ''
            if (-not [string]::IsNullOrEmpty($objSkip.ArticleId)) {
                $strArticle = 'KB{0}' -f $objSkip.ArticleId
            }
            [pscustomobject]@{
                Reason = [string]$objSkip.Reason
                Wave = [string]$objSkip.Wave
                Article = $strArticle
                Title = [string]$objSkip.Title
            }
        }
    }
}

function ConvertTo-UpdatePlanMarkdown {
    # .SYNOPSIS
    # Returns the Markdown review text of a plan.
    #
    # .PARAMETER Plan
    # The plan that New-UpdatePlan returns.
    #
    # .EXAMPLE
    # $strText = ConvertTo-UpdatePlanMarkdown -Plan $objPlan
    #
    # # The text that Export-UpdatePlan writes to the .md file.
    #
    # .INPUTS
    # None. You can't pipe objects to this function.
    #
    # .OUTPUTS
    # [string] The Markdown text.
    #
    # .NOTES
    # This function does not support positional parameters.
    #
    # Version: 1.0.20261106.0
    [CmdletBinding(PositionalBinding = $false)]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Plan
    )

    process {
        ConvertTo-UpMarkdown -Plan $Plan
    }
}

function ConvertTo-UpdatePlanJson {
    # .SYNOPSIS
    # Returns the JSON text of a plan, the format that Export-UpdatePlan writes.
    #
    # .PARAMETER Plan
    # The plan that New-UpdatePlan returns.
    #
    # .EXAMPLE
    # $strJson = ConvertTo-UpdatePlanJson -Plan $objPlan
    #
    # # The JSON text of the plan.
    #
    # .INPUTS
    # None. You can't pipe objects to this function.
    #
    # .OUTPUTS
    # [string] The JSON text.
    #
    # .NOTES
    # This function does not support positional parameters.
    #
    # Version: 1.0.20261106.0
    [CmdletBinding(PositionalBinding = $false)]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Plan
    )

    process {
        $Plan | ConvertTo-Json -Depth 8
    }
}

function ConvertTo-UpdatePlanHtml {
    # .SYNOPSIS
    # Returns a self-contained HTML report of a plan.
    #
    # .DESCRIPTION
    # The page has no script and no external resource. Every value is HTML encoded.
    #
    # .PARAMETER Plan
    # The plan that New-UpdatePlan returns.
    #
    # .EXAMPLE
    # $strHtml = ConvertTo-UpdatePlanHtml -Plan $objPlan
    #
    # # A complete HTML document.
    #
    # .INPUTS
    # None. You can't pipe objects to this function.
    #
    # .OUTPUTS
    # [string] The HTML text.
    #
    # .NOTES
    # This function does not support positional parameters.
    #
    # Version: 1.0.20261106.0
    [CmdletBinding(PositionalBinding = $false)]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Plan
    )

    process {
        $scriptBlockEncode = { param($objValue) [System.Net.WebUtility]::HtmlEncode([string]$objValue) }
        $listLine = New-Object -TypeName 'System.Collections.Generic.List[string]'
        $listLine.Add('<!DOCTYPE html>')
        $listLine.Add('<html lang="en"><head><meta charset="utf-8">')
        $listLine.Add('<title>Update plan</title>')
        $listLine.Add('<style>body{font-family:Segoe UI,Arial,sans-serif;margin:24px;color:#1b1b1b}h1{font-size:22px}h2{font-size:17px;margin-top:28px;border-bottom:1px solid #ccc;padding-bottom:4px}table{border-collapse:collapse;margin:8px 0;font-size:13px}th,td{border:1px solid #c8c8c8;padding:4px 10px;text-align:left}th{background:#0078d4;color:#fff}tr:nth-child(even) td{background:#f3f3f3}.meta{color:#555;font-size:13px}</style>')
        $listLine.Add('</head><body>')
        $listLine.Add('<h1>Update plan</h1>')
        $listLine.Add(('<p class="meta">Plan ID {0}. Generated {1}. Site {2} on {3}. Plan only: this report changes nothing on the site.</p>' -f (& $scriptBlockEncode $Plan.PlanId), (& $scriptBlockEncode $Plan.GeneratedAt), (& $scriptBlockEncode $Plan.SiteCode), (& $scriptBlockEncode $Plan.ComputerName)))
        $listLine.Add('<h2>Site state</h2><table>')
        foreach ($objProperty in $Plan.Summary.PSObject.Properties) {
            $listLine.Add(('<tr><th>{0}</th><td>{1}</td></tr>' -f (& $scriptBlockEncode $objProperty.Name), (& $scriptBlockEncode $objProperty.Value)))
        }
        if ($null -ne $Plan.Sync) {
            $listLine.Add(('<tr><th>Last successful WSUS synchronization</th><td>{0} (error code {1})</td></tr>' -f (& $scriptBlockEncode $Plan.Sync.LastSuccessfulSyncTime), (& $scriptBlockEncode $Plan.Sync.LastSyncErrorCode)))
        }
        $listLine.Add('</table>')
        foreach ($objWave in @($Plan.Waves)) {
            $listLine.Add(('<h2>Wave {0}: {1}</h2>' -f (& $scriptBlockEncode $objWave.Order), (& $scriptBlockEncode $objWave.Name)))
            $strDeviceNoun = if ([int]$objWave.MemberCount -eq 1) { 'device' } else { 'devices' }
            $listLine.Add(('<p class="meta">Collection {0} ({1}), {2} {6}. Start {3}. Deadline {4}. Maintenance windows: {5}.</p>' -f (& $scriptBlockEncode $objWave.CollectionName), (& $scriptBlockEncode $objWave.CollectionId), (& $scriptBlockEncode $objWave.MemberCount), (& $scriptBlockEncode $objWave.StartDate), (& $scriptBlockEncode $objWave.DeadlineDate), (& $scriptBlockEncode $objWave.MaintenanceWindowCount), $strDeviceNoun))
            if (@($objWave.Updates).Count -gt 0) {
                $listLine.Add('<table><tr><th>Seq</th><th>Article</th><th>Severity</th><th>Devices that need it</th><th>Title</th></tr>')
                foreach ($objUpdate in @($objWave.Updates)) {
                    $strArticle = 'none'
                    if (-not [string]::IsNullOrEmpty($objUpdate.ArticleId)) {
                        $strArticle = 'KB{0}' -f $objUpdate.ArticleId
                    }
                    $listLine.Add(('<tr><td>{0}</td><td>{1}</td><td>{2}</td><td>{3}</td><td>{4}</td></tr>' -f (& $scriptBlockEncode $objUpdate.Sequence), (& $scriptBlockEncode $strArticle), (& $scriptBlockEncode $objUpdate.SeverityName), (& $scriptBlockEncode $objUpdate.NeededDevices), (& $scriptBlockEncode $objUpdate.Title)))
                }
                $listLine.Add('</table>')
            } else {
                $listLine.Add('<p>No update in this wave.</p>')
            }
        }
        $listLine.Add('<h2>Skipped updates</h2>')
        if (@($Plan.Skipped).Count -eq 0) {
            $listLine.Add('<p>None.</p>')
        } else {
            $listLine.Add('<table><tr><th>Reason</th><th>Wave</th><th>Article</th><th>Title</th></tr>')
            foreach ($objSkip in @($Plan.Skipped)) {
                $strArticle = 'none'
                if (-not [string]::IsNullOrEmpty($objSkip.ArticleId)) {
                    $strArticle = 'KB{0}' -f $objSkip.ArticleId
                }
                $listLine.Add(('<tr><td>{0}</td><td>{1}</td><td>{2}</td><td>{3}</td></tr>' -f (& $scriptBlockEncode $objSkip.Reason), (& $scriptBlockEncode $objSkip.Wave), (& $scriptBlockEncode $strArticle), (& $scriptBlockEncode $objSkip.Title)))
            }
            $listLine.Add('</table>')
        }
        $listLine.Add('</body></html>')
        $listLine -join [System.Environment]::NewLine
    }
}

function Get-UpdatePlanDeploymentPreview {
    # .SYNOPSIS
    # Lists the deployments that Invoke-UpdatePlan -Apply would create. Reads only the plan.
    #
    # .PARAMETER Plan
    # The plan that New-UpdatePlan returns.
    #
    # .EXAMPLE
    # $arrPreview = Get-UpdatePlanDeploymentPreview -Plan $objPlan
    #
    # # One row for each wave that holds updates.
    #
    # .INPUTS
    # None. You can't pipe objects to this function.
    #
    # .OUTPUTS
    # [pscustomobject] Properties Name, CollectionId, Collection, UpdateCount, Start, Deadline.
    #
    # .NOTES
    # This function does not support positional parameters.
    #
    # Version: 1.0.20261106.0
    [CmdletBinding(PositionalBinding = $false)]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Plan
    )

    process {
        foreach ($objWave in @($Plan.Waves)) {
            if (@($objWave.Updates).Count -eq 0) {
                continue
            }
            [pscustomobject]@{
                Name = 'UpdatePlanner {0} {1}' -f $Plan.PlanId, $objWave.Name
                CollectionId = [string]$objWave.CollectionId
                Collection = [string]$objWave.CollectionName
                UpdateCount = @($objWave.Updates).Count
                Start = [string]$objWave.StartDate
                Deadline = [string]$objWave.DeadlineDate
            }
        }
    }
}

function ConvertTo-UpdatePlanResultRow {
    # .SYNOPSIS
    # Turns the results of Invoke-UpdatePlan into rows for a grid.
    #
    # .DESCRIPTION
    # For a dry run, a Skipped result becomes a Dry run row and the message says that
    # nothing was created. Other results pass through unchanged.
    #
    # .PARAMETER Result
    # The result objects that Invoke-UpdatePlan returns.
    #
    # .PARAMETER DryRun
    # Set when the results come from a run with -WhatIf.
    #
    # .EXAMPLE
    # $arrRow = ConvertTo-UpdatePlanResultRow -Result $arrResult -DryRun
    #
    # # Rows with Status Dry run.
    #
    # .INPUTS
    # None. You can't pipe objects to this function.
    #
    # .OUTPUTS
    # [pscustomobject] Properties Status, Wave, CollectionId, UpdateCount, AssignmentId, Message.
    #
    # .NOTES
    # This function does not support positional parameters.
    #
    # Version: 1.0.20261106.0
    [CmdletBinding(PositionalBinding = $false)]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Result,

        [Parameter(Mandatory = $false)]
        [switch]$DryRun
    )

    process {
        foreach ($objResult in @($Result)) {
            $strStatus = [string]$objResult.Status
            $strMessage = [string]$objResult.Message
            if ($DryRun -and $strStatus -eq 'Skipped') {
                $strStatus = 'Dry run'
                $strMessage = 'Would create this deployment. Nothing was created.'
            }
            [pscustomobject]@{
                Status = $strStatus
                Wave = [string]$objResult.Wave
                CollectionId = [string]$objResult.CollectionId
                UpdateCount = [int]$objResult.UpdateCount
                AssignmentId = $objResult.AssignmentId
                Message = $strMessage
            }
        }
    }
}
function Test-UpdatePlanApplyAllowed {
    # .SYNOPSIS
    # Checks whether a plan may be applied and returns the reasons when it may not.
    #
    # .DESCRIPTION
    # A plan is blocked when it holds no update to deploy, or when a wave targets a
    # built-in collection (an ID that starts with SMS, for example All Systems). The
    # function reads only the plan.
    #
    # .PARAMETER Plan
    # The plan that New-UpdatePlan returns.
    #
    # .EXAMPLE
    # $objCheck = Test-UpdatePlanApplyAllowed -Plan $objPlan
    #
    # # $objCheck.IsAllowed = $true when nothing blocks the apply step.
    #
    # .INPUTS
    # None. You can't pipe objects to this function.
    #
    # .OUTPUTS
    # [pscustomobject] Properties IsAllowed and Reasons.
    #
    # .NOTES
    # This function does not support positional parameters.
    #
    # Version: 1.0.20261106.0
    [CmdletBinding(PositionalBinding = $false)]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Plan
    )

    process {
        $listReason = New-Object -TypeName 'System.Collections.Generic.List[string]'
        $intDeployable = 0
        foreach ($objWave in @($Plan.Waves)) {
            if (@($objWave.Updates).Count -gt 0) {
                $intDeployable++
                if (([string]$objWave.CollectionId).StartsWith('SMS', [System.StringComparison]::OrdinalIgnoreCase)) {
                    $listReason.Add(('{0}: the collection {1} is built in. Deployments to built-in collections are blocked.' -f $objWave.Name, $objWave.CollectionId))
                }
            }
        }
        if ($intDeployable -eq 0) {
            $listReason.Add('The plan holds no update to deploy.')
        }
        [pscustomobject]@{
            IsAllowed = ($listReason.Count -eq 0)
            Reasons = $listReason.ToArray()
        }
    }
}
function Write-UpdatePlanFile {
    # .SYNOPSIS
    # Writes text to a file as UTF-8 without a byte order mark.
    #
    # .PARAMETER Path
    # The file path. The function creates the folder when it is missing.
    #
    # .PARAMETER Text
    # The text to write.
    #
    # .EXAMPLE
    # $strPath = Write-UpdatePlanFile -Path 'C:\plans\plan.html' -Text $strHtml
    #
    # # Returns the absolute path written.
    #
    # .INPUTS
    # None. You can't pipe objects to this function.
    #
    # .OUTPUTS
    # [string] The absolute path written.
    #
    # .NOTES
    # This function does not support positional parameters.
    #
    # Version: 1.0.20261106.0
    [CmdletBinding(PositionalBinding = $false)]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Text
    )

    process {
        Write-UpTextFile -Path $Path -Text $Text
    }
}

function Write-UpdatePlanAudit {
    # .SYNOPSIS
    # Appends one record to the action log, a JSON Lines file.
    #
    # .DESCRIPTION
    # The window writes one record for each dry run and each apply, with the plan ID,
    # the user, the computer and the result of each wave.
    #
    # .PARAMETER Path
    # The path of the JSON Lines file. The function creates the folder when it is missing.
    #
    # .PARAMETER Record
    # The record to append.
    #
    # .EXAMPLE
    # Write-UpdatePlanAudit -Path 'C:\logs\actions.jsonl' -Record ([pscustomobject]@{ Action = 'DryRun' })
    #
    # # Appends one line.
    #
    # .INPUTS
    # None. You can't pipe objects to this function.
    #
    # .OUTPUTS
    # None.
    #
    # .NOTES
    # This function does not support positional parameters.
    #
    # Version: 1.0.20261106.0
    [CmdletBinding(PositionalBinding = $false)]
    [OutputType([void])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$Record
    )

    process {
        $strFullPath = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($Path)
        [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($strFullPath))
        $strLine = ($Record | ConvertTo-Json -Depth 6 -Compress) + [System.Environment]::NewLine
        $objEncoding = New-Object -TypeName 'System.Text.UTF8Encoding' -ArgumentList $false
        [System.IO.File]::AppendAllText($strFullPath, $strLine, $objEncoding)
    }
}

#endregion Window support

Export-ModuleMember -Function 'Get-UpdatePlannerState', 'New-UpdatePlan', 'Export-UpdatePlan', 'Invoke-UpdatePlan', 'Get-UpdatePlannerCollection', 'Resolve-UpdatePlannerSetting', 'ConvertTo-UpdatePlanRow', 'ConvertTo-UpdatePlanSkippedRow', 'ConvertTo-UpdatePlanResultRow', 'ConvertTo-UpdatePlanMarkdown', 'ConvertTo-UpdatePlanJson', 'ConvertTo-UpdatePlanHtml', 'Get-UpdatePlanDeploymentPreview', 'Test-UpdatePlanApplyAllowed', 'Write-UpdatePlanFile', 'Write-UpdatePlanAudit'
