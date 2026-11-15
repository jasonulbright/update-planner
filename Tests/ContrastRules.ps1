# The contrast rules of the window tests. Enabled text must reach 4.5:1 (3:1 for large text) and an
# enabled control border 3:1, in both themes. The title text must reach 4.5:1
# on the active and on the inactive title bar. There is no list of accepted defects: every
# violation fails the test. Window.Tests.ps1 and Show-ContrastViolations.ps1 both call
# Get-ContrastViolation, so the printed list always matches what the test checks.
# A disabled control is exempt from the contrast ratios: WCAG 2.x success criterion 1.4.3 does not apply to
# text or images of text that are part of an inactive user interface component. Instead, Get-DimmedViolation
# requires that a disabled control looks clearly dimmed, so that it reads as disabled.

# A disabled control must look dimmed: its text contrast is at most 1/1.25 of the enabled text contrast, and its
# label is still readable (1.5:1 or more).
function Get-DimmedViolation {
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Views)
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($v in $Views) {
        $where = if ($v.PSObject.Properties['View']) { $v.View } elseif ($v.PSObject.Properties['Pane']) { $v.Pane } else { '' }
        foreach ($c in @($v.Interactive)) {
            if ($null -eq $c -or $null -eq $c.EnabledText -or $null -eq $c.DisabledText) { continue }
            if ($c.DisabledText -lt 1.5) { [void]$lines.Add(('{0}: {1} disabled text {2} is not readable (1.5 or more)' -f $where, $c.Name, $c.DisabledText)) }
            elseif ($c.DisabledText -le 0 -or ($c.EnabledText / $c.DisabledText) -lt 1.25) { [void]$lines.Add(('{0}: {1} is not dimmed when disabled (enabled {2}, disabled {3}, ratio {4})' -f $where, $c.Name, $c.EnabledText, $c.DisabledText, [math]::Round($c.EnabledText / [math]::Max($c.DisabledText, 0.01), 2))) }
        }
    }
    return @($lines | Sort-Object -Unique)
}

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
            foreach ($metric in 'EnabledText', 'EnabledBorder') {
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
