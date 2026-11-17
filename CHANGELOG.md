# Changelog

All notable changes to Update Planner are documented in this file.

## [Unreleased]

### Changed

- Compact density for a 1080p work area: 36 px sidebar, 26 px controls, 24 px rows.
- Open maximized on first start; the Deploy view shares its free height between both grids.
- Capture the maximized window; the capture reports a verdict and the images it produced.
- Retake the guide and README images at the 1080p work area, light state images added.

### Added

- Test the density and the vacant area of every view at the work area.
- List the guide images that no capture run produced.
- Show the hover and pressed look of each button in the guide.
- Add the test plan.
- Test the shell logic, the script calls and the start-up without the console (Shell.Logic, Script.Contract and Startup tests).

### Fixed

- Guard the buttons of the vendored SuiteCommon dialogs: the check no longer skips them, and the vendored SuiteCommon gives its dialogs ThemedButtonStyle.
- Vendor SuiteCommon with the atomic settings save: the settings file is written to a temp file and replaced in one step, so a failed write cannot leave it truncated.
- Capture tool lock follows D-16: the lock text is owner|pid|start, a lock is stale only after 30 minutes with no running owner process, a live owner lock is never removed, a removed lock is reported, and the holder refreshes it.

## [2026.11.15.0013] - 2026-11-15

## 9 disabled controls now dim

### Changed

- Treat disabled controls as exempt from 4.5:1 text contrast and require them to look dimmed.
- Dim disabled text boxes, combo boxes and date pickers.

## [2026.11.15.0012] - 2026-11-15

## 44 guide images retaken with blue pressed buttons and the light inactive title bar

### Fixed

- Keep accent and neutral buttons blue or neutral when hovered or pressed, never black.
- Show the inactive light title bar in SuiteCommon blue with dark caption text.

### Added

- Judge button states and title bar text in both themes, for the main window and a dialog.
- Check the body of every dialog against the theme in the chrome window test.
- Guard that window tests open windows only inside try and finally.

### Changed

- Retake the 44 guide images, README images included, with the current buttons and title bar.
- Guard that every README image is a guide image that the capture tool produces.
- Close every window that a window test call leaves open.
- Sync the vendored SuiteCommon with the window body and cleanup helpers.
- Sync the vendored SuiteCommon with the inactive title bar and the button templates.
- Skip the text of disabled buttons in the contrast probe, because the templates dim them.

## [2026.11.14.0011] - 2026-11-14

## 44 guide images retaken with bordered dialog buttons

### Changed

- Retake the guide images with the shared dialog chrome borders.
- Sync the vendored SuiteCommon with the 1 px dialog button borders.

### Added

- Add window tests for the button states and the dialog chrome.

## [2026.11.14.0010] - 2026-11-14

## 44 guide images retaken with gray button borders

### Fixed

- Retake the guide images with 1 px gray button borders.

## [2026.11.14.0009] - 2026-11-14

## 1 px gray borders on every button in both themes

### Fixed

- Show button borders at 1 px in gray, not in the text color.
- Add guards for button styles, muted text brushes and the dialog theme call.
- Make the PowerShell sources and the files they read plain ASCII.
- Add the encoding guard.

## [2026.11.14.0008] - 2026-11-14

## 4.5:1 or more contrast on the inactive title bar in both themes

### Fixed

- Show the inactive title bar text at 4.5:1 contrast or more in both themes.
- Show text boxes, combo boxes and grid headers with the shared border and disabled-text styles.
- Let the window tests show their windows at 80,80 when SUITE_VISIBLE_WINDOWS is 1.
- Refresh the vendored SuiteCommon library to release 2026.11.13.0083.

## [2026.11.13.0007] - 2026-11-13

## 1 footer style for the status text and the site text

### Added

- Show the site code and the SMS Provider in the footer as one text, for example `Site ABC`, a middle dot, and `sms01.example.com`. The footer shows `Site not set` while a value is empty. Select the text to open Options.
- Add a guard test for the footer: one status element, no font setting on it, the footer calls, and no editable site field outside Options.

### Changed

- Replace the bold 14 pt site code and SMS Provider titles and the 12 pt site code in the footer with the one footer style of SuiteCommon. The status text no longer sets its own font size.
- Refresh the vendored SuiteCommon library to release 2026.11.13.0082.
- Retake the user guide images and the README screenshot.

### Fixed

- Show page headers, status and About text in the normal weight, not bold.
- Add a guard test that fails when text other than a field title is bold.
- Do nothing when you select the site text in the footer while an action runs. The Options button is off then, and so is the footer click.

## [2026.11.12.0006] - 2026-11-12

## 1 button style for every dialog and window

### Fixed

- Show white text on blue buttons in light mode.
- Keep text contrast when a button is hovered or pressed.
- Raise the dark theme button border to 3:1 contrast.
- Show field titles in bold 14 pt and field values in normal weight.
- Show no raw exception text in the window.

### Changed

- Use one themed style for every button and one secondary style for dialogs.
- Retake the user guide images.

### Added

- Add tests that guard button text and border contrast.

## [2026.11.10.0005] - 2026-11-10

## 44 user guide images retaken

### Fixed

- Show the app name, not Options, in the title of each Options message box.
- Meet 4.5:1 text and 3:1 border contrast on disabled buttons and tab headers.
- Meet 4.5:1 text and 3:1 border contrast in the light theme and the dark theme.
- Use the signed-in account for an SMS Provider on the same computer, not a credential.

### Added

- Add window tests for titles, centering, contrast and clipping. CI runs them.
- Add capture scripts in tools/guide-capture. One command retakes all guide images.

### Changed

- Correct the user guide against the code.
- Retake all 44 user guide images.

## [2026.11.07.0004] - 2026-11-07

## 1 user guide ships with the release

### Added

- Add the user guide (docs/index.md) with images of the running window.

## [2026.11.06.0003] - 2026-11-06

## 1 data access that uses the supported ConfigurationManager cmdlets

### Changed

- Read the site with the ConfigurationManager cmdlets (Get-CMSoftwareUpdate, Get-CMCollection, Get-CMCollectionMember, Get-CMMaintenanceWindow, Get-CMSoftwareUpdateDeployment, Get-CMSoftwareUpdateSyncStatus, Get-CMDeviceCollection, Get-CMFolder). The tool needs the Configuration Manager console on the computer.
- Read the update status of each device and the folder of each collection with Invoke-CMWmiQuery, because no cmdlet returns them.
- Create a software update group and a deployment of that group for each wave. The tool created one deployment without a group before.
- Require the site code in Options and in the command line script. The tool no longer asks the SMS Provider for it.
- Write the plan file as a Suite ring plan that Deployment Helper loads (docs/plan-format.md).

### Added

- Stop with a plain message at start when the console is not installed.
- Add ConvertFrom-UpdatePlanJson and Test-UpConsoleModule.

## [2026.11.06.0002] - 2026-11-06

## 5 defects fixed that the user guide found

### Fixed

- Show the full Plan subtitle when the window opens, not only after a change of view.
- Cut a long update title with an ellipsis in both grids and show the full title as a tooltip.
- Tab through Export JSON, Export Markdown and Export HTML in the order that the window shows them.
- Write "1 device" in the Markdown and HTML report for a collection of one device.
- Reset the Skipped updates tab header to "Skipped updates" when a change of the connection clears the plan.

## [2026.11.06.0001] - 2026-11-06

## 1 window app that plans update waves

### Added

- Open a window that plans software update rollouts in waves.
- Pick wave collections from a searchable folder tree.
- Set the start date, days between waves, days to deadline and lowest severity.
- Show the plan as a grid, a Markdown report and an HTML report.
- Export the plan as JSON, Markdown or HTML.
- Run a dry run of the deployment step with the WhatIf switch.
- Create the deployments after Enable actions is on and a confirmation.
- Block deployments to built-in collections.
- Write one action log record for each dry run and each deployment.
- Keep the command line script `Invoke-UpdatePlanner.ps1`.
