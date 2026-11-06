# Plan rules and limits

## What the tool reads

1. The update catalog from the SMS Provider (`SMS_SoftwareUpdate`): needed, installed, superseded and expired counts for each update.
2. The last WSUS synchronization (`SMS_SUPSyncStatus`). With **Include WSUS counts** it also reads update counts from the WSUS server (`Get-WsusServer`) over PowerShell remoting to the provider computer.
3. The device collections: members, maintenance windows for updates, and how many devices in each collection need each update (`SMS_UpdateComplianceStatus`, status 2).
4. The existing update deployments (`SMS_UpdatesAssignment`).
5. For the collection picker: the device collections and the console folders (`SMS_Collection`, `SMS_ObjectContainerNode`, `SMS_ObjectContainerItem`).

Every site query is a `SELECT`. Building a plan changes nothing on the site.

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

One `SMS_UpdatesAssignment` for each wave that holds updates. The deployment sets the update IDs, the target collection, the start time, the deadline, a required assignment type, and notification on. It leaves every other property at the site default.

## What the tool does not do

- It does not move a deadline into a maintenance window. It lists the windows of each collection in the report.
- It does not create or change software update groups, deployment packages or collections. It does not download content.
- It does not read or change WSUS approvals. The WSUS counts are information only.
- It does not decide the supersedence chain. It reads the `IsSuperseded` flag that Configuration Manager sets.
- Dates are calendar dates at 00:00 on the computer that runs the tool. The provider converts the time with the time zone offset. A created deployment can show a different clock time on the site server.
- The need counts come from one query for all required rows and one membership query for each target collection. A very large site returns many rows.

## Known limits

- Tested on one lab site with one primary site and one SMS Provider. A hierarchy or a remote provider is not tested.
- The Deploy step creates deployments from the update IDs. Review a created deployment in the console before a real rollout.
