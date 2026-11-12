# Helpers of Theme.Guard.Tests.ps1. Dot-source from BeforeDiscovery and from BeforeAll.
# The helpers parse files. They create no WPF control, so they run on Windows PowerShell 5.1 and PowerShell 7.

$script:strRepoRoot = Split-Path -Path $PSScriptRoot -Parent
$script:arrThemeProperty = @('FontSize', 'FontWeight', 'FontStyle', 'TextDecorations', 'FontFamily', 'FontStretch')
$script:strBannedPattern = '(?i)\b(easily|simply|seamless(ly)?|powerful|robust|streamline[sd]?|streamlining|quickly|just|effortless(ly)?|intuitive(ly)?|handy|helps you|allows you to)\b'
$script:strXamlNamespace = 'http://schemas.microsoft.com/winfx/2006/xaml'

# The leaf of a property name: Border.Background, Controls:ControlsHelper.MouseOverBorderBrush and Background give the last word.
function Get-PropertyLeaf {
    param([string]$Name)
    if ([string]::IsNullOrEmpty($Name)) { return '' }
    return ($Name -split '[.:]')[-1]
}

# True when a brush value names an accent or a blue color.
function Test-BlueBrush {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    if ($Value -match 'MahApps\.(Brushes|Colors)\.(Accent\d*|AccentBase|Highlight\d*|Button\.Flat\.Background\.Pressed)\b') { return $true }
    if ($Value -match 'SystemColors\.Highlight(Brush|Color)Key') { return $true }
    if ($Value -match '(?i)^\s*(blue|dodgerblue|royalblue|steelblue|navy|mediumblue|darkblue|cornflowerblue|deepskyblue|lightskyblue|skyblue)\s*$') { return $true }
    $strHex = $Value.Trim()
    if ($strHex -match '^#([0-9A-Fa-f])([0-9A-Fa-f])([0-9A-Fa-f])$') { $strHex = '#{0}{0}{1}{1}{2}{2}' -f $Matches[1], $Matches[2], $Matches[3] }
    if ($strHex -match '^#(?:[0-9A-Fa-f]{2})?([0-9A-Fa-f]{2})([0-9A-Fa-f]{2})([0-9A-Fa-f]{2})$') {
        $dblRed = [Convert]::ToInt32($Matches[1], 16) / 255.0
        $dblGreen = [Convert]::ToInt32($Matches[2], 16) / 255.0
        $dblBlue = [Convert]::ToInt32($Matches[3], 16) / 255.0
        $dblMax = [Math]::Max($dblRed, [Math]::Max($dblGreen, $dblBlue))
        $dblMin = [Math]::Min($dblRed, [Math]::Min($dblGreen, $dblBlue))
        $dblDelta = $dblMax - $dblMin
        if ($dblDelta -lt 0.2 -or $dblMax -eq 0) { return $false }
        if ($dblMax -ne $dblBlue) { return $false }
        $dblHue = 60.0 * (4.0 + (($dblRed - $dblGreen) / $dblDelta))
        return ($dblHue -ge 190 -and $dblHue -le 260)
    }
    return $false
}

function Test-WhiteBrush {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    return ($Value -match '(?i)^\s*(white|#FFFFFF|#FFFFFFFF|#FFF)\s*$' -or $Value -match 'MahApps\.Brushes\.(Ideal|ThemeIdeal)Foreground')
}

# The value of a Setter: the Value attribute, or the Color attribute of a nested brush element at any depth.
function Get-SetterValue {
    param($Setter)
    if ($Setter.HasAttribute('Value')) { return $Setter.GetAttribute('Value') }
    $objNode = $Setter.SelectSingleNode('.//*[@Color]')
    if ($objNode) { return $objNode.GetAttribute('Color') }
    return ''
}

# The direct Setter children of a node whose property leaf matches a pattern.
function Get-SetterChild {
    param($Node, [string]$LeafPattern)
    if (-not $Node) { return @() }
    return @($Node.ChildNodes | Where-Object { $_.LocalName -eq 'Setter' -and (Get-PropertyLeaf $_.GetAttribute('Property')) -match $LeafPattern })
}

# The files of the repository below a folder, with the path relative to the repository root. The filter works on the
# relative path, so a worktree below .claude does not exclude itself.
function Get-RepoFile {
    param([string]$Filter, [string[]]$Skip = @('.claude', '.git'))
    $strRoot = $script:strRepoRoot.TrimEnd('\')
    # The top level is read first, so that a skipped folder (.claude holds worktrees) is never walked.
    foreach ($objTop in @(Get-ChildItem -LiteralPath $strRoot -Force)) {
        if ($Skip -contains $objTop.Name) { continue }
        $arrFile = @()
        if ($objTop.PSIsContainer) { $arrFile = @(Get-ChildItem -LiteralPath $objTop.FullName -Filter $Filter -File -Recurse) }
        elseif ($objTop.Name -like $Filter) { $arrFile = @($objTop) }
        foreach ($objFile in $arrFile) {
            $strRelative = $objFile.FullName.Substring($strRoot.Length + 1)
            [PSCustomObject]@{ File = $objFile; Relative = $strRelative; Top = ($strRelative -split '\\')[0] }
        }
    }
}

# Every XAML document of the repository: the XAML files and the XAML here-strings of the scripts.
function Get-XamlDocument {
    $arrDoc = @()
    foreach ($objItem in @(Get-RepoFile -Filter '*.xaml')) {
        $arrDoc += [PSCustomObject]@{ Source = $objItem.File.Name; Text = (Get-Content -LiteralPath $objItem.File.FullName -Raw) }
    }
    foreach ($strFilter in '*.ps1', '*.psm1') {
        foreach ($objItem in @(Get-RepoFile -Filter $strFilter -Skip @('.claude', '.git', 'Tests', 'tools'))) {
            $strRaw = Get-Content -LiteralPath $objItem.File.FullName -Raw
            $intIndex = 0
            foreach ($objMatch in [regex]::Matches($strRaw, "(?s)@'\r?\n(\s*<[^\r\n]*Window.*?)\r?\n'@")) {
                $intIndex++
                $arrDoc += [PSCustomObject]@{ Source = ('{0} here-string {1}' -f $objItem.File.Name, $intIndex); Text = $objMatch.Groups[1].Value }
            }
        }
    }
    return $arrDoc
}

# Resolves {StaticResource Key} to the key.
function Get-ResourceKey {
    param([string]$Value)
    if ($Value -match '^\{(?:Static|Dynamic)Resource\s+([^}\s]+)\}$') { return $Matches[1] }
    return ''
}

# A Foreground setter of the same scope is white: a sibling Setter, or a Setter of the enclosing Style.
function Test-WhiteForegroundInScope {
    param($Setter)
    $arrScope = @($Setter.ParentNode)
    $objStyle = $Setter.ParentNode
    while ($objStyle -and $objStyle.LocalName -ne 'Style' -and $objStyle.LocalName -ne 'ControlTemplate') { $objStyle = $objStyle.ParentNode }
    if ($objStyle) { $arrScope += $objStyle }
    foreach ($objScope in $arrScope) {
        foreach ($objForeground in @(Get-SetterChild -Node $objScope -LeafPattern 'Foreground$')) {
            if (Test-WhiteBrush (Get-SetterValue $objForeground)) { return $true }
        }
    }
    return $false
}

# Returns one text per blue-background rule that has no white foreground. It reads Setter nodes of styles, templates and
# triggers (also with a qualified property such as Border.Background or Controls:ControlsHelper.MouseOverBackground and with a nested brush
# whose Color attribute is at any depth), attributes of elements, and property elements such as <Border.Background>.
function Get-BlueWithoutWhite {
    param([string]$Text, [string]$Source)
    [xml]$xml = $Text
    $listFound = New-Object System.Collections.Generic.List[string]
    $strContainer = '^(Border|Grid|StackPanel|DockPanel|WrapPanel|Canvas|UniformGrid)$'
    foreach ($objElement in @($xml.SelectNodes('//*'))) {
        if ($objElement.LocalName -eq 'Setter') {
            if ((Get-PropertyLeaf $objElement.GetAttribute('Property')) -match 'Background$') {
                $strValue = Get-SetterValue $objElement
                if ((Test-BlueBrush $strValue) -and -not (Test-WhiteForegroundInScope $objElement)) {
                    [void]$listFound.Add(('{0}: Setter {1} {2} in <{3}> has no white Foreground' -f $Source, $objElement.GetAttribute('Property'), $strValue, $objElement.ParentNode.LocalName))
                }
            }
            continue
        }
        if ($objElement.LocalName -match '\.\w*Background$') {
            $objBrush = $objElement.SelectSingleNode('.//*[@Color]')
            if ($objBrush -and (Test-BlueBrush $objBrush.GetAttribute('Color')) -and $objElement.ParentNode -and -not (Test-WhiteBrush $objElement.ParentNode.GetAttribute('Foreground'))) {
                [void]$listFound.Add(('{0}: <{1}> has a blue brush and its owner has no white Foreground' -f $Source, $objElement.LocalName))
            }
            continue
        }
        foreach ($objAttribute in @($objElement.Attributes | Where-Object { (Get-PropertyLeaf $_.Name) -match 'Background$' })) {
            if (-not (Test-BlueBrush $objAttribute.Value)) { continue }
            $strOwnForeground = ''
            foreach ($objForeground in @($objElement.Attributes | Where-Object { (Get-PropertyLeaf $_.Name) -match 'Foreground$' })) {
                if (Test-WhiteBrush $objForeground.Value) { $strOwnForeground = $objForeground.Value }
            }
            if ($strOwnForeground) { continue }
            # A container has no Foreground. Its text elements must carry the white foreground themselves.
            if ($objElement.LocalName -match $strContainer) {
                $arrText = @($objElement.SelectNodes(".//*[local-name()='TextBlock' or local-name()='Label' or local-name()='ContentPresenter']"))
                $boolAllWhite = ($arrText.Count -gt 0)
                foreach ($objText in $arrText) { if (-not (Test-WhiteBrush $objText.GetAttribute('Foreground'))) { $boolAllWhite = $false } }
                if ($boolAllWhite) { continue }
            }
            [void]$listFound.Add(('{0}: <{1}> {2} {3} has no white Foreground' -f $Source, $objElement.LocalName, $objAttribute.Name, $objAttribute.Value))
        }
    }
    return $listFound.ToArray()
}

# Returns the text of a script without comment lines and block comments, so that a match cannot come from a comment.
function Remove-ScriptComment {
    param([string]$Text)
    $strText = [regex]::Replace($Text, '(?s)<#.*?#>', '')
    return (($strText -split "\r?\n" | Where-Object { $_ -notmatch '^\s*#' }) -join "`n")
}

# Every string of a script: the constant strings and the text parts of expandable strings.
function Get-ScriptString {
    param([string]$Path)
    $objAst = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$null)
    $arrNode = $objAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.StringConstantExpressionAst] -or $n -is [System.Management.Automation.Language.ExpandableStringExpressionAst] }, $true)
    foreach ($objNode in $arrNode) { [string]$objNode.Value }
}

# The text a user can read in a XAML document: tooltips and text attributes.
function Get-XamlUiText {
    param([string]$Text)
    [xml]$xml = $Text
    foreach ($objElement in @($xml.SelectNodes('//*'))) {
        foreach ($objAttribute in @($objElement.Attributes)) {
            if ($objAttribute.LocalName -match '^(ToolTip|Text|Content|Header|Title|Watermark|OnContent|OffContent|ToolTipService.*)$' -or $objAttribute.Name -match 'Watermark$') {
                if ($objAttribute.Value -notmatch '^\{') { $objAttribute.Value }
            }
        }
    }
}

# Returns one text per assignment of a blue string literal to a Background property in a script.
function Get-ScriptBlueBackground {
    param([string]$Path)
    $objAst = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$null)
    $arrAssign = $objAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left -is [System.Management.Automation.Language.MemberExpressionAst] }, $true)
    foreach ($objAssign in $arrAssign) {
        if ([string]$objAssign.Left.Member.Value -ne 'Background') { continue }
        # A white or ideal foreground set on the same control in the same block makes the blue background safe.
        $strTarget = $objAssign.Left.Expression.Extent.Text
        $arrSibling = @()
        if ($objAssign.Parent.PSObject.Properties['Statements']) { $arrSibling = @($objAssign.Parent.Statements | Where-Object { $_ -is [System.Management.Automation.Language.AssignmentStatementAst] -and $_.Left -is [System.Management.Automation.Language.MemberExpressionAst] }) }
        $arrWhite = @($arrSibling | Where-Object { [string]$_.Left.Member.Value -eq 'Foreground' -and $_.Left.Expression.Extent.Text -eq $strTarget -and $_.Right.Extent.Text -match '(?i)IdealForeground|White|#FFFFFF' })
        if ($arrWhite.Count -gt 0) { continue }
        $arrString = $objAssign.Right.FindAll({ param($n) $n -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true)
        foreach ($objString in $arrString) {
            if (Test-BlueBrush ([string]$objString.Value)) { '{0}:{1}: Background {2}' -f (Split-Path -Leaf $Path), $objAssign.Extent.StartLineNumber, $objString.Value }
        }
    }
}

# Returns one text per style that is based on a MahApps accent button and has no white foreground.
function Get-AccentButtonWithoutWhite {
    param([string]$Text, [string]$Source)
    [xml]$xml = $Text
    $listFound = New-Object System.Collections.Generic.List[string]
    foreach ($objStyle in @($xml.SelectNodes("//*[local-name()='Style']"))) {
        if ($objStyle.GetAttribute('BasedOn') -notmatch 'Button\.(Square\.|Flat\.)?Accent') { continue }
        $objForeground = Get-SetterChild -Node $objStyle -LeafPattern '^Foreground$' | Select-Object -First 1
        if (-not $objForeground -or -not (Test-WhiteBrush (Get-SetterValue $objForeground))) {
            [void]$listFound.Add(('{0}: accent button style {1} has no white Foreground' -f $Source, $objStyle.GetAttribute('Key', $script:strXamlNamespace)))
        }
    }
    return $listFound.ToArray()
}

# True when a style node has a trigger on the property (IsSelected, IsHighlighted) that sets a blue Background and a white Foreground.
function Test-StateTrigger {
    param($Style, [string]$Property)
    foreach ($objTrigger in @($Style.SelectNodes(".//*[local-name()='Trigger'][@Property='$Property']"))) {
        $objBackground = Get-SetterChild -Node $objTrigger -LeafPattern '^Background$' | Select-Object -First 1
        $objForeground = Get-SetterChild -Node $objTrigger -LeafPattern '^Foreground$' | Select-Object -First 1
        if ($objBackground -and (Test-BlueBrush (Get-SetterValue $objBackground)) -and $objForeground -and (Test-WhiteBrush (Get-SetterValue $objForeground))) { return $true }
    }
    return $false
}

# Returns one text per list, combo box, tree, grid row or grid cell without a selected-state style. Each item control of a
# document takes an explicit item container style (a base style is not enough, MahApps sets its own); the style has a
# blue background with a white foreground for IsSelected, and for a combo box item also for IsHighlighted.
function Get-SelectedStateViolation {
    param([string]$Text, [string]$Source)
    [xml]$xml = $Text
    $listFound = New-Object System.Collections.Generic.List[string]
    $hashStyle = @{}
    foreach ($objStyle in @($xml.SelectNodes("//*[local-name()='Style'][@*[local-name()='Key']]"))) { $hashStyle[$objStyle.GetAttribute('Key', $script:strXamlNamespace)] = $objStyle }
    $hashRule = @(
        @{ Control = 'ListBox'; Attribute = 'ItemContainerStyle'; Item = 'ListBoxItem'; Property = @('IsSelected') }
        @{ Control = 'ListView'; Attribute = 'ItemContainerStyle'; Item = 'ListViewItem'; Property = @('IsSelected') }
        @{ Control = 'ComboBox'; Attribute = 'ItemContainerStyle'; Item = 'ComboBoxItem'; Property = @('IsSelected', 'IsHighlighted') }
        @{ Control = 'TreeView'; Attribute = 'ItemContainerStyle'; Item = 'TreeViewItem'; Property = @('IsSelected') }
        @{ Control = 'DataGrid'; Attribute = 'CellStyle'; Item = 'DataGridCell'; Property = @('IsSelected') }
    )
    foreach ($hashControl in $hashRule) {
        foreach ($objElement in @($xml.SelectNodes(("//*[local-name()='{0}']" -f $hashControl.Control)))) {
            $strName = $objElement.GetAttribute('Name', $script:strXamlNamespace)
            $strKey = Get-ResourceKey $objElement.GetAttribute($hashControl.Attribute)
            if (-not $strKey -or -not $hashStyle.ContainsKey($strKey)) {
                [void]$listFound.Add(('{0}: {1} {2} has no {3}' -f $Source, $hashControl.Control, $strName, $hashControl.Attribute))
                continue
            }
            foreach ($strProperty in $hashControl.Property) {
                if (-not (Test-StateTrigger -Style $hashStyle[$strKey] -Property $strProperty)) {
                    [void]$listFound.Add(('{0}: style {1} of {2} {3} has no blue Background with white Foreground for {4}' -f $Source, $strKey, $hashControl.Control, $strName, $strProperty))
                }
            }
        }
    }
    foreach ($objElement in @($xml.SelectNodes("//*[local-name()='DataGrid']"))) {
        $strName = $objElement.GetAttribute('Name', $script:strXamlNamespace)
        $strGridStyle = Get-ResourceKey $objElement.GetAttribute('Style')
        $objRowStyle = $null
        if ($strGridStyle -and $hashStyle.ContainsKey($strGridStyle)) {
            $objRowSetter = Get-SetterChild -Node $hashStyle[$strGridStyle] -LeafPattern '^RowStyle$' | Select-Object -First 1
            if ($objRowSetter) { $strRowKey = Get-ResourceKey $objRowSetter.GetAttribute('Value'); if ($strRowKey -and $hashStyle.ContainsKey($strRowKey)) { $objRowStyle = $hashStyle[$strRowKey] } }
        }
        if (-not $objRowStyle -or -not (Test-StateTrigger -Style $objRowStyle -Property 'IsSelected')) {
            [void]$listFound.Add(('{0}: DataGrid {1} has no row style with a blue Background and a white Foreground for IsSelected' -f $Source, $strName))
        }
    }
    return $listFound.ToArray()
}

# Returns one text per button problem in a XAML document. Every Button has a Style whose chain of BasedOn
# styles ends at ThemedButtonStyle. ThemedButtonStyle is the only button style that is based on MahApps directly.
# No button, button style or button template has a literal color. Qualified properties and the Color attribute of a nested
# brush at any depth count.
function Get-ButtonThemeViolation {
    param([string]$Text, [string]$Source)
    [xml]$xml = $Text
    $listFound = New-Object System.Collections.Generic.List[string]
    $scriptIsLiteral = { param($v) ($v -match '^\s*#[0-9A-Fa-f]{3,8}\s*$') -or ($v -match '^\s*(White|Black|Red|Green|Blue|Gray|Grey|Transparent|Navy|Steel\w*|\w*Blue|Dark\w+|Light\w+)\s*$') }
    $hashStyle = @{}
    foreach ($objStyle in @($xml.SelectNodes("//*[local-name()='Style'][@TargetType='Button']"))) { $hashStyle[$objStyle.GetAttribute('Key', $script:strXamlNamespace)] = $objStyle.GetAttribute('BasedOn') }
    $scriptResolve = {
        param($key)
        $hashSeen = @{}
        while ($key -and -not $hashSeen.ContainsKey($key)) {
            if ($key -eq 'ThemedButtonStyle') { return $true }
            $hashSeen[$key] = $true
            if (-not $hashStyle.ContainsKey($key)) { return $false }
            $key = Get-ResourceKey $hashStyle[$key]
        }
        return $false
    }
    foreach ($strKey in @($hashStyle.Keys)) {
        if ($strKey -ne 'ThemedButtonStyle' -and $hashStyle[$strKey] -match 'MahApps\.') { [void]$listFound.Add(('{0}: Button style {1} is based on MahApps and not on ThemedButtonStyle' -f $Source, $strKey)) }
    }
    foreach ($objButton in @($xml.SelectNodes("//*[local-name()='Button']"))) {
        $strName = $objButton.GetAttribute('Name', $script:strXamlNamespace)
        $strKey = Get-ResourceKey $objButton.GetAttribute('Style')
        if (-not $strKey -or -not (& $scriptResolve $strKey)) {
            [void]$listFound.Add(('{0}: Button {1} does not take ThemedButtonStyle' -f $Source, $strName))
        }
        foreach ($objAttribute in @($objButton.Attributes)) {
            if ((Get-PropertyLeaf $objAttribute.Name) -match '(Background|Foreground|Brush)$' -and (& $scriptIsLiteral $objAttribute.Value)) { [void]$listFound.Add(('{0}: Button {1} sets {2} to the literal {3}' -f $Source, $strName, $objAttribute.Name, $objAttribute.Value)) }
        }
    }
    $arrScope = @($xml.SelectNodes("//*[local-name()='Style'][@TargetType='Button']")) + @($xml.SelectNodes("//*[local-name()='ControlTemplate'][@TargetType='Button']"))
    foreach ($objScope in $arrScope) {
        $strKey = $objScope.GetAttribute('Key', $script:strXamlNamespace)
        foreach ($objNode in @($objScope.SelectNodes('descendant-or-self::*'))) {
            foreach ($objAttribute in @($objNode.Attributes)) {
                $strLeaf = Get-PropertyLeaf $objAttribute.Name
                if ($strLeaf -eq 'Value') {
                    if ((Get-PropertyLeaf $objNode.GetAttribute('Property')) -notmatch '(Background|Foreground|Brush)$') { continue }
                }
                elseif ($strLeaf -notmatch '^(Color|Fill|Stroke)$' -and $strLeaf -notmatch '(Background|Foreground|Brush)$') { continue }
                if (& $scriptIsLiteral $objAttribute.Value) { [void]$listFound.Add(('{0}: {1} {2} uses the literal color {3}' -f $Source, $objScope.LocalName, $strKey, $objAttribute.Value)) }
            }
        }
    }
    return $listFound.ToArray()
}

# True when a UI title is in Title Case: each word starts with a capital letter or a digit, except the small words in the
# middle. A word of capitals (JSON) and a word with a dot (sms01.example.com) pass. The text may end with dots.
function Test-TitleCase {
    param([string]$Text)
    $strClean = ($Text -replace '\.\.\.$', '').Trim()
    if ([string]::IsNullOrWhiteSpace($strClean)) { return $true }
    $arrSmall = @('a', 'an', 'the', 'and', 'or', 'of', 'to', 'in', 'on', 'for', 'per', 'by', 'at', 'as', 'but', 'nor', 'with', 'from')
    $arrWord = @($strClean -split '\s+')
    for ($intIndex = 0; $intIndex -lt $arrWord.Count; $intIndex++) {
        $strWord = $arrWord[$intIndex].Trim(',', ':', '(', ')')
        if (-not $strWord) { continue }
        $boolEdge = ($intIndex -eq 0 -or $intIndex -eq $arrWord.Count - 1)
        if (-not $boolEdge -and ($arrSmall -contains $strWord)) { continue }
        if ($strWord -cnotmatch '^[A-Z0-9#<\[\(]') { return $false }
    }
    return $true
}

# The titles of a XAML document that must be in Title Case: button content, tab and column headers, field labels, window
# titles, check box, radio button and switch text. A binding or a name with a dot stays out.
function Get-XamlTitle {
    param([string]$Text)
    [xml]$xml = $Text
    foreach ($objElement in @($xml.SelectNodes('//*'))) {
        $strName = $objElement.LocalName
        $strValue = ''
        if ($strName -in 'Button', 'CheckBox', 'RadioButton', 'ToggleButton') { $strValue = $objElement.GetAttribute('Content') }
        elseif ($strName -in 'DataGridTextColumn', 'DataGridCheckBoxColumn', 'DataGridTemplateColumn') { $strValue = $objElement.GetAttribute('Header') }
        elseif ($strName -eq 'ToggleSwitch') { $strValue = $objElement.GetAttribute('Header') }
        elseif ($strName -eq 'MetroWindow' -or $strName -eq 'Window') { $strValue = $objElement.GetAttribute('Title') }
        elseif ($strName -eq 'TextBlock' -and ($objElement.GetAttribute('Style') -match 'FieldLabelStyle|OptLabel' -or $objElement.ParentNode.LocalName -eq 'TabItem.Header')) { $strValue = $objElement.GetAttribute('Text') }
        if ($strValue -and $strValue -notmatch '^\{' -and $strValue -notmatch '^(On|Off)$') { $strValue }
    }
}

# Returns one text per call of a UI command (a log line, the status text, a message box, a confirmation) that carries the
# text of an exception: $_, an Exception property, an error message variable.
function Get-UiExceptionText {
    param([string]$Path, [string[]]$Command = @('Add-LogLine', 'Set-StatusText', 'Show-ThemedMessage', 'Show-ConfirmDialog'))
    $objAst = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$null)
    $arrCall = $objAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $Command -contains $n.GetCommandName() }, $true)
    foreach ($objCall in $arrCall) {
        if ($objCall.Extent.Text -match '\$_(?![\w])|\$PSItem|Exception|ErrorMsg|\$err\b|\$ex\b') { '{0}:{1}: {2}' -f (Split-Path -Leaf $Path), $objCall.Extent.StartLineNumber, $objCall.Extent.Text }
    }
}
