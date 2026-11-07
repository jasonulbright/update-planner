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
| Update catalog: needed, installed, superseded, expired counts | `Get-CMSoftwareUpdate -Fast` | Same rows as `SMS_SoftwareUpdate`. |
| Last WSUS synchronization | `Get-CMSoftwareUpdateSyncStatus` | With **Include WSUS counts** it also reads update counts from the WSUS server (`Get-WsusServer`) over PowerShell remoting to the provider computer. |
| Target collection (by ID or by name) | `Get-CMCollection` | The tool checks that it is a device collection. |
| Members of a target collection | `Get-CMCollectionMember` | |
| Maintenance windows for updates | `Get-CMMaintenanceWindow` | Windows of type 1 (all deployments) and type 4 (software updates). |
| Existing update deployments | `Get-CMSoftwareUpdateDeployment` | |
| Collection picker: device collections | `Get-CMDeviceCollection` | |
| Collection picker: console folders | `Get-CMFolder -TypeName SMS_Collection_Device` | |

Two reads have no cmdlet. They use `Invoke-CMWmiQuery` (a ConfigurationManager cmdlet that runs a WQL `SELECT` on the open site drive):

| Data | Query | Why |
|---|---|---|
| Devices that need an update (status 2) | `SMS_UpdateComplianceStatus` | No cmdlet returns the update status of each device. |
| Folder that holds a collection | `SMS_ObjectContainerItem` | No cmdlet returns the folder of a collection. |

Every site read is a read. Building a plan changes nothing on the site.

## Plan rules

| Rule | Result |
|---|---|
| Update is expired | Skipped. Counted, not listed. |
| Update is superseded | Skipped. Listed when a device still needs it. |
| No device needs the update | Skipped. Counted, not listed. |
| Severity is below the lowest severity | Skipped and listed. |
| No device in the wave collection needs the update | Not in that wave. |
| An existing deployment already targets the update at the collection | Skipped for that wave and listed (`AlreadyDeployed`). |
| Wave holds the most updates per wave | The rest are skipped and listed (`WaveLimit`). |
| Order in a wave | Severity (high to low), devices that need the update (high to low), article ID, CI ID. |
| Dates | Wave n starts on the start date + (n - 1) x days between waves. The deadline is the start + days to deadline. |

## What the Deploy step creates

For each wave that holds updates, two objects:

1. A software update group (`New-CMSoftwareUpdateGroup`) that holds the update IDs of the wave.
2. A software update deployment of that group (`New-CMSoftwareUpdateDeployment`) with the target collection, the start time, the deadline (required), notification on, and local time. The deployment does not install outside the maintenance window and does not restart outside it. It does not distribute content (`-DeployWithNoPackage`).

Both are named `UpdatePlanner <PlanId> <wave name>`. To undo a run, delete the deployments and the groups whose name holds the plan ID.

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
