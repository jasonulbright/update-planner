# Troubleshooting

This page lists the most common problems of Update Planner with their cause and their fix. Each entry has three parts: the message or the symptom, the cause and the fix.

## What it does

Use the page to find the fix for a message in a dialog, in the log or in the status bar. [Error messages](reference/error-messages.md) lists all messages.

## When to use it

Use this page when a button is off, a step fails, or the plan is not what you expect.

## Requirements

None. Some fixes need rights on the site.

## Steps

1. Read the message. A message in `<angle brackets>` shows a value that the tool inserts.
2. Find the message in the tables below.
3. Do the fix.
4. Select **Build Plan** again.

## Start

| Message or symptom | Cause | Fix |
|---|---|---|
| A message box with the title **Update Planner** says that the Configuration Manager console is not installed, and the tool ends. | The ConfigurationManager module is not on this computer. | Install the console, then start the tool again. |

## Connection

| Message or symptom | Cause | Fix |
|---|---|---|
| The status bar shows "Open Options to set the SMS Provider and the site code". | The provider or the site code is empty. | Select **Options** and enter both. |
| The step failed. The log file has "Access is denied". | The account has no read right on the site. | Run the tool as an account with read rights on the site. See [Permissions](reference/permissions.md). |
| Message box **Step Failed**. The log file has `Cannot open site <site code> on <provider>. ...` | The site code or the SMS Provider name is wrong, the SMS Provider is not reachable, or the account has no rights. | Check the values in **Options**, the network and the account rights. |
| The collection list is old. | The tool keeps the list from the last load. | Select **Load Collections**. |

## Plan

| Message or symptom | Cause | Fix |
|---|---|---|
| The plan has 0 planned assignments. | No device in the wave collections needs an update, or **Lowest Severity** is too high. | Read **Skipped Updates** and the site totals in the summary. |
| An update that you expect is missing. | The update is superseded, expired, below the severity, already deployed to the collection, or over the wave limit. | Find the update in **Skipped Updates**. To check whether an update is expired, find it with `Get-CMSoftwareUpdate -Fast` on the site drive and read `IsExpired`. See [Plan grids](core/plan-grids.md). |
| The report has no WSUS line. | **Include WSUS Counts** is cleared, or the WSUS read failed (PowerShell remoting to the provider, or `Get-WsusServer` on it). The plan builds without the counts. | Select **Include WSUS Counts** and build the plan again. Check PowerShell remoting and the right to run `Get-WsusServer` on the provider. |
| A wave shows fewer updates than the site has. | The wave collection needs only part of them. | None. A wave holds only the updates that its devices need. |

## Deploy

| Message or symptom | Cause | Fix |
|---|---|---|
| **Dry Run** and **Deploy...** are off. | **Enable Actions** is off, or no plan exists. | Build a plan. Turn on **Enable Actions**. |
| Deploy blocked: ... built in. | A wave targets a built-in collection. | Remove the wave. Build the plan again. |
| A deployment shows another clock time on the site server. | The tool sends a date at 00:00 on this computer. The provider converts it. | Check the time zone of this computer and of the site server. |
| You created deployments by mistake. | The confirmation was accepted. | Delete the deployments and the software update groups whose name holds the plan ID in the console. The tool never deletes them. |

## Window

| Message or symptom | Cause | Fix |
|---|---|---|
| The window opens in the wrong place. | The saved window state holds an old position. | Close the tool. Delete `UpdatePlanner.windowstate.json`. Start the tool. |
| The tool does not start. | The folder is blocked, or the PowerShell version is wrong. | Extract the zip again. Start with Windows PowerShell 5.1. The start script unblocks the files in `Lib`. |

## Links

None.
