# Error messages

This page lists the messages that Update Planner shows, grouped by area. Each row gives the message, where it appears, the cause and the fix.

- `<x>` marks a value that the tool inserts.
- For the most common messages, see also [Troubleshooting](../troubleshooting.md).

## What it does

The page lists the texts of the window dialogs, the log and the command-line script.

## When to use it

Use this page when the tool shows a message that you do not know.

## Requirements

None.

## Messages

### Options

| Message | Where | Cause | Fix |
|---|---|---|---|
| The site code is three letters or digits. | Message box **Update Planner** over **Options** | The site code has another form. | Enter three letters or digits, or leave the box empty. |
| The SMS provider is a computer name or an FQDN. | Message box **Update Planner** over **Options** | The provider holds a character that a name does not hold. | Enter a computer name or an FQDN. |

### Plan page

| Message | Where | Cause | Fix |
|---|---|---|---|
| Add: set the SMS provider and the site code in Options first. | Log | The provider or the site code is empty. | Set both in **Options**. |
| Load collections: set the SMS provider and the site code in Options first. | Log | The same. | The same. |
| Enter the SMS Provider computer name in Options. | Dialog **Build plan** and log | The provider is empty. | Set the provider in **Options**. |
| Enter the site code in Options. It is three letters or digits. | Dialog **Build plan** and log | The site code is empty. | Set the site code in **Options**. |
| The Configuration Manager console is not installed on this computer. Update Planner reads the site with the ConfigurationManager PowerShell module, which comes only with the console. Install the console, then start Update Planner again. | Message box **Update Planner** at start. The tool ends. | The module is not found. | Install the console. |
| The start date is not a date. | Dialog **Build plan** | The start date box holds text. | Enter a date or select one in the calendar. |
| Days between waves must be a whole number from 0 to 365. | Dialog **Build plan** | The value is not a whole number in the range. | Enter a whole number from 0 to 365. |
| Days to the deadline must be a whole number from 0 to 365. | Dialog **Build plan** | The same. | The same. |
| The lowest severity must be All, Low, Moderate, Important or Critical. | Dialog **Build plan** | The list holds no valid choice. | Select a severity in the list. |
| The most updates in a wave must be a whole number from 1 to 1000. | Dialog **Build plan** | The value is not a whole number in the range. | Enter a whole number from 1 to 1000. |
| Add at least one wave collection. | Dialog **Build plan** | The wave list is empty. | Add a wave collection. |
| A collection is in the wave list more than once. | Dialog **Build plan** | The saved wave list holds the same collection twice. | Remove the duplicate. |
| <name> is already in the wave list. | Log | You added a collection that is in the list. | None. |
| Failed: `<text>` | Log. The message box **Step failed** shows `<text>` alone. | A step failed. The text is the error of the site or of the ConfigurationManager module. | Read the text. Check the provider name and the rights. |
| Cannot open site `<site code>` on `<provider>`. Check the site code and the SMS Provider name in Options, and the account rights. `<text>` | Message box **Step failed** and log | The site drive did not open: a wrong site code or provider name, no route to the provider, or no rights. | Check the values in **Options** and the account rights. |
| Target collection "`<collection ID>`" matched 0 collections. It must match exactly one. | Message box **Step failed** and log | A wave collection no longer exists on the site, for example after a change of site. | Remove the wave. Add the collection again. |
| The step failed. See the log. | Status bar | The same. | The same. |

### Deploy page

| Message | Where | Cause | Fix |
|---|---|---|---|
| Deploy blocked: <wave>: the collection <ID> is built in. Deployments to built-in collections are blocked. | Dialog and log | A wave targets a collection whose ID starts with `SMS`. | Remove the wave. Build the plan again. |
| The plan holds no update to deploy. | Dialog **Deploy blocked** and log (the log line starts with "Deploy blocked:") | No wave holds an update. | Change the waves or the settings. Build the plan again. |
| Deploy cancelled. | Log | You selected **No**. | None. |
| The action log could not be written: <text> | Log | The `Logs` folder is not writable. | Give your account write access. |

### Command line

| Message | Cause | Fix |
|---|---|---|
| Target collection "`<name>`" matched `<n>` collections. It must match exactly one. | A name has no match, or more than one match. | Use the collection ID. |
| Target collection "`<name>`" is not a device collection. | The name is a user collection. | Use a device collection. |
| Plan only. No change was made. Add -Apply to create the deployments. | A warning at the end of a plan without `-Apply`. | None. |
| WSUS state is not available: `<text>` | A warning with `-IncludeWsus` when the WSUS read fails. The plan has no WSUS counts. | Check PowerShell remoting and the right to run `Get-WsusServer` on the provider. |
| `<wave>`: the collection `<ID>` is built in. Deployments to built-in collections are blocked. | `-Apply` without `-WhatIf` and a wave that targets a built-in collection. Nothing is created. | Remove the collection from `-TargetCollection`. |

## Steps

1. Find the message in the tables.
2. Do the fix.

## Limits

The tool shows the error text of the site, of the ConfigurationManager module and of PowerShell remoting as it is. This page cannot list those texts.

## Troubleshooting

See [Troubleshooting](../troubleshooting.md).

## Links

None.
