# Options dialog

The Options dialog sets the connection to the site and shows the version of the tool.

## What it does

The dialog has two sections, **Connection** and **About**. **Connection** holds the SMS Provider and the site code. **About** shows the version, a one-paragraph description, the author and the license.

## When to use it

Use the dialog at the first start, and when the SMS Provider or the site changes.

## Requirements

None. The dialog does not connect to the site.

## Steps

### Set the connection

1. Select **Options** in the sidebar. The button is off while a step runs.
2. Select **Connection**. The section has the heading **Configuration Manager Connection**.
3. In **SMS Provider FQDN**, enter a computer name or an FQDN. The characters are letters, digits, dot, hyphen and underscore. The watermark shows `e.g. sms01.example.com`.
4. In **Site Code**, enter the three letters or digits of the site code, for example `ABC`. The watermark shows `e.g. ABC. Three letters or digits.` The site code is required.
5. Select **OK**. **OK** is the default button: Enter selects it. Select **Cancel** to discard the change. Press Esc to cancel.
6. Read the right end of the footer. It shows the saved site, for example `Site ABC · sms01.example.com`, or `Site not set`. The footer is read-only. Select the site text to open Options. You change the site code and the SMS Provider only in this dialog.

![The Connection section of the Options dialog](../images/options-connection.png)

If the site code has the wrong form, a message box with the title **Update Planner** shows "The site code is three letters or digits." The dialog stays open. An empty site code is not checked here. **Load Collections**, **Add...** and **Build Plan** need it.

![The message for a wrong site code](../images/options-bad-site-code.png)

The message boxes of the dialog carry the title **Update Planner**, not the title of the dialog (**Options**). They show a warning sign and an **OK** button. They open in the center of the dialog. A message box of the main window has its own title too: a step that fails shows a message box with the title **Step Failed** and a fixed message. The log file holds the error text. A change of the provider or the site code clears the collection list, the plan, the grids and the report. The wave list stays. Load the collections and build the plan again. After a change of site, check each wave that stays: remove it and select it again when its collection is not the one that you mean.

### Read the version

1. Select **About**.
2. Read the version, for example `Update Planner v2026.11.07.0004`. The section also shows a one-paragraph description, the author and the license (MIT).

![The About section](../images/options-about.png)

### Options in the light theme

![The Options dialog in the light theme](../images/options-light.png)

## Options and settings of this page

| Control | Default | Effect |
|---|---|---|
| **SMS Provider FQDN** | Empty, or the value that the suite launcher hands over | The computer that runs the SMS Provider. Saved when you select **OK**. |
| **Site Code** | Empty, or the value that the suite launcher hands over | A three-character site code. Required. The tool no longer asks the provider for it. |

The text under the boxes says: the tool connects with the Windows account that runs it and stores no password; the tool needs the Configuration Manager console on this computer; a domain admin account that is a local administrator of the SMS Provider computer needs no Configuration Manager role; an account with fewer rights is not tested. This statement was tested on a lab site only. Check the roles and the scopes of the account in your site.

## Limits

- The dialog has no credential field. To use another account, start the tool as that account.
- A provider name that holds a query or a path is refused.

## Troubleshooting

| Message | Cause | Fix |
|---|---|---|
| The site code is three letters or digits. | The site code has another form. | Enter three letters or digits, or leave the box empty. |
| The SMS Provider is a computer name or an FQDN. | The provider holds a character that a name does not hold. | Enter a computer name or an FQDN. |

## Links

- [Plan for the SMS Provider](https://learn.microsoft.com/intune/configmgr/core/plan-design/hierarchy/plan-for-the-sms-provider): Explains what the SMS Provider is and where it runs.
