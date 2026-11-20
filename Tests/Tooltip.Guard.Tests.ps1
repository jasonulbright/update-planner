#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.1.0' }
# Guard tests for tooltips. They parse the XAML text of the window and of the Options dialog. They
# create no WPF control and open no window, so they run on Windows PowerShell 5.1 and on PowerShell 7.
#
# Rule: each control in the audited list has a tooltip. The tooltip is not empty, uses ASCII only,
# ends in a period and has at most 200 characters.

BeforeAll {
    $script:Root = Split-Path -Path $PSScriptRoot -Parent
    $script:XamlNs = 'http://schemas.microsoft.com/winfx/2006/xaml'
    $script:MaxLength = 200

    # The audited controls: x:Name values in MainWindow.xaml and in the Options dialog of the script.
    $script:WindowName = @(
        'lstWaves', 'dpStartDate', 'txtSpacing', 'txtDeadline', 'cboSeverity', 'txtMaxUpdates',
        'tabPlanned', 'tabSkipped', 'rdoMarkdown', 'rdoHtml', 'btnCancelWork'
    )
    $script:DialogName = @('btnCatConnection', 'btnCatAbout', 'txtSmsProvider', 'txtSiteCode')

    function Read-XamlText {
        param([string]$Text)
        $x = New-Object System.Xml.XmlDocument
        $x.LoadXml($Text)
        $x
    }

    function Get-ToolTipText {
        param($Document, [string]$Name)
        $el = $Document.SelectSingleNode('//*[@*[local-name()="Name" and namespace-uri()="' + $script:XamlNs + '"]="' + $Name + '"]')
        if ($null -eq $el) { return $null }
        $el.GetAttribute('ToolTip')
    }

    $script:WindowDoc = Read-XamlText -Text ([IO.File]::ReadAllText((Join-Path $script:Root 'MainWindow.xaml')))
    $scriptText = [IO.File]::ReadAllText((Join-Path $script:Root 'start-updateplanner.ps1'))
    $m = [regex]::Match($scriptText, "(?ms)\`$dlgXaml\s*=\s*@'[ \t]*\r?\n(\s*<.*?)\r?\n'@")
    $script:DialogXaml = $m.Groups[1].Value
    $script:DialogDoc = if ($m.Success) { Read-XamlText -Text $m.Groups[1].Value } else { $null }
}

Describe 'Tooltips' {
    It 'finds the Options dialog XAML in the script' {
        $script:DialogDoc | Should -Not -BeNullOrEmpty
    }

    It 'gives every audited window control a tooltip' {
        foreach ($n in $script:WindowName) {
            $t = Get-ToolTipText -Document $script:WindowDoc -Name $n
            $t | Should -Not -BeNullOrEmpty -Because ('{0} needs a ToolTip' -f $n)
            $t.Trim().Length | Should -BeGreaterThan 0 -Because ('{0} needs a ToolTip' -f $n)
        }
    }

    It 'gives every audited Options dialog control a tooltip' {
        foreach ($n in $script:DialogName) {
            $t = Get-ToolTipText -Document $script:DialogDoc -Name $n
            $t | Should -Not -BeNullOrEmpty -Because ('{0} needs a ToolTip' -f $n)
        }
    }

    It 'uses ASCII only, ends each tooltip in a period and keeps it short' {
        $all = @()
        foreach ($n in $script:WindowName) { $all += , @($n, (Get-ToolTipText -Document $script:WindowDoc -Name $n)) }
        foreach ($n in $script:DialogName) { $all += , @($n, (Get-ToolTipText -Document $script:DialogDoc -Name $n)) }
        foreach ($pair in $all) {
            $name = $pair[0]; $t = [string]$pair[1]
            $t | Should -Match '^[\x20-\x7E]+$' -Because ('{0} must use printable ASCII only' -f $name)
            $t | Should -Match '\.$' -Because ('{0} must end in a period' -f $name)
            $t.Length | Should -BeLessOrEqual $script:MaxLength -Because ('{0} must stay short' -f $name)
        }
    }
}
