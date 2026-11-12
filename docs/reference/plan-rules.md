# Plan rules

This page lists what Update Planner reads, the rules that build a plan, what the deploy step creates, and what the tool does not do.

## What it does

The page states the rules of the plan and of the deploy step. The window and the command line use the same rules.

## When to use it

Use this page to find out why an update is, or is not, in a wave.

## Requirements

None.

## What the tool reads

The tool reads the site with the ConfigurationManager PowerShell module (it comes with the Configuration Manager console). It opens the site drive of the SMS Provider computer and calls these cmdlets:

| Data | Cmdlet | Notes |
|---|---|---|
| Site check when the site drive opens | `Get-CMSite -SiteCode <site code>` | A wrong site code or provider stops the step with "Cannot open site ...". |
| Update catalog: needed, installed, superseded, expired counts | `Get-CMSoftwareUpdate -Fast` | Same rows as `SMS_SoftwareUpdate`. The call does not use `-IncludeUpgrade`. See the note below. |
| Last WSUS synchronization | `Get-CMSoftwareUpdateSyncStatus` | With **Include WSUS Counts** it also reads update counts from the WSUS server (`Get-WsusServer`) over PowerShell remoting to the provider computer. |
| Target collection (by ID or by name) | `Get-CMCollection` | The tool checks that it is a device collection. |
| Members of a target collection | `Get-CMCollectionMember` | |
| Maintenance windows for updates | `Get-CMMaintenanceWindow` | Windows of type 1 (all deployments) and type 4 (software updates). |
| Existing update deployments | `Get-CMSoftwareUpdateDeployment` | |
| Collection picker: device collections | `Get-CMDeviceCollection` | |
| Collection picker: console folders | `Get-CMFolder -TypeName SMS_Collection_Device` | |

Note on `-IncludeUpgrade`: Microsoft Learn says that this switch of `Get-CMSoftwareUpdate` adds the software updates of the upgrade category. The tool does not use it. On a lab site with no updates of the upgrade category, the call returned the same count with and without the switch (checked 2026-11-10). On a site that synchronizes the upgrade category, the plan does not hold those updates.

Two reads have no cmdlet. They use `Invoke-CMWmiQuery` (a ConfigurationManager cmdlet that runs a WQL `SELECT` on the open site drive):

| Data | Query | Why |
|---|---|---|
| Devices that need an update (status 2) | `SMS_UpdateComplianceStatus` | No cmdlet returns the update status of each device. |
| Folder that holds a collection | `SMS_ObjectContainerItem` | No cmdlet returns the folder of a collection. |

Every site read is a read. Building a plan changes nothing on the site.

## Plan rules

The tool checks each update of the catalog against the rules in this order. The first rule that matches gives the reason.

| Rule | Result |
|---|---|
| Update is expired | Skipped (`Expired`). Counted, not listed. |
| Update is superseded | Skipped (`Superseded`). Listed when a device still needs it. |
| No device needs the update | Skipped (`NotNeeded`). Counted, not listed. |
| Severity is below the lowest severity | Skipped and listed (`BelowMinimumSeverity`). |
| No device in the wave collection needs the update | Not in that wave (`NotNeededInCollection`). Not listed. |
| An existing deployment already targets the update at the collection | Skipped for that wave and listed (`AlreadyDeployed`). |
| Wave holds the most updates per wave | The rest are skipped and listed (`WaveLimit`). |
| Order in a wave | Severity (high to low), devices that need the update (high to low), article ID, CI ID. |
| Dates | Wave n starts on the start date + (n - 1) x days between waves. The deadline is the start + days to deadline. |

### Severity

**Lowest Severity** sets the lowest severity number to plan. An update with a lower number is skipped.

| Lowest Severity | Number | Updates in the plan |
|---|---|---|
| All | 0 | All, also updates with no severity (`None`) |
| Low | 2 | Low, Moderate, Important, Critical |
| Moderate | 6 | Moderate, Important, Critical |
| Important | 8 | Important, Critical |
| Critical | 10 | Critical |

### Waves

- The tool makes one wave for each wave collection, in the order of the wave list. The first collection is wave 1.
- A wave is named `Wave <n> <collection name>`.
- A wave collection is a device collection, given by its ID or by its name. A name must match exactly one collection.
- A wave holds at most the value of **Most Updates per Wave**, 1 to 1000. 1000 is the limit of one software update group.
- A wave that holds no update gets no deployment.

## What the Deploy step creates

For each wave that holds updates, two objects:

1. A software update group (`New-CMSoftwareUpdateGroup`) that holds the update IDs of the wave. Its description is `Created by Update Planner plan <PlanId>`.
2. A software update deployment of that group (`New-CMSoftwareUpdateDeployment`) with these values:

| Parameter | Value |
|---|---|
| `-CollectionId` | The wave collection. |
| `-DeploymentName` | The name of the group. |
| `-Comment` | `Created by Update Planner plan <PlanId>` |
| `-DeploymentType` | `Required` |
| `-AvailableDateTime` | The wave start date. |
| `-DeadlineDateTime` | The wave deadline date. |
| `-TimeBasedOn` | `LocalTime` |
| `-UserNotification` | `DisplayAll` |
| `-SoftwareInstallation` | `$false`: no installation outside the maintenance window after the deadline. |
| `-AllowRestart` | `$false`: no restart outside the maintenance window after the deadline. |
| `-DeployWithNoPackage` | `$true`: the deployment uses no deployment package and distributes no content. Without this switch the cmdlet fails for updates that the site has not downloaded. |

Both are named `UpdatePlanner <PlanId> <wave name>`. To undo a run, delete the deployments and the groups whose name holds the plan ID.

The **Dry Run** button and `-WhatIf` run the same step. They do not open the site drive and create nothing.

### Built-in collection block

A collection whose ID starts with `SMS` is a built-in collection, for example All Systems (`SMS00001`). The deploy step refuses a wave that holds updates and targets such a collection:

- The window checks the plan before the confirmation. The message box **Deploy Blocked** names each such wave. It also blocks a plan in which no wave holds an update.
- `Invoke-UpdatePlan -Apply` stops with the same message before it opens the site drive. With `-WhatIf` it does not stop.

## The plan file

The JSON export is a Suite ring plan. Deployment Helper loads it as a ring plan. See [plan-format.md](plan-format.md).

## What the tool does not do

- It does not move a deadline into a maintenance window. It lists the windows of each collection in the report.
- It does not change an existing software update group, deployment, deployment package or collection. It does not download content.
- It does not read or change WSUS approvals. The WSUS counts are information only.
- It does not decide the supersedence chain. It reads the `IsSuperseded` flag that Configuration Manager sets.
- Dates are calendar dates at 00:00 on the computer that runs the tool. A created deployment can show a different clock time on the site server.
- The need counts come from one query for all required rows and one membership read for each target collection. A very large site returns many rows.

## Known limits

- Tested on one lab site with one primary site and one SMS Provider. A hierarchy or a remote provider is not tested.
- The Deploy step needs update content that the site has downloaded, or clients that can download it. Review a created deployment in the console before a real rollout.
- The tool needs the Configuration Manager console on the computer that runs it. The ConfigurationManager module comes only with the console.

## Links

- [Introduction to software updates in Configuration Manager](https://learn.microsoft.com/intune/configmgr/sum/understand/software-updates-introduction): Explains the software update workflow.
- [Monitor software updates](https://learn.microsoft.com/intune/configmgr/sum/deploy-use/monitor-software-updates): Describes how the site reports the state of an update.
