# Network

This page lists every outbound call of Update Planner.

## What it does

The page names each connection, its target and the reason.

## When to use it

Use this page to set a firewall rule or to check what the tool sends.

## Requirements

None.

## Calls

| Call | Target | When | Content |
|---|---|---|---|
| ConfigurationManager module | The SMS Provider computer, through the site drive that the console module opens. The ports are those of the console. | **Load Collections**, **Build Plan**, **Deploy...** and the command-line script. **Dry Run** and `-WhatIf` make no call. | `Get-CM*` reads and `Invoke-CMWmiQuery` (WQL `SELECT`). **Deploy...** also creates software update groups and deployments. |
| PowerShell remoting | The SMS Provider computer. On that computer, `Get-WsusServer` connects to `localhost` on port 8530. | **Build Plan** with **Include WSUS Counts** | A read of the update counts of the WSUS server. |
| `https://api.github.com/repos/<repository>/releases/latest` | GitHub | At the start of the window, once a day, only when the tool is installed by the suite installer | The check for a newer suite version. The result goes to the log. |

A plain extract of the zip (no `suite-manifest.json`) makes no call to GitHub. The tool sends no user data, no telemetry and no plan.

## Steps

### Check what the tool sends

1. Run the tool on a computer with no route to GitHub.
2. Build a plan. The plan builds, because the plan needs only the provider.

## Limits

The tool does not change a proxy setting. A failed update check is ignored.

## Troubleshooting

See [Troubleshooting](../troubleshooting.md).

## Links

- [Windows Remote Management](https://learn.microsoft.com/windows/win32/winrm/portal): Describes WinRM and its ports.
