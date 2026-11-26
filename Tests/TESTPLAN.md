# Update Planner: test plan

Measured 2026-11-17 with `Invoke-Checks.ps1` (Pester 5.7.1, PSScriptAnalyzer 1.25.0) on a lab computer, with the window tests off. Counts are tests as run; each data row counts as one test.

| | Windows PowerShell 5.1 | PowerShell 7 |
|---|---|---|
| Passed | 495 | 485 |
| Skipped (window tests, opt-in off) | 128 | 127 |

Run: `.\Invoke-Checks.ps1` (lint, then tests). It runs in CI on both hosts (`.github/workflows/ci.yml`).

Window tests: `Window.Tests.ps1` and the other `*.Window.Tests.ps1` files open windows only when `SUITE_ALLOW_WINDOW_TESTS` is `1`. The CI workflow sets it. Otherwise Pester reports those tests as Skipped with that reason, not as Failed. `WindowGuard.Tests.ps1` tests the guard and checks that every test file that can open a window applies it. It opens no window. `ButtonStates.Window.Tests.ps1` needs the real mouse and runs only in a visible run (`SUITE_VISIBLE_WINDOWS=1`, the labadmin session of CLIENT01).

## What is covered

| Area | File | Contents |
|---|---|---|
| Module | `UpdatePlannerCommon.Tests.ps1` | The module functions with stubbed ConfigMgr commands, including `-WhatIf` on the plan and deployment writes |
| Shell logic | `Shell.Logic.Tests.ps1` | The functions of `start-updateplanner.ps1`, cut from its syntax tree and run on stand-in controls: preferences file, status bar, control state, wave list, report text, action log |
| Script contract | `Script.Contract.Tests.ps1` | Every call with named parameters in the start script and the module matches the real function signature |
| Start-up | `Startup.Tests.ps1` | No console: plain message, console check before the window, exit code 2, no site call on bad input |
| Module and window | `UpdatePlannerWindow.Tests.ps1` | The module calls that the window makes |
| Windows | `Window.Tests.ps1` | Main window and Options dialog, both themes, 1024x720 and the work area: names, titles, no clipped text, nothing off screen, contrast |
| Chrome | `Chrome.Window.Tests.ps1` | Chrome and buttons of the main window and of every dialog, both themes |
| Density | `Density.Tests.ps1`, `Density.Window.Tests.ps1` | The compact 1080p layout from the XAML, and measured on screen with vacant-space checks |
| Button states | `ButtonStates.Window.Tests.ps1` | Hover, focus and pressed fills of the main window buttons, both themes (visible run only) |
| Window guard | `WindowGuard.Tests.ps1` | The opt-in guard and its use in every window test file |
| Theme guards | `Theme.Guard.Tests.ps1`, `Theme.Source.Guard.Tests.ps1`, `ButtonStyle.Guard.Tests.ps1`, `FontWeight.Guard.Tests.ps1`, `Footer.Guard.Tests.ps1` | White text on blue, fonts independent of the theme, banned words, one themed button style (also in the vendored SuiteCommon dialogs), Title Case, bold only for field titles, the footer |
| Encoding | `Encoding.Guard.Tests.ps1` | Plain ASCII in every PowerShell file and every file that PowerShell reads |
| Documents and images | `Documentation.Tests.ps1`, `Readme.Images.Guard.Tests.ps1`, `GuideImages.Guard.Tests.ps1` | Index and links, every README image is a guide image, every guide image was produced by a capture run |
| View data | `Show.View.Tests.ps1` | The rows that reach the controls, counted on real WPF controls that are not shown: a plan that the module builds from site data in `Show-Plan` (plan, skipped and preview grids, summary text, report, buttons), the results grid of `Show-DeployResult` and the wave list |
| Capture tool | `GuideCapture.Tests.ps1` | The capture scripts parse, carry no secret and take the lab lock |
| Capture processes | `ProcessJob.Tests.ps1` | A stop of the app ends its job. A process that records the app as its parent and is not in the job stays alive |

## Not covered, and why

- The tests stub the ConfigMgr commands. No test calls a real site. The module calls are not run in the lab.
- The refresh, the plan and the deploy handlers run inside the window with a site. The tests cover the module calls that they make, not the clicks.
- The window code of the start script (event handlers, the background run, the dialogs) is not run by the shell logic tests. The window tests open it.
- The settings save in SuiteCommon is not atomic. The fix belongs in `app-packager-suite`.