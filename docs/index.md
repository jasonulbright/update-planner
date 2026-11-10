# Update Planner documentation

Update Planner plans software update rollouts in waves for a Configuration Manager site. This page links every page of the documentation.

## Start

- [Getting started](getting-started.md): install, set the connection, build the first plan.

## Core

- [Plan page](core/plan.md): the wave collections, the collection picker, the plan settings and Build plan.
- [Plan grids](core/plan-grids.md): the Planned updates grid, the Skipped updates grid and the skip reasons.
- [Report and export](core/report-and-export.md): the Markdown and HTML report, Copy, Open HTML report and the three export buttons.
- [Deploy page](core/deploy.md): Enable actions, Dry run, Deploy... and the built-in collection block.
- [Options dialog](core/options.md): the SMS provider, the site code and About.
- [Command line](core/command-line.md): `Invoke-UpdatePlanner.ps1`, its parameters and its results.

## Reference

- [Plan format](reference/plan-format.md): the Suite ring plan that the JSON export writes.
- [Plan rules](reference/plan-rules.md): what the tool reads, how it builds a plan and what it does not do.
- [Settings](reference/settings.md): every setting with its default and where it is stored.
- [Permissions](reference/permissions.md): the rights that each action needs.
- [Network](reference/network.md): every outbound call.
- [Files and logs](reference/files-and-logs.md): every folder and file that the tool writes.
- [Keyboard](reference/keyboard.md): the Tab order and the dialog keys.
- [Error messages](reference/error-messages.md): message, cause and fix.
- [Glossary](reference/glossary.md): the terms of the tool.

## External references

- [External references](external-references.md): Microsoft Learn pages for each feature.

## Troubleshooting

- [Troubleshooting](troubleshooting.md): the most common messages with cause and fix.

## Retake the captures

One command regenerates every image in `docs/images`. Run it from the repository folder on the workstation. It copies the tool to a lab workstation, runs the capture steps in an interactive session there (a scheduled task), copies the images back and removes its files and the task from the lab workstation.

```powershell
.\tools\guide-capture\Invoke-GuideCapture.ps1 -CredentialScript <credential script> -Target <lab workstation> -LogonUser <domain\account> -SiteCode <site code> -SmsProvider <provider FQDN> -Waves '<collection 1>', '<collection 2>', '<collection 3>'
```

- The credential script is outside the repository. It sets `$LabCredential` to a PSCredential with PowerShell remoting rights on the lab workstation.
- The lab workstation needs the Configuration Manager console and a lab site with at least three device collections.
- The capture reads the site and runs a dry run. It opens the deploy confirmation and selects **No**. It never creates a deployment.
- The command replaces an image only when every step passed. It stops with the failed steps when a step failed.
