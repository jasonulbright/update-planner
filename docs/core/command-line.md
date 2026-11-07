# Command line

`Invoke-UpdatePlanner.ps1` builds the same plan as the window, from a PowerShell prompt.

## What it does

The script reads the site, writes `update-plan.json` and `update-plan.md`, and changes nothing on the site. With `-Apply` it also creates one software update group and one deployment for each wave. `-Apply` supports `-WhatIf` and `-Confirm`.

## When to use it

- Use it to build a plan in a script or a scheduled task.
- Use `-Apply -WhatIf` to see the deployments without the window.

## Requirements

- Windows PowerShell 5.1 or PowerShell 7.
- The Configuration Manager console on this computer (the ConfigurationManager module).
- The same site rights as the window. See [Permissions](../reference/permissions.md).
- Start the script from a PowerShell prompt. A list of collections, such as `'Pilot','Broad'`, needs a PowerShell prompt or `-Command`. `-File` does not split a list at the comma.

## Steps

### Build a plan

1. Open a PowerShell prompt in the Update Planner folder.
2. Run the script with the provider and the wave collections:

   ```powershell
   .\Invoke-UpdatePlanner.ps1 -ComputerName cm01.contoso.com -SiteCode MCM -TargetCollection 'MCM00014', 'MCM00016' -StartDate 2026-11-09
   ```

3. Read the output. It shows the path of the two files.

```text
JsonPath                             MarkdownPath
--------                             ------------
C:\Plans\update-plan.json            C:\Plans\update-plan.md
```

The script writes the files to the current folder unless you set `-OutputPath`. The Markdown file has the same name as the JSON file.

### Show the deployments without creating them

1. Add `-Apply -WhatIf`:

   ```powershell
   .\Invoke-UpdatePlanner.ps1 -ComputerName cm01.contoso.com -SiteCode MCM -TargetCollection 'MCM00014' -StartDate 2026-11-09 -Apply -WhatIf
   ```

2. Read the lines that begin with `What if: Performing the operation "Create software update group and deployment" on target`.

The script still writes the plan files. It creates no deployment.

### Create the deployments

1. Add `-Apply`. The script asks for a confirmation before each deployment.
2. Add `-Confirm:$false` to skip the question.

A built-in collection is refused for a real run. `-Apply -WhatIf` shows the deployment for it.

## Options and settings of this page

| Parameter | Default | Effect |
|---|---|---|
| `-ComputerName` | The local computer | The SMS Provider computer. |
| `-Credential` | The current account | A credential for the connection. |
| `-SiteCode` | None. Required. | Three letters or digits. |
| `-TargetCollection` | None. Required. | Device collections, as names or IDs. The order is the order of the waves. Each name must match exactly one device collection. |
| `-StartDate` | Tomorrow | The start date of wave 1. |
| `-WaveSpacingDays` | 7 | 0 to 365. |
| `-DeadlineDays` | 3 | 0 to 365. |
| `-MinimumSeverity` | 0 | One of 0 (All), 2 (Low), 6 (Moderate), 8 (Important), 10 (Critical). |
| `-OutputPath` | `update-plan.json` in the current folder | The JSON file. The Markdown file uses the same name. |
| `-IncludeWsus` | Off | Also reads update counts from the WSUS server. |
| `-Apply` | Off | Creates the deployments. |

The script has no parameter for the most updates in a wave. It uses 1000.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | The script finished. |
| 1 | A step failed. The message is on the error stream. |

## Limits

- A name that matches no collection, more than one collection, or a collection that is not a device collection stops the script.

## Troubleshooting

| Message | Cause | Fix |
|---|---|---|
| Target collection "<name>" matched 0 collections. It must match exactly one. | The name has no match. | Check the name, or use the collection ID. |
| A positional parameter cannot be found that accepts argument | A list of collections was passed to `-File` as one text. | Start the script from a PowerShell prompt, or use `-Command`. |

## Links

- [about_CommonParameters](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters): Describes `-WhatIf` and `-Confirm`.
