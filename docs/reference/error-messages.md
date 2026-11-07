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
| The site code is three letters or digits. | Dialog | The site code has another form. | Enter three letters or digits, or leave the box empty. |
| The SMS provider is a computer name or an FQDN. | Dialog | The provider holds a character that a name does not hold. | Enter a computer name or an FQDN. |

### Plan page

| Message | Where | Cause | Fix |
|---|---|---|---|
| Add: set the SMS provider and the site code in Options first. | Log | The provider or the site code is empty. | Set both in **Options**. |
| Load collections: set the SMS provider and the site code in Options first. | Log | The same. | The same. |
| Enter the SMS Provider computer name in Options. | Dialog **Build plan** and log | The provider is empty. | Set the provider in **Options**. |
| The Configuration Manager console is not installed on this computer. Update Planner reads the site with the ConfigurationManager PowerShell module, which comes only with the console. Install the console, then start Update Planner again. | Message box at start | The module is not found. | Install the console. |
| The start date is not a date. | Dialog **Build plan** | The start date box holds text. | Enter a date or select one in the calendar. |
| Days between waves must be a whole number from 0 to 365. | Dialog **Build plan** | The value is not a whole number in the range. | Enter a whole number from 0 to 365. |
| Days to the deadline must be a whole number from 0 to 365. | Dialog **Build plan** | The same. | The same. |
| The lowest severity must be All, Low, Moderate, Important or Critical. | Dialog **Build plan** | The list holds no valid choice. | Select a severity in the list. |
| The most updates in a wave must be a whole number from 1 to 1000. | Dialog **Build plan** | The value is not a whole number in the range. | Enter a whole number from 1 to 1000. |
| Add at least one wave collection. | Dialog **Build plan** | The wave list is empty. | Add a wave collection. |
| A collection is in the wave list more than once. | Dialog **Build plan** | The saved wave list holds the same collection twice. | Remove the duplicate. |
| <name> is already in the wave list. | Log | You added a collection that is in the list. | None. |
| Failed: <text> | Dialog and log | A site query failed. The text is the error of the site or of WinRM. | Read the text. Check the provider name and the rights. |
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
| Target collection "<name>" matched <n> collections. It must match exactly one. | A name has no match, or more than one match. | Use the collection ID. |
| Target collection "<name>" is not a device collection. | The name is a user collection. | Use a device collection. |
| The SMS Provider reports no local site code. | The provider has no local site. | Set `-SiteCode`. |
| Plan only. No change was made. Add -Apply to create the deployments. | A warning at the end of a plan without `-Apply`. | None. |

## Steps

1. Find the message in the tables.
2. Do the fix.

## Limits

The tool shows the error text of the site and of WinRM as it is. This page cannot list those texts.

## Troubleshooting

See [Troubleshooting](../troubleshooting.md).

## Links

None.
