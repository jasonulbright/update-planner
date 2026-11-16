#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.1.0' }

<#
.SYNOPSIS
    Pester 5.x test for the compact 1080p density of the main window (XAML only, no window is opened).
    The shared style values are asserted in one place. The window test Density.Window.Tests.ps1 measures them on screen.
#>

BeforeAll {
    $script:Xaml = [xml](Get-Content -LiteralPath (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'MainWindow.xaml') -Raw)
    $script:Ns = New-Object System.Xml.XmlNamespaceManager($script:Xaml.NameTable)
    $script:Ns.AddNamespace('w', 'http://schemas.microsoft.com/winfx/2006/xaml/presentation')
    $script:Ns.AddNamespace('x', 'http://schemas.microsoft.com/winfx/2006/xaml')
    function Get-StyleValue {
        param([string]$Key, [string]$Property)
        $style = $script:Xaml.SelectSingleNode("//w:Style[@x:Key='$Key']", $script:Ns)
        $style | Should -Not -BeNullOrEmpty -Because $Key
        $setter = $style.SelectSingleNode("w:Setter[@Property='$Property']", $script:Ns)
        if ($setter) { $setter.GetAttribute('Value') } else { $null }
    }
}

Describe 'Compact density at 1080p' {
    It 'opens at the design size of a maximized 1080p work area and keeps the 1024x640 minimum' {
        $w = $script:Xaml.DocumentElement
        [int]$w.GetAttribute('Width') | Should -Be 1920
        [int]$w.GetAttribute('Height') | Should -Be 1032
        [int]$w.GetAttribute('MinWidth') | Should -BeLessOrEqual 1024
        [int]$w.GetAttribute('MinHeight') | Should -BeLessOrEqual 640
    }

    It 'sizes the sidebar view buttons between 34 and 36 px' {
        [double](Get-StyleValue 'ViewButtonStyle' 'Height') | Should -BeIn 34, 35, 36
    }

    It 'sizes the inline buttons and the single-line inputs between 26 and 28 px' {
        [double](Get-StyleValue 'SquareInlineButtonStyle' 'Height') | Should -BeGreaterOrEqual 26
        [double](Get-StyleValue 'SquareInlineButtonStyle' 'Height') | Should -BeLessOrEqual 28
        foreach ($el in @($script:Xaml.SelectNodes('//w:TextBox[@Height] | //w:ComboBox[@Height] | //w:DatePicker[@Height]', $script:Ns))) {
            [double]$el.GetAttribute('Height') | Should -BeIn 26, 27, 28 -Because $el.GetAttribute('Name', 'http://schemas.microsoft.com/winfx/2006/xaml')
        }
    }

    It 'gives every grid rows of 24 to 26 px and a 26 px column header from the one shared style' {
        [double](Get-StyleValue 'ViewDataGrid' 'RowHeight') | Should -BeGreaterOrEqual 24
        [double](Get-StyleValue 'ViewDataGrid' 'RowHeight') | Should -BeLessOrEqual 26
        [double](Get-StyleValue 'ViewDataGrid' 'ColumnHeaderHeight') | Should -Be 26
        foreach ($g in @($script:Xaml.SelectNodes('//w:DataGrid', $script:Ns))) {
            $g.GetAttribute('RowHeight') | Should -BeNullOrEmpty -Because 'the row height has one place: ViewDataGrid'
            $g.GetAttribute('Style') | Should -Match 'ViewDataGrid' -Because $g.GetAttribute('Name', 'http://schemas.microsoft.com/winfx/2006/xaml')
        }
    }

    It 'gives no pane that holds a list or a grid a fixed height, except the log pane' {
        # A fixed height leaves vacant space at the maximized work area. The panes share the free height with * rows.
        $fixed = @(foreach ($row in @($script:Xaml.SelectNodes('//w:RowDefinition[@Height]', $script:Ns))) {
                $h = $row.GetAttribute('Height')
                if ($h -match '^[0-9]+$' -and [int]$h -gt 8) { $h }
            })
        # The log row (140 px) is the one fixed pane: the rest of the window takes all the free space.
        @($fixed | Where-Object { $_ -ne '140' }) | Should -BeNullOrEmpty -Because ('fixed row heights: ' + ($fixed -join ', '))
        foreach ($lb in @($script:Xaml.SelectNodes('//w:ListBox', $script:Ns))) {
            $lb.GetAttribute('Height') | Should -BeNullOrEmpty -Because $lb.GetAttribute('Name', 'http://schemas.microsoft.com/winfx/2006/xaml')
        }
    }
}
