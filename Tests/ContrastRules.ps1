# The contrast rules of the window tests. Text must reach 4.5:1 (3:1 for large text) and a
# control border 3:1, enabled and disabled, in both themes. The title text must reach 4.5:1
# on the active and on the inactive title bar. There is no list of accepted defects: every
# violation fails the test. Window.Tests.ps1 and Show-ContrastViolations.ps1 both call
# Get-ContrastViolation, so the printed list always matches what the test checks.

function Test-LargeText {
    # WCAG large text: 24 px, or 18.66 px and bold. It needs 3:1; other text needs 4.5:1.
    param([Parameter(Mandatory)]$Row)
    return ($Row.Size -ge 24 -or ($Row.Bold -and $Row.Size -ge 18.66))
}

function Get-ContrastViolation {
    # One line per violation. $Views are measured views or panes (Text, Interactive and TitleBar).
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Views)
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($v in $Views) {
        $where = if ($v.PSObject.Properties['View']) { $v.View } elseif ($v.PSObject.Properties['Pane']) { $v.Pane } else { '' }
        foreach ($r in @($v.Text)) {
            if ($null -eq $r) { continue }
            $min = if (Test-LargeText $r) { 3.0 } else { 4.5 }
            if ($r.Ratio -lt $min) { [void]$lines.Add(('{0}: text "{1}" ({2}) {3} on {4} = {5}' -f $where, $r.Text, $r.Name, $r.Foreground, $r.Backdrop, $r.Ratio)) }
        }
        foreach ($c in @($v.Interactive)) {
            if ($null -eq $c) { continue }
            foreach ($metric in 'EnabledText', 'DisabledText', 'EnabledBorder', 'DisabledBorder') {
                $value = $c.$metric
                if ($null -eq $value) { continue }
                $min = if ($metric -like '*Text') { 4.5 } else { 3.0 }
                if ($value -lt $min) { [void]$lines.Add(('{0}: {1} {2} {3} = {4}' -f $where, $c.Name, $metric, $c.PSObject.Properties[$metric + 'Colors'].Value, $value)) }
            }
        }
    }
    $first = @($Views | Where-Object { $_ }) | Select-Object -First 1
    if ($first -and $first.TitleBar) {
        foreach ($state in 'Active', 'Inactive') {
            $value = $first.TitleBar.$state
            if ($null -ne $value -and $value -lt 4.5) { [void]$lines.Add(('title bar {0} = {1}' -f $state.ToLowerInvariant(), $value)) }
        }
    }
    return @($lines | Sort-Object -Unique)
}
