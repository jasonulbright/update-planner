# Changelog

All notable changes to Update Planner are documented in this file.

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
