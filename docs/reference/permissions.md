# Permissions

This page lists the rights that each action of Update Planner needs.

## What it does

The page names the site rights, the computer rights and the file rights for each action.

## When to use it

Use this page to set up an account for the tool, or to find the cause of an access error.

## Requirements

None.

## Rights by action

| Action | Where | Right |
|---|---|---|
| Start | This computer | The Configuration Manager console (the ConfigurationManager module). Without it the tool ends at start with a message. |
| Load collections | The SMS Provider, through the ConfigurationManager module | A domain admin account that is a local administrator of the SMS Provider computer needs no Configuration Manager role. An account with fewer rights is not tested. The tool reads with `Get-CMCollection`, `Get-CMFolder` and `Invoke-CMWmiQuery`. |
| Build plan | The SMS Provider, the same way | Reads with `Get-CMSoftwareUpdate`, `Get-CMCollectionMember`, `Get-CMMaintenanceWindow`, `Get-CMSoftwareUpdateDeployment`, `Get-CMSoftwareUpdateSyncStatus` and `Invoke-CMWmiQuery` (a `SELECT` for the update status of each device). |
| Include WSUS counts | The provider computer (PowerShell remoting) | A right to run `Get-WsusServer` on the provider computer. Without it, the plan builds and the WSUS counts are missing. |
| Dry run | None beyond Build plan | Creates nothing. |
| Deploy... | The SMS Provider | The right to create software update groups and deployments (`New-CMSoftwareUpdateGroup`, `New-CMSoftwareUpdateDeployment`). |
| Reports, exports, logs | This computer | Write access to the folder of the script. |

Every read is a cmdlet or a `SELECT`. Building a plan changes nothing on the site.

The tool uses the Windows account that runs it. It stores no password and has no credential field. The command-line script accepts `-Credential`.

## Steps

### Check an account

1. Start the tool as the account.
2. Select **Load collections**. A list of collections shows that the account can read the site.
3. Select **Build plan**. A plan shows that the account can read the update state.

## Limits

The tool does not check the right to create deployments before **Deploy...**. The site refuses a deployment that the account may not create, and the **Message** column shows the reason.

## Troubleshooting

See [Troubleshooting](../troubleshooting.md).

## Links

- [Fundamentals of role-based administration](https://learn.microsoft.com/intune/configmgr/core/understand/fundamentals-of-role-based-administration): Describes the security roles and scopes.
