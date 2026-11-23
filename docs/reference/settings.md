# Settings

This page lists every setting of Update Planner with its default and the place where it is stored.

## What it does

The tool saves its settings in `UpdatePlanner.prefs.json` and the window state in `UpdatePlanner.windowstate.json`. Both files are in the folder of the script. The site settings (the SMS Provider, the site code and the wave list) are saved for the site that the launcher chose, in `prefs.json` in the site data folder `%LOCALAPPDATA%\AppPackagerData\sites\<SITE>\tools\update-planner`, for example `sites\AB1\tools\update-planner`. See Sites in [Options](../core/options.md#sites). The files are plain JSON. The tool creates them on first use.

## When to use it

Use this page to find where a setting lives, or to reset the tool.

## Requirements

Write access for your account to the folder of the script and to your profile folder `%LOCALAPPDATA%`.

## Settings

| Setting | Where in the window | Key in `UpdatePlanner.prefs.json` | Default | Saved |
|---|---|---|---|---|
| Theme | Toggle at the bottom of the sidebar | `DarkMode` | `true` (dark) | At once |
| SMS Provider | **Options**, **SMS Provider FQDN** | `SMSProvider` (site setting) | The provider of the site. With no site chosen: empty, or `SUITE_CM_PROVIDER`. | **OK** in Options |
| Site code | **Options**, **Site Code** | `SiteCode` (site setting) | The site that the launcher chose, read-only. With no site chosen: empty, or `SUITE_CM_SITECODE`. Required. | **OK** in Options, when no site is chosen |
| Days Between Waves | **Plan**, **Days Between Waves** | `WaveSpacingDays` | `7` | **Build Plan** and window close |
| Days to Deadline | **Plan**, **Days to Deadline** | `DeadlineDays` | `3` | **Build Plan** and window close |
| Lowest Severity | **Plan**, **Lowest Severity** | `Severity` | `All` | **Build Plan** and window close |
| Most Updates per Wave | **Plan**, **Most Updates per Wave** | `MaxUpdates` | `1000` | **Build Plan** and window close |
| Include WSUS Counts | **Plan**, **Include WSUS Counts** | `IncludeWsus` | `false` | **Build Plan** and window close |
| Wave list | **Plan**, wave list | `Waves` (site setting): a list of `<collection ID>\|<name>` | Empty | At the next save of the file: **Build Plan**, **OK** in Options, the theme toggle or window close |

The site settings are `SiteCode`, `SMSProvider` and `Waves`. With a site chosen, the tool saves them in the site data folder, so that each site has its own wave list. The other keys stay in `UpdatePlanner.prefs.json`. A wave list holds collection IDs, which belong to one site.

The wave 1 start date is not saved. It starts as tomorrow at each start. **Enable Actions** is not saved. It starts off.

### Window state

| Key in `UpdatePlanner.windowstate.json` | Content |
|---|---|
| `Width`, `Height`, `Left`, `Top` | The size and the position of the window. |
| `Maximized` | `true` when the window was maximized. |
| `ActiveView` | `Plan`, `Report` or `Deploy`. The window opens on this page. |

### Environment variables

| Variable | Effect |
|---|---|
| `SUITE_CM_PROVIDER` | Fills an empty SMS Provider when no site is chosen. The suite launcher sets it. |
| `SUITE_CM_SITECODE` | Fills an empty site code when no site is chosen. The suite launcher sets it. |

A value that is saved in `UpdatePlanner.prefs.json` wins over a variable.

## Steps

### Reset the tool

1. Close the tool.
2. Delete `UpdatePlanner.prefs.json` and `UpdatePlanner.windowstate.json`. To reset the site settings of one site too, delete `prefs.json` in the site data folder of that site.
3. Start the tool. It opens with the defaults.

## Limits

The file is read at start. A change to the file while the tool runs is overwritten at the next save.

## Troubleshooting

| Message | Cause | Fix |
|---|---|---|
| The window opens on the wrong page or in the wrong place. | `UpdatePlanner.windowstate.json` holds an old state. | Close the tool. Delete the file. Start the tool. |
| The provider is filled when you did not enter it. | `SUITE_CM_PROVIDER` is set, or the site holds a provider. | Enter a provider in **Options**, or clear the variable. |

## Links

None.
