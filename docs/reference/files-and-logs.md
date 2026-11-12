# Files and logs

This page lists every folder and file that Update Planner writes.

## What it does

The tool writes next to its script. It writes nothing to the registry. It writes no file outside the script folder, except the files that you export to another folder.

## When to use it

Use this page to find a log, to back up the settings, or to clean up.

## Requirements

Write access for your account to the folder of the script.

## Files

| Path (in the script folder) | Content | Written when |
|---|---|---|
| `UpdatePlanner.prefs.json` | The connection, the plan settings and the wave list. See [Settings](settings.md). | **OK** in Options, **Build Plan** when the settings are valid, the theme toggle, a change of the wave list and window close. |
| `UpdatePlanner.windowstate.json` | The window size, position and page. | Window close. |
| `Logs\UpdatePlanner-<yyyyMMdd-HHmmss>.log` | The tool log of one session. One line for each log line of the window, with the time and the level. | During the session. |
| `Logs\UpdatePlanner-startup-<yyyyMMdd-HHmmss>.txt` | The PowerShell transcript of the start. | At start. |
| `Logs\UpdatePlanner-crash-<yyyyMMdd-HHmmss>.txt` | The details of an unhandled error. | Only after a crash. |
| `Logs\update-planner-actions.jsonl` | The action log: one JSON line for each dry run and each deployment of the window. The command-line script does not write it. | **Dry Run** and **Deploy...** in the window |
| `Reports\update-plan-<ID>.html` | The HTML report. | **Open HTML Report** |
| `Reports\update-plan-<ID>.json`, `.md`, `.html` | The exports. | **Export JSON**, **Export Markdown**, **Export HTML**, when you keep the default folder. |
| `update-plan.json`, `update-plan.md` | The plan of the command-line script, in the current folder. | `Invoke-UpdatePlanner.ps1` |

A session log starts with the line "=== Log initialized ===".

### Action log record

Each line is one JSON object.

| Field | Content |
|---|---|
| `Time` | The time, ISO 8601. |
| `User` | `<domain>\<user>` of the Windows account. |
| `Computer` | The computer that ran the tool. |
| `Action` | `DryRun` or `Apply`. |
| `PlanId` | The plan ID. |
| `Site` | The site code. |
| `Provider` | The SMS Provider. |
| `Results` | One object for each wave: `Wave`, `CollectionId`, `UpdateCount`, `Status`, `AssignmentId`, `Message` and `Detail`. `Detail` holds the error text of a failed deployment. The window shows only `Message`. |

In a dry run, each result has the status `Skipped` and the message "Not confirmed or WhatIf." The grid shows the same result as **Dry run**.

## Steps

### Clean up

1. Close the tool.
2. Delete the files in `Logs` and `Reports` that you do not need.
3. Do not delete `update-planner-actions.jsonl` if you must keep the record of the deployments.

## Limits

- The tool never deletes a log or a report.
- The log files grow with each session.

## Troubleshooting

| Message | Cause | Fix |
|---|---|---|
| The action log could not be written. The log file has the details. | The `Logs` folder is not writable, or the file is locked. | Give your account write access to the folder. The dry run or the deployment was not affected. |

## Links

None.
