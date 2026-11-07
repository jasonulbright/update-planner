# Settings

This page lists every setting of Update Planner with its default and the place where it is stored.

## What it does

The tool saves its settings in `UpdatePlanner.prefs.json` and the window state in `UpdatePlanner.windowstate.json`. Both files are in the folder of the script. The files are plain JSON. The tool creates them on first use.

## When to use it

Use this page to find where a setting lives, or to reset the tool.

## Requirements

Write access for your account to the folder of the script.

## Settings

| Setting | Where in the window | Key in `UpdatePlanner.prefs.json` | Default | Saved |
|---|---|---|---|---|
| Theme | Toggle at the bottom of the sidebar | `DarkMode` | `true` (dark) | At once |
| SMS Provider | **Options**, **SMS Provider FQDN** | `SMSProvider` | Empty, or `SUITE_CM_PROVIDER` | **OK** in Options |
| Site code | **Options**, **Site Code** | `SiteCode` | Empty, or `SUITE_CM_SITECODE`. Required. | **OK** in Options |
| Days between waves | **Plan**, **Days between waves** | `WaveSpacingDays` | `7` | **Build plan** and window close |
| Days to deadline | **Plan**, **Days to deadline** | `DeadlineDays` | `3` | **Build plan** and window close |
| Lowest severity | **Plan**, **Lowest severity** | `Severity` | `All` | **Build plan** and window close |
| Most updates per wave | **Plan**, **Most updates per wave** | `MaxUpdates` | `1000` | **Build plan** and window close |
| Include WSUS counts | **Plan**, **Include WSUS counts** | `IncludeWsus` | `false` | **Build plan** and window close |
| Wave list | **Plan**, wave list | `Waves`: a list of `<collection ID>\|<name>` | Empty | At each change of the list |

The wave 1 start date is not saved. It starts as tomorrow at each start. **Enable actions** is not saved. It starts off.

### Window state

| Key in `UpdatePlanner.windowstate.json` | Content |
|---|---|
| `Width`, `Height`, `Left`, `Top` | The size and the position of the window. |
| `Maximized` | `true` when the window was maximized. |
| `ActiveView` | `Plan`, `Report` or `Deploy`. The window opens on this page. |

### Environment variables

| Variable | Effect |
|---|---|
| `SUITE_CM_PROVIDER` | Fills an empty SMS Provider. The suite launcher sets it. |
| `SUITE_CM_SITECODE` | Fills an empty site code. The suite launcher sets it. |

A value that is saved in `UpdatePlanner.prefs.json` wins over a variable.

## Steps

### Reset the tool

1. Close the tool.
2. Delete `UpdatePlanner.prefs.json` and `UpdatePlanner.windowstate.json`.
3. Start the tool. It opens with the defaults.

## Limits

The file is read at start. A change to the file while the tool runs is overwritten at the next save.

## Troubleshooting

| Message | Cause | Fix |
|---|---|---|
| The window opens on the wrong page or in the wrong place. | `UpdatePlanner.windowstate.json` holds an old state. | Close the tool. Delete the file. Start the tool. |
| The provider is filled when you did not enter it. | `SUITE_CM_PROVIDER` is set. | Enter a provider in **Options**, or clear the variable. |

## Links

None.
