#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.1.0' }
# Guard tests for the theme rules. They parse the files and create no WPF control, so they run on
# Windows PowerShell 5.1 and PowerShell 7 and open no window.
#   (a) Every blue background in XAML and PowerShell has a white foreground, also in hover, pressed and selected states.
#   (b) No font size, weight, style or text decoration depends on the theme. The titles of the site code and the
#       SMS Provider are bold and 14 pt or larger. Their values are not.
#   (c) No banned word is in a tooltip, a UI string, the README or the user guide.
#   (d) Every button takes the shared themed style. Titles are in Title Case.
#   (e) No window text shows the text of an exception.

BeforeDiscovery {
    . "$PSScriptRoot\ThemeGuardHelpers.ps1"
    $script:arrPsFileD = @(
        'start-updateplanner.ps1', 'Invoke-UpdatePlanner.ps1', 'Module\UpdatePlannerCommon.psm1', 'Lib\SuiteCommon\SuiteCommon.psm1'
    ) | ForEach-Object { @{ Name = $_; Path = (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath $_) } }
    $script:arrAppPsFileD = @($script:arrPsFileD | Where-Object { $_.Name -notmatch 'SuiteCommon' })
    $script:arrXamlDocD = @(Get-XamlDocument)
    $script:arrOwnXamlDocD = @($script:arrXamlDocD | Where-Object { $_.Source -notmatch 'SuiteCommon' })
}

BeforeAll {
    . "$PSScriptRoot\ThemeGuardHelpers.ps1"
    $script:arrXamlDoc = @(Get-XamlDocument)
    $script:arrOwnXamlDoc = @($script:arrXamlDoc | Where-Object { $_.Source -notmatch 'SuiteCommon' })
    $script:strShellPath = Join-Path -Path $script:strRepoRoot -ChildPath 'start-updateplanner.ps1'
}

Describe 'Blue backgrounds have white text (a)' {
    It 'finds XAML to check' {
        $script:arrXamlDoc.Count | Should -BeGreaterThan 2
        @($script:arrXamlDoc | Where-Object { $_.Source -eq 'MainWindow.xaml' }).Count | Should -Be 1
        @($script:arrXamlDoc | Where-Object { $_.Source -like 'start-updateplanner.ps1 here-string*' }).Count | Should -BeGreaterOrEqual 1
    }

    It 'sets a white foreground on every blue background in <_.Source>' -ForEach $script:arrXamlDocD {
        $arrBad = @(Get-BlueWithoutWhite -Text $_.Text -Source $_.Source)
        $arrBad | Should -BeNullOrEmpty
    }

    It 'recognizes blue and white brushes' {
        Test-BlueBrush '{DynamicResource MahApps.Brushes.Accent}' | Should -BeTrue
        Test-BlueBrush '{DynamicResource MahApps.Colors.Accent}' | Should -BeTrue
        Test-BlueBrush '{DynamicResource MahApps.Colors.AccentBase}' | Should -BeTrue
        Test-BlueBrush '{DynamicResource MahApps.Brushes.Accent3}' | Should -BeTrue
        Test-BlueBrush '{DynamicResource MahApps.Brushes.Highlight}' | Should -BeTrue
        Test-BlueBrush '{DynamicResource {x:Static SystemColors.HighlightBrushKey}}' | Should -BeTrue
        Test-BlueBrush '#0078D4' | Should -BeTrue
        Test-BlueBrush '#FF0078D4' | Should -BeTrue
        Test-BlueBrush '#07D' | Should -BeTrue
        Test-BlueBrush '#1E1E1E' | Should -BeFalse
        Test-BlueBrush '#3A3A3A' | Should -BeFalse
        Test-BlueBrush '{DynamicResource MahApps.Brushes.ThemeBackground}' | Should -BeFalse
        Test-WhiteBrush '{DynamicResource MahApps.Brushes.IdealForeground}' | Should -BeTrue
        Test-WhiteBrush 'White' | Should -BeTrue
        Test-WhiteBrush 'Black' | Should -BeFalse
    }

    It 'flags a blue background that has no white foreground, with every property form' {
        $strOpen = '<Style xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:Controls="clr-namespace:MahApps.Metro.Controls;assembly=MahApps.Metro" TargetType="Button">'
        @(Get-BlueWithoutWhite -Text ($strOpen + '<Setter Property="Background" Value="#0078D4"/></Style>') -Source 's').Count | Should -Be 1
        @(Get-BlueWithoutWhite -Text ($strOpen + '<Setter Property="Background" Value="#0078D4"/><Setter Property="Foreground" Value="White"/></Style>') -Source 's').Count | Should -Be 0
        @(Get-BlueWithoutWhite -Text ($strOpen + '<Setter Property="Border.Background" Value="{DynamicResource MahApps.Brushes.Accent}"/></Style>') -Source 's').Count | Should -Be 1
        @(Get-BlueWithoutWhite -Text ($strOpen + '<Setter Property="Controls:ControlsHelper.MouseOverBackground" Value="{DynamicResource MahApps.Brushes.Accent}"/></Style>') -Source 's').Count | Should -Be 1
        @(Get-BlueWithoutWhite -Text ($strOpen + '<Setter Property="Background"><Setter.Value><SolidColorBrush Color="{DynamicResource MahApps.Colors.Accent}"/></Setter.Value></Setter></Style>') -Source 's').Count | Should -Be 1
        @(Get-BlueWithoutWhite -Text ($strOpen + '<Setter Property="Background"><Setter.Value><LinearGradientBrush><GradientStop Color="#0078D4"/></LinearGradientBrush></Setter.Value></Setter></Style>') -Source 's').Count | Should -Be 1
        @(Get-BlueWithoutWhite -Text ($strOpen + '<Style.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter Property="Background" Value="{DynamicResource MahApps.Brushes.Accent}"/></Trigger></Style.Triggers></Style>') -Source 's').Count | Should -Be 1
        @(Get-BlueWithoutWhite -Text ($strOpen + '<Style.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter Property="Background" Value="{DynamicResource MahApps.Brushes.Accent}"/><Setter Property="Foreground" Value="{DynamicResource MahApps.Brushes.IdealForeground}"/></Trigger></Style.Triggers></Style>') -Source 's').Count | Should -Be 0
        $strGrid = '<Grid xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation">'
        @(Get-BlueWithoutWhite -Text ($strGrid + '<Border Background="#0078D4"><TextBlock Text="x"/></Border></Grid>') -Source 's').Count | Should -Be 1
        @(Get-BlueWithoutWhite -Text ($strGrid + '<Border Background="#0078D4"><TextBlock Text="x" Foreground="White"/></Border></Grid>') -Source 's').Count | Should -Be 0
        @(Get-BlueWithoutWhite -Text ($strGrid + '<Button Background="{DynamicResource MahApps.Brushes.Accent}" Content="x"/></Grid>') -Source 's').Count | Should -Be 1
        @(Get-BlueWithoutWhite -Text ($strGrid + '<Border><Border.Background><SolidColorBrush Color="#0078D4"/></Border.Background></Border></Grid>') -Source 's').Count | Should -Be 1
    }

    It 'sets no blue color as a Background in <Name>, and each CSS rule with a blue background has white text' -ForEach $script:arrAppPsFileD {
        $arrBad = @(foreach ($strHit in @(Get-ScriptBlueBackground -Path $Path)) { 'background ' + $strHit })
        $arrBad += @(foreach ($strString in @(Get-ScriptString -Path $Path)) {
                foreach ($objMatch in [regex]::Matches($strString, '\{([^}]*)\}')) {
                    $strRule = $objMatch.Groups[1].Value
                    $objBackground = [regex]::Match($strRule, '(?i)(?<![-\w])background(?:-color)?\s*:\s*(#[0-9A-F]{6,8})\b')
                    if ($objBackground.Success -and (Test-BlueBrush $objBackground.Groups[1].Value) -and $strRule -notmatch '(?i)(?<![-\w])color\s*:\s*(#fff(fff)?|white)\b') { 'css ' + $strRule }
                }
            })
        $arrBad | Should -BeNullOrEmpty
    }

    It 'finds a blue Background assignment in a script' {
        $strTemp = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('themeguard-' + [guid]::NewGuid().ToString('N') + '.ps1')
        try {
            [System.IO.File]::WriteAllText($strTemp, "`$b.Background = '#0078D4'`n`$c.Foreground = '#0078D4'`n`$d.Background = '#1E1E1E'`n")
            @(Get-ScriptBlueBackground -Path $strTemp).Count | Should -Be 1
            [System.IO.File]::WriteAllText($strTemp, "`$b.Background = '#0078D4'`n`$b.Foreground = 'White'`n")
            @(Get-ScriptBlueBackground -Path $strTemp).Count | Should -Be 0
        }
        finally { Remove-Item -LiteralPath $strTemp -Force -ErrorAction SilentlyContinue }
    }

    It 'sets a white foreground on every accent button style outside SuiteCommon in <_.Source>' -ForEach $script:arrOwnXamlDocD {
        $arrBad = @(Get-AccentButtonWithoutWhite -Text $_.Text -Source $_.Source)
        $arrBad | Should -BeNullOrEmpty
    }

    It 'flags an accent button style that has no white foreground' {
        $strXaml = '<ResourceDictionary xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"><Style x:Key="A" TargetType="Button" BasedOn="{StaticResource MahApps.Styles.Button.Square.Accent}"><Setter Property="Height" Value="32"/></Style></ResourceDictionary>'
        @(Get-AccentButtonWithoutWhite -Text $strXaml -Source 'sample').Count | Should -Be 1
        $strOk = $strXaml.Replace('<Setter Property="Height" Value="32"/>', '<Setter Property="Foreground" Value="{DynamicResource MahApps.Brushes.IdealForeground}"/>')
        @(Get-AccentButtonWithoutWhite -Text $strOk -Source 'sample').Count | Should -Be 0
    }

    It 'sets the foreground of every selected-state trigger that sets a Background in <_.Source>' -ForEach $script:arrXamlDocD {
        [xml]$xml = $_.Text
        $arrBad = foreach ($objTrigger in @($xml.SelectNodes("//*[local-name()='Trigger'][@Property='IsSelected' or @Property='IsHighlighted' or @Property='IsMouseOver' or @Property='IsPressed']"))) {
            $objBackground = Get-SetterChild -Node $objTrigger -LeafPattern 'Background$' | Select-Object -First 1
            $objForeground = Get-SetterChild -Node $objTrigger -LeafPattern 'Foreground$' | Select-Object -First 1
            if ($objBackground -and -not $objForeground -and -not (Test-WhiteForegroundInScope $objBackground)) { '{0} trigger sets a Background and no Foreground' -f $objTrigger.GetAttribute('Property') }
        }
        @($arrBad) | Should -BeNullOrEmpty
    }

    It 'gives every list, combo box, tree and grid a selected state with white text on blue in <_.Source>' -ForEach $script:arrOwnXamlDocD {
        $arrBad = @(Get-SelectedStateViolation -Text $_.Text -Source $_.Source)
        $arrBad | Should -BeNullOrEmpty
    }

    It 'finds the item controls of the main window' {
        $objMain = @($script:arrXamlDoc | Where-Object { $_.Source -eq 'MainWindow.xaml' })[0]
        [xml]$xml = $objMain.Text
        foreach ($strControl in 'ListBox', 'ComboBox', 'DataGrid') {
            @($xml.SelectNodes(("//*[local-name()='{0}']" -f $strControl))).Count | Should -BeGreaterThan 0 -Because $strControl
        }
    }

    It 'flags a combo box without the IsHighlighted state and a list without an item container style' {
        $strOpen = '<Grid xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">'
        $strSelected = '<Trigger Property="IsSelected" Value="True"><Setter Property="Background" Value="{DynamicResource MahApps.Brushes.Accent}"/><Setter Property="Foreground" Value="{DynamicResource MahApps.Brushes.IdealForeground}"/></Trigger>'
        $strHighlighted = '<Trigger Property="IsHighlighted" Value="True"><Setter Property="Background" Value="{DynamicResource MahApps.Brushes.Accent}"/><Setter Property="Foreground" Value="{DynamicResource MahApps.Brushes.IdealForeground}"/></Trigger>'
        $strRow = '<Style x:Key="R" TargetType="DataGridRow"><Style.Triggers>' + $strSelected + '</Style.Triggers></Style><Style x:Key="G" TargetType="DataGrid"><Setter Property="RowStyle" Value="{StaticResource R}"/></Style>'
        $strCell = '<Style x:Key="C" TargetType="DataGridCell"><Style.Triggers>' + $strSelected + '</Style.Triggers></Style>'
        $strComboBad = '<Style x:Key="I" TargetType="ComboBoxItem"><Style.Triggers>' + $strSelected + '</Style.Triggers></Style>'
        $strComboGood = '<Style x:Key="I" TargetType="ComboBoxItem"><Style.Triggers>' + $strSelected + $strHighlighted + '</Style.Triggers></Style>'
        $strBox = '<ComboBox ItemContainerStyle="{StaticResource I}"/>'
        @(Get-SelectedStateViolation -Text ($strOpen + '<Grid.Resources>' + $strComboBad + '</Grid.Resources>' + $strBox + '</Grid>') -Source 's').Count | Should -Be 1
        @(Get-SelectedStateViolation -Text ($strOpen + '<Grid.Resources>' + $strComboGood + '</Grid.Resources>' + $strBox + '</Grid>') -Source 's').Count | Should -Be 0
        @(Get-SelectedStateViolation -Text ($strOpen + '<ListBox/></Grid>') -Source 's').Count | Should -Be 1
        @(Get-SelectedStateViolation -Text ($strOpen + '<Grid.Resources>' + $strRow + $strCell + '</Grid.Resources><DataGrid Style="{StaticResource G}" CellStyle="{StaticResource C}"/></Grid>') -Source 's').Count | Should -Be 0
        @(Get-SelectedStateViolation -Text ($strOpen + '<Grid.Resources>' + $strRow + '</Grid.Resources><DataGrid Style="{StaticResource G}"/></Grid>') -Source 's').Count | Should -Be 1
    }

    It 'finds the sidebar buttons of the shell and lists each in the theme call' {
        $strShell = Get-Content -LiteralPath $script:strShellPath -Raw
        $arrThemed = New-Object System.Collections.Generic.HashSet[string]
        foreach ($objMatch in [regex]::Matches($strShell, 'Button\s*=\s*\$(btn\w+)')) { [void]$arrThemed.Add($objMatch.Groups[1].Value) }
        foreach ($objMatch in [regex]::Matches($strShell, '-OptionsButton\s+\$(btn\w+)')) { [void]$arrThemed.Add($objMatch.Groups[1].Value) }
        $objMain = @($script:arrXamlDoc | Where-Object { $_.Source -eq 'MainWindow.xaml' })[0]
        [xml]$xml = $objMain.Text
        $arrSidebar = @($xml.SelectNodes("//*[local-name()='Button'][contains(@Style,'ViewButtonStyle') or contains(@Style,'OptionsButtonStyle')]"))
        $arrSidebar.Count | Should -BeGreaterOrEqual 4
        $arrMissing = foreach ($objButton in $arrSidebar) {
            $strName = $objButton.GetAttribute('Name', $script:strXamlNamespace)
            if (-not $strName) { 'a sidebar button has no x:Name' } elseif (-not $arrThemed.Contains($strName)) { $strName }
        }
        @($arrMissing) | Should -BeNullOrEmpty
        $strShell | Should -Match '-ViewButtons\s+\$script:ViewButtons'
        ([regex]::Matches($strShell, 'Update-SidebarButtonTheme')).Count | Should -BeGreaterOrEqual 3
    }
}

Describe 'Theme helpers of SuiteCommon behave and are used (a, b)' {
    BeforeAll {
        # Set-ThemeForeground tests a type of WindowsBase. The test loads the assemblies itself, so it runs alone.
        Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
        $script:strSuitePath = Join-Path -Path $script:strRepoRoot -ChildPath 'Lib\SuiteCommon\SuiteCommon.psm1'
        $script:objSuiteAst = [System.Management.Automation.Language.Parser]::ParseFile($script:strSuitePath, [ref]$null, [ref]$null)
        function Get-SuiteFunction {
            param([string]$Name)
            $script:objSuiteAst.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $Name }, $true)
        }
        function Get-CommandCount {
            param($Ast, [string]$Name)
            @($Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq $Name }, $true)).Count
        }
        . ([scriptblock]::Create((Get-SuiteFunction 'Set-ThemeForeground').Extent.Text))
    }

    It 'paints the light theme buttons of SuiteCommon with white text' {
        $strText = Remove-ScriptComment -Text (Get-Content -LiteralPath $script:strSuitePath -Raw)
        $strText | Should -Match "OnBlue\s*=\s*\`$bc\.ConvertFrom\('#FFFFFF'\)"
        foreach ($strName in 'Update-SidebarButtonTheme', 'Set-ButtonTheme') {
            $objFunction = Get-SuiteFunction $strName
            $objFunction | Should -Not -BeNullOrEmpty -Because $strName
            (Get-CommandCount $objFunction 'Set-ThemeForeground') | Should -BeGreaterThan 0 -Because ('{0} sets the foreground with each background' -f $strName)
            (Get-CommandCount $objFunction 'Set-ConnectionTextTheme') | Should -BeGreaterThan 0 -Because $strName
        }
    }

    It 'Set-ThemeForeground sets the on-blue brush in light mode and clears it in dark mode' {
        $objControl = [pscustomobject]@{ Foreground = $null }
        Set-ThemeForeground -Control $objControl -IsDark $false -OnBlue 'White'
        $objControl.Foreground | Should -Be 'White'
        Set-ThemeForeground -Control $objControl -IsDark $true -OnBlue 'White'
        $objControl.Foreground | Should -BeNullOrEmpty
    }

    It 'Set-ThemeForeground clears a dependency object through ClearValue and takes a null control' {
        $objAst = Get-SuiteFunction 'Set-ThemeForeground'
        $objAst.Extent.Text | Should -Match 'ClearValue\(\[System\.Windows\.Controls\.Control\]::ForegroundProperty\)'
        { Set-ThemeForeground -Control $null -IsDark $false -OnBlue 'White' } | Should -Not -Throw
    }

    It 'the script starts the theme and every dialog calls Set-DialogTheme' {
        $objShell = [System.Management.Automation.Language.Parser]::ParseFile($script:strShellPath, [ref]$null, [ref]$null)
        (Get-CommandCount $objShell 'Initialize-SuiteTheme') | Should -BeGreaterThan 0
        (Get-CommandCount $objShell 'Update-SidebarButtonTheme') | Should -BeGreaterThan 0
        $intDialog = @($script:arrXamlDoc | Where-Object { $_.Source -like 'start-updateplanner*here-string*' }).Count
        $intDialog | Should -BeGreaterThan 0
        (Get-CommandCount $objShell 'Set-DialogTheme') | Should -BeGreaterOrEqual $intDialog
        (Get-SuiteFunction 'Set-DialogTheme') | Should -Not -BeNullOrEmpty
    }
}

Describe 'Fonts do not depend on the theme (b)' {
    It 'has no font property in a theme branch of <Name>' -ForEach $script:arrPsFileD {
        $objAst = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$null)
        $arrAssign = $objAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left -is [System.Management.Automation.Language.MemberExpressionAst] }, $true)
        $arrBad = foreach ($objAssign in $arrAssign) {
            $strMember = [string]$objAssign.Left.Member.Value
            if ($script:arrThemeProperty -notcontains $strMember) { continue }
            $objParent = $objAssign.Parent
            while ($objParent) {
                $strCondition = ''
                if ($objParent -is [System.Management.Automation.Language.IfStatementAst]) { $strCondition = (@($objParent.Clauses | ForEach-Object { $_.Item1.Extent.Text }) -join ' ') }
                elseif ($objParent -is [System.Management.Automation.Language.SwitchStatementAst]) { $strCondition = $objParent.Condition.Extent.Text }
                if ($strCondition -match '(?i)IsDark|DarkMode|Light|Theme|IsOn') { '{0}:{1} sets {2} in a theme branch' -f $Name, $objAssign.Extent.StartLineNumber, $strMember; break }
                $objParent = $objParent.Parent
            }
        }
        @($arrBad) | Should -BeNullOrEmpty
    }

    It 'sets no font property in the theme functions of SuiteCommon except the connection boxes' {
        $strPath = Join-Path -Path $script:strRepoRoot -ChildPath 'Lib\SuiteCommon\SuiteCommon.psm1'
        $objAst = [System.Management.Automation.Language.Parser]::ParseFile($strPath, [ref]$null, [ref]$null)
        foreach ($strName in 'Set-ThemeForeground', 'Update-SidebarButtonTheme', 'Set-ButtonTheme', 'Set-DialogTheme', 'Update-TitleBarBrushes', 'Initialize-SuiteTheme') {
            $objFunction = $objAst.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $strName }, $true)
            $objFunction | Should -Not -BeNullOrEmpty -Because $strName
            $objFunction.Extent.Text | Should -Not -Match '\.(FontSize|FontWeight|FontStyle|TextDecorations)\s*=' -Because $strName
        }
    }

    It 'makes the title of each connection box bold and 14 pt or larger, and leaves the value alone, the same way in both themes' {
        $strPath = Join-Path -Path $script:strRepoRoot -ChildPath 'Lib\SuiteCommon\SuiteCommon.psm1'
        $strText = Remove-ScriptComment -Text (Get-Content -LiteralPath $strPath -Raw)
        $strText | Should -Match 'FieldTitleFontSize\s*=\s*14'
        $objAst = [System.Management.Automation.Language.Parser]::ParseFile($strPath, [ref]$null, [ref]$null)
        $objFunction = $objAst.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Set-ConnectionTextTheme' }, $true)
        $objFunction | Should -Not -BeNullOrEmpty
        $strCode = Remove-ScriptComment -Text $objFunction.Extent.Text
        $strCode | Should -Match '\$title\.FontWeight\s*=\s*\[System\.Windows\.FontWeights\]::Bold'
        $strCode | Should -Not -Match '\$box\.(FontSize|FontWeight)\s*='
    }

    It 'uses no SemiBold title or label in <_.Source>, so that every title and field label is bold' -ForEach $script:arrOwnXamlDocD {
        $_.Text | Should -Not -Match 'FontWeight(=|" Value=)"SemiBold"'
    }

    It 'uses no theme trigger on a font property in <_.Source>' -ForEach $script:arrXamlDocD {
        # A trigger on the selected tab or on the mouse is not a theme trigger. A trigger is a theme trigger when its own condition names the theme.
        [xml]$xml = $_.Text
        $arrBad = foreach ($objSetter in @($xml.SelectNodes("//*[local-name()='Setter']"))) {
            if ($script:arrThemeProperty -contains (Get-PropertyLeaf $objSetter.GetAttribute('Property'))) {
                $objParent = $objSetter.ParentNode
                if ($objParent.LocalName -match 'Trigger') {
                    $strCondition = '{0} {1} {2}' -f $objParent.GetAttribute('Property'), $objParent.GetAttribute('Binding'), $objParent.GetAttribute('Value')
                    if ($strCondition -match '(?i)theme|dark|light|IsDark') { $objParent.OuterXml.Substring(0, [Math]::Min(80, $objParent.OuterXml.Length)) }
                }
            }
        }
        @($arrBad) | Should -BeNullOrEmpty
    }

    It 'finds the site code and SMS Provider boxes in the documents' {
        $arrName = foreach ($objDoc in @($script:arrOwnXamlDoc)) {
            [xml]$xml = $objDoc.Text
            foreach ($strName in 'txtSiteCode', 'txtSmsProvider') { if ($xml.SelectSingleNode(("//*[@*[local-name()='Name']='{0}']" -f $strName))) { $strName } }
        }
        @($arrName | Sort-Object -Unique) | Should -Be @('txtSiteCode', 'txtSmsProvider')
        @($arrName).Count | Should -BeGreaterOrEqual 4
    }

    It 'sets the title of the site code and SMS Provider boxes to bold 14 pt or more, and the value to normal weight and a size below 14 pt, in <_.Source>' -ForEach $script:arrOwnXamlDocD {
        [xml]$xml = $_.Text
        foreach ($strName in 'txtSiteCode', 'txtSmsProvider', 'txtProvider', 'txtSiteServer') {
            $objElement = $xml.SelectSingleNode(("//*[@*[local-name()='Name']='{0}']" -f $strName))
            if (-not $objElement) { continue }
            $objTitle = $objElement.PreviousSibling
            while ($objTitle -and $objTitle.NodeType -ne 'Element') { $objTitle = $objTitle.PreviousSibling }
            $objTitle | Should -Not -BeNullOrEmpty -Because ('{0} has a title element before it' -f $strName)
            $objTitle.LocalName | Should -BeIn @('TextBlock', 'Label') -Because $strName
            [double]$objTitle.GetAttribute('FontSize') | Should -BeGreaterOrEqual 14 -Because ('the title of {0}' -f $strName)
            $objTitle.GetAttribute('FontWeight') | Should -Be 'Bold' -Because ('the title of {0}' -f $strName)
            $objElement.GetAttribute('FontWeight') | Should -Not -Be 'Bold' -Because ('the value of {0}' -f $strName)
            if ($objElement.GetAttribute('FontSize')) { [double]$objElement.GetAttribute('FontSize') | Should -BeLessThan 14 -Because ('the value of {0}' -f $strName) }
        }
    }

    It 'makes every field label of the main window and the dialog bold' -ForEach $script:arrOwnXamlDocD {
        [xml]$xml = $_.Text
        $arrStyle = @{}
        foreach ($objStyle in @($xml.SelectNodes("//*[local-name()='Style'][@TargetType='TextBlock']"))) {
            $arrStyle[$objStyle.GetAttribute('Key', $script:strXamlNamespace)] = (@(Get-SetterChild -Node $objStyle -LeafPattern '^FontWeight$' | Where-Object { $_.GetAttribute('Value') -eq 'Bold' }).Count -gt 0)
        }
        $arrBad = foreach ($objText in @($xml.SelectNodes("//*[local-name()='TextBlock'][contains(@Style,'FieldLabelStyle') or contains(@Style,'OptLabel')]"))) {
            $strKey = Get-ResourceKey $objText.GetAttribute('Style')
            if ($objText.GetAttribute('FontWeight') -ne 'Bold' -and -not $arrStyle[$strKey]) { $objText.GetAttribute('Text') }
        }
        @($arrBad) | Should -BeNullOrEmpty
    }
}

Describe 'No banned word in the UI text and the documents (c)' {
    It 'finds the banned word <Word>' -ForEach @(@{ Word = 'simply' }, @{ Word = 'Helps you' }, @{ Word = 'streamlines' }, @{ Word = 'just' }, @{ Word = 'quickly' }) {
        $Word | Should -Match $script:strBannedPattern
    }

    It 'has no banned word in the XAML text of <_.Source>' -ForEach $script:arrXamlDocD {
        $arrBad = @(Get-XamlUiText -Text $_.Text | Where-Object { $_ -match $script:strBannedPattern })
        $arrBad | Should -BeNullOrEmpty
    }

    It 'has no banned word in the strings of <Name>' -ForEach $script:arrPsFileD {
        $arrBad = @(Get-ScriptString -Path $Path | Where-Object { $_ -match $script:strBannedPattern })
        $arrBad | Should -BeNullOrEmpty
    }

    It 'has no banned word in the README or the user guide' {
        $arrFile = @(Get-Item -LiteralPath (Join-Path -Path $script:strRepoRoot -ChildPath 'README.md')) + @(Get-ChildItem -LiteralPath (Join-Path -Path $script:strRepoRoot -ChildPath 'docs') -Filter '*.md' -File -Recurse)
        $arrBad = foreach ($objFile in $arrFile) {
            $intLine = 0
            foreach ($strLine in (Get-Content -LiteralPath $objFile.FullName)) {
                $intLine++
                if ($strLine -match $script:strBannedPattern) { '{0}:{1}: {2}' -f $objFile.Name, $intLine, $Matches[0] }
            }
        }
        @($arrBad) | Should -BeNullOrEmpty
    }

    It 'writes ConfigMgr and never MECM in the UI text and the documents' {
        $arrFile = @(Get-Item -LiteralPath (Join-Path -Path $script:strRepoRoot -ChildPath 'README.md')) + @(Get-ChildItem -LiteralPath (Join-Path -Path $script:strRepoRoot -ChildPath 'docs') -Filter '*.md' -File -Recurse)
        $arrBad = foreach ($objFile in $arrFile) { if ((Get-Content -LiteralPath $objFile.FullName -Raw) -cmatch '\bMECM\b') { $objFile.Name } }
        @($arrBad) | Should -BeNullOrEmpty
        $arrText = foreach ($objDoc in $script:arrOwnXamlDoc) { Get-XamlUiText -Text $objDoc.Text }
        @($arrText | Where-Object { $_ -cmatch '\bMECM\b' }) | Should -BeNullOrEmpty
    }
}

Describe 'Every button takes the shared themed style (d)' {
    It 'has no unthemed button and no literal button color in <_.Source>' -ForEach $script:arrOwnXamlDocD {
        $arrBad = @(Get-ButtonThemeViolation -Text $_.Text -Source $_.Source)
        $arrBad | Should -BeNullOrEmpty
    }

    # The dialogs of SuiteCommon are vendored code. They are fixed in the suite repository (app-packager-suite), not here.
    # The test is skipped on purpose and shows in the result as Skipped with this reason.
    It 'SKIPPED until the suite repository fixes its dialogs: has no unthemed button in <_.Source>' -Skip -ForEach @($script:arrXamlDocD | Where-Object { $_.Source -match 'SuiteCommon' }) {
        $arrBad = @(Get-ButtonThemeViolation -Text $_.Text -Source $_.Source)
        $arrBad | Should -BeNullOrEmpty
    }

    It 'finds the buttons of the documents' {
        $intCount = 0
        foreach ($objDoc in $script:arrOwnXamlDoc) {
            [xml]$xml = $objDoc.Text
            $intCount += @($xml.SelectNodes("//*[local-name()='Button']")).Count
        }
        $intCount | Should -BeGreaterThan 15
    }

    It 'flags a button that has no style, a literal color and a style that is not shared' {
        $strNamespace = 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" xmlns:Controls="clr-namespace:MahApps.Metro.Controls;assembly=MahApps.Metro"'
        $strThemed = '<Style x:Key="ThemedButtonStyle" TargetType="Button" BasedOn="{StaticResource MahApps.Styles.Button.Square}"/>'
        @(Get-ButtonThemeViolation -Text "<Grid $strNamespace><Button x:Name=`"a`"/></Grid>" -Source 's').Count | Should -Be 1
        @(Get-ButtonThemeViolation -Text "<Grid $strNamespace><Grid.Resources>$strThemed<Style x:Key=`"S`" TargetType=`"Button`" BasedOn=`"{StaticResource ThemedButtonStyle}`"/></Grid.Resources><Button Style=`"{StaticResource S}`" Background=`"#1E1E1E`"/></Grid>" -Source 's').Count | Should -Be 1
        @(Get-ButtonThemeViolation -Text "<Grid $strNamespace><Grid.Resources>$strThemed<Style x:Key=`"S`" TargetType=`"Button`" BasedOn=`"{StaticResource MahApps.Styles.Button.Square.Accent}`"/></Grid.Resources><Button Style=`"{StaticResource S}`"/></Grid>" -Source 's').Count | Should -Be 2
        @(Get-ButtonThemeViolation -Text "<Grid $strNamespace><Grid.Resources>$strThemed<Style x:Key=`"S`" TargetType=`"Button`" BasedOn=`"{StaticResource ThemedButtonStyle}`"><Setter Property=`"Foreground`" Value=`"White`"/></Style></Grid.Resources><Button Style=`"{StaticResource S}`"/></Grid>" -Source 's').Count | Should -Be 1
        @(Get-ButtonThemeViolation -Text "<Grid $strNamespace><Grid.Resources>$strThemed<Style x:Key=`"S`" TargetType=`"Button`" BasedOn=`"{StaticResource ThemedButtonStyle}`"><Setter Property=`"Foreground`" Value=`"{DynamicResource MahApps.Brushes.ThemeForeground}`"/></Style></Grid.Resources><Button Style=`"{StaticResource S}`"/></Grid>" -Source 's').Count | Should -Be 0
    }

    It 'flags a literal color in a qualified brush property and in a nested brush of a button template' {
        $strNamespace = 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" xmlns:Controls="clr-namespace:MahApps.Metro.Controls;assembly=MahApps.Metro"'
        $strThemed = '<Style x:Key="ThemedButtonStyle" TargetType="Button" BasedOn="{StaticResource MahApps.Styles.Button.Square}"/>'
        $strStyle = '<Style x:Key="S" TargetType="Button" BasedOn="{StaticResource ThemedButtonStyle}"><Setter Property="Controls:ControlsHelper.MouseOverBorderBrush" Value="#3A3A3A"/></Style>'
        @(Get-ButtonThemeViolation -Text "<Grid $strNamespace><Grid.Resources>$strThemed$strStyle</Grid.Resources><Button Style=`"{StaticResource S}`"/></Grid>" -Source 's').Count | Should -Be 1
        $strNested = '<ControlTemplate TargetType="Button"><Border><Border.Background><SolidColorBrush Color="#3A3A3A"/></Border.Background></Border></ControlTemplate>'
        @(Get-ButtonThemeViolation -Text "<Grid $strNamespace><Grid.Resources>$strThemed$strNested</Grid.Resources></Grid>" -Source 's').Count | Should -Be 1
        $strSetter = '<Style x:Key="S" TargetType="Button" BasedOn="{StaticResource ThemedButtonStyle}"><Setter Property="Background"><Setter.Value><SolidColorBrush Color="#3A3A3A"/></Setter.Value></Setter></Style>'
        @(Get-ButtonThemeViolation -Text "<Grid $strNamespace><Grid.Resources>$strThemed$strSetter</Grid.Resources><Button Style=`"{StaticResource S}`"/></Grid>" -Source 's').Count | Should -Be 1
    }

    It 'has one secondary button style and one primary button style in the dialog, and no other button style that sets a Background' {
        $arrDoc = @($script:arrOwnXamlDoc | Where-Object { $_.Text -match 'DialogAccentButton' })
        $arrDoc.Count | Should -Be 1
        [xml]$xml = $arrDoc[0].Text
        $arrWithBackground = foreach ($objStyle in @($xml.SelectNodes("//*[local-name()='Style'][@TargetType='Button']"))) {
            if (@(Get-SetterChild -Node $objStyle -LeafPattern '^Background$').Count -gt 0) { $objStyle.GetAttribute('Key', $script:strXamlNamespace) }
        }
        @($arrWithBackground | Sort-Object) | Should -Be @('DialogAccentButton', 'DialogButton')
    }

    It 'defines the button template and the button style once in each document and no per-dialog button style besides them' {
        foreach ($objDoc in $script:arrOwnXamlDoc) {
            [xml]$xml = $objDoc.Text
            @($xml.SelectNodes("//*[local-name()='Style'][@*[local-name()='Key']='ThemedButtonStyle']")).Count | Should -Be 1 -Because $objDoc.Source
            @($xml.SelectNodes("//*[local-name()='ControlTemplate'][@*[local-name()='Key']='ThemedButtonTemplate']")).Count | Should -Be 1 -Because $objDoc.Source
            @($xml.SelectNodes("//*[local-name()='ControlTemplate'][@TargetType='Button' or @TargetType='ButtonBase']")).Count | Should -Be 1 -Because $objDoc.Source
        }
    }

    It 'uses the same dialog button definition as the window button definition' {
        $arrTemplate = foreach ($objDoc in $script:arrOwnXamlDoc) {
            [xml]$xml = $objDoc.Text
            $objNode = $xml.SelectSingleNode("//*[local-name()='ControlTemplate'][@*[local-name()='Key']='ThemedButtonTemplate']")
            ($objNode.InnerXml -replace '\s+', ' ')
        }
        @($arrTemplate | Sort-Object -Unique).Count | Should -Be 1
    }

    It 'names the colors of the secondary dialog style from the theme resources only' {
        $arrDoc = @($script:arrOwnXamlDoc | Where-Object { $_.Text -match 'DialogAccentButton' })
        [xml]$xml = $arrDoc[0].Text
        $objSecondary = $xml.SelectSingleNode("//*[local-name()='Style'][@*[local-name()='Key']='DialogButton']")
        $objSecondary | Should -Not -BeNullOrEmpty
        $objSecondary.GetAttribute('BasedOn') | Should -Be '{StaticResource ThemedButtonStyle}'
        foreach ($objSetter in @(Get-SetterChild -Node $objSecondary -LeafPattern '(Background|Foreground|Brush)$')) {
            $objSetter.GetAttribute('Value') | Should -Match '^\{DynamicResource MahApps\.Brushes\.' -Because $objSetter.GetAttribute('Property')
        }
    }

    It 'themes the buttons of the window in both themes through SuiteCommon' {
        $strShell = Get-Content -LiteralPath $script:strShellPath -Raw
        $strShell | Should -Match '-ViewButtons\s+\$script:ViewButtons'
        $strShell | Should -Match '-OptionsButton\s+\$btnOptions'
        ([regex]::Matches($strShell, 'Update-SidebarButtonTheme')).Count | Should -BeGreaterOrEqual 3
    }
}

Describe 'Titles are in Title Case (d)' {
    It 'recognizes Title Case' {
        Test-TitleCase 'Build Plan' | Should -BeTrue
        Test-TitleCase 'Wave Collections in Order' | Should -BeTrue
        Test-TitleCase 'Days to Deadline' | Should -BeTrue
        Test-TitleCase 'Add...' | Should -BeTrue
        Test-TitleCase 'Export JSON' | Should -BeTrue
        Test-TitleCase 'Build plan' | Should -BeFalse
        Test-TitleCase 'Skipped updates' | Should -BeFalse
        Test-TitleCase 'enable Actions' | Should -BeFalse
    }

    It 'has Title Case for every button, header, tab, field label and window title in <_.Source>' -ForEach $script:arrOwnXamlDocD {
        $arrBad = @(Get-XamlTitle -Text $_.Text | Where-Object { -not (Test-TitleCase $_) })
        $arrBad | Should -BeNullOrEmpty
    }

    It 'finds titles to check in the main window' {
        $objMain = @($script:arrXamlDoc | Where-Object { $_.Source -eq 'MainWindow.xaml' })[0]
        @(Get-XamlTitle -Text $objMain.Text).Count | Should -BeGreaterThan 30
    }

    It 'has Title Case in the title of every message box, confirmation and background step of the script' {
        $objAst = [System.Management.Automation.Language.Parser]::ParseFile($script:strShellPath, [ref]$null, [ref]$null)
        $arrCall = $objAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -in 'Show-ThemedMessage', 'Show-ConfirmDialog', 'Start-BackgroundWork', 'Show-CollectionPickerDialog' }, $true)
        @($arrCall).Count | Should -BeGreaterThan 5
        $arrBad = foreach ($objCall in $arrCall) {
            $arrElement = @($objCall.CommandElements)
            for ($intIndex = 0; $intIndex -lt $arrElement.Count - 1; $intIndex++) {
                if ($arrElement[$intIndex] -is [System.Management.Automation.Language.CommandParameterAst] -and $arrElement[$intIndex].ParameterName -eq 'Title' -and $arrElement[$intIndex + 1] -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                    $strTitle = [string]$arrElement[$intIndex + 1].Value
                    if (-not (Test-TitleCase $strTitle)) { $strTitle }
                }
            }
        }
        @($arrBad) | Should -BeNullOrEmpty
    }

    It 'uses the term SMS Provider and never the lower case form in the XAML text' {
        $arrText = foreach ($objDoc in $script:arrOwnXamlDoc) { Get-XamlUiText -Text $objDoc.Text }
        @($arrText | Where-Object { $_ -cmatch 'SMS provider' }) | Should -BeNullOrEmpty
    }
}

Describe 'No raw exception text in the window (e)' {
    It 'finds the UI calls of the script' {
        $objAst = [System.Management.Automation.Language.Parser]::ParseFile($script:strShellPath, [ref]$null, [ref]$null)
        @($objAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -in 'Add-LogLine', 'Set-StatusText', 'Show-ThemedMessage' }, $true)).Count | Should -BeGreaterThan 20
    }

    It 'shows no exception text in a log line, the status text or a message box of start-updateplanner.ps1' {
        $arrBad = @(Get-UiExceptionText -Path $script:strShellPath)
        $arrBad | Should -BeNullOrEmpty
    }

    It 'writes exception text only to the log file (-Quiet) in start-updateplanner.ps1' {
        $objAst = [System.Management.Automation.Language.Parser]::ParseFile($script:strShellPath, [ref]$null, [ref]$null)
        $arrCall = $objAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Write-Log' }, $true)
        @($arrCall).Count | Should -BeGreaterThan 0
        $arrBad = foreach ($objCall in $arrCall) {
            $strText = $objCall.Extent.Text
            if ($strText -match '\$_|Exception\.Message|ErrorMsg|\$err\b' -and $strText -notmatch '-Quiet') { '{0}: {1}' -f $objCall.Extent.StartLineNumber, $strText }
        }
        @($arrBad) | Should -BeNullOrEmpty
    }

    It 'flags exception text in a UI call' {
        $strTemp = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('themeguard-' + [guid]::NewGuid().ToString('N') + '.ps1')
        try {
            [System.IO.File]::WriteAllText($strTemp, "try { 1 } catch { Add-LogLine (`$_.Exception.Message) }`ntry { 1 } catch { Show-ThemedMessage -Message `$script:State.ErrorMsg }`nAdd-LogLine 'The step failed.'`n")
            @(Get-UiExceptionText -Path $strTemp).Count | Should -Be 2
        }
        finally { Remove-Item -LiteralPath $strTemp -Force -ErrorAction SilentlyContinue }
    }

    It 'shows a failed deployment with a fixed message and keeps the exception text in Detail' {
        $strModule = Get-Content -LiteralPath (Join-Path -Path $script:strRepoRoot -ChildPath 'Module\UpdatePlannerCommon.psm1') -Raw
        $strModule | Should -Match "Message = \`$strFailure\s*\r?\n\s*Detail = \`$strDetail"
        $strModule | Should -Not -Match "\`$strFailure = \`$_\.Exception\.Message"
    }
}
