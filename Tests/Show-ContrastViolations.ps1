<#
.SYNOPSIS
    Prints the contrast violations of the main window and of the Options dialog in both themes.

.DESCRIPTION
    Run it when the window test reports a contrast violation, to see the full list with the
    colours. Opens the windows off screen at 1440x900, as Window.Tests.ps1 does. It runs only
    with SUITE_ALLOW_WINDOW_TESTS=1: window tests run in CI or on the lab, not on a workstation.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Console tool.')]
param()
. "$PSScriptRoot\WindowHarness.ps1"
$guard = Test-WindowTestsAllowed
if (-not $guard.Allowed) { throw ('This tool opens windows and does not run here: {0}.' -f $guard.Reason) }
. "$PSScriptRoot\ContrastRules.ps1"
. "$PSScriptRoot\WindowConfig.ps1"
$root = Split-Path -Parent $PSScriptRoot
$shellPath = Join-Path $root $script:AppConfig.Shell
$shell = [System.IO.File]::ReadAllText($shellPath)
$dialogXaml = [regex]::Match($shell, "(?s)@'\s*(<Controls:MetroWindow.*?)\s*'@").Groups[1].Value
$brushes = Get-AppSuiteBrushOverride -ShellPath $shellPath
$sample = New-WindowSampleData
try {
    foreach ($dark in $true, $false) {
        $theme = if ($dark) { 'dark' } else { 'light' }
        $main = Invoke-WpfSta -Arguments @{ Dark = $dark; W = 1440; H = 900; Config = $script:AppConfig; Sample = $sample; Brushes = $brushes } -Script $script:MainMeasureScript
        Write-Host ("== main {0}" -f $theme)
        Get-ContrastViolation -Views @($main) | ForEach-Object { Write-Host $_ }
        $dlg = Invoke-WpfSta -Arguments @{ Xaml = $dialogXaml; Dark = $dark; Panes = $script:AppConfig.OptionsPanes; Brushes = $brushes } -Script $script:DialogMeasureScript
        $first = @($dlg)[0].Size
        Write-Host ("== dialog {0}" -f $theme)
        Get-ContrastViolation -Views @($dlg | Where-Object Size -eq $first) | ForEach-Object { Write-Host $_ }
    }
}
finally { Close-WpfSession }
