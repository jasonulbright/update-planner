#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.1.0' }
# Guard for the load robustness of the plan build (Q-47). It parses the files and opens no window.

BeforeAll {
    $script:Root = Split-Path -Parent $PSScriptRoot
    $script:Shell = Get-Content -LiteralPath (Join-Path $script:Root 'start-updateplanner.ps1') -Raw
    $script:Xaml = Get-Content -LiteralPath (Join-Path $script:Root 'MainWindow.xaml') -Raw
}

Describe 'The plan build can be cancelled and reports partial data' {
    It 'has a Cancel button on the progress overlay that takes the themed button style, and the overlay takes the click' {
        $script:Xaml | Should -Match '<Button x:Name="btnCancelWork" Content="Cancel" Style="\{StaticResource ThemedButtonStyle\}"'
        $script:Xaml | Should -Match '<Border x:Name="progressOverlay"\s+Visibility="Collapsed"\s+IsHitTestVisible="True"'
    }

    It 'sets the cancel flag from the button and keeps a cancel flag and a note list in the state of the work' {
        $script:Shell | Should -Match '\$btnCancelWork\.Add_Click'
        $script:Shell | Should -Match "\`$script:BgState\['Cancel'\] = \`$true"
        $script:Shell | Should -Match 'Cancel = \$false; Notes = \[System\.Collections\.ArrayList\]::Synchronized'
    }

    It 'passes the state of the work to the site read and logs the notes of an incomplete read' {
        $script:Shell | Should -Match 'Get-UpdatePlannerState @p -State \$S'
        $script:Shell | Should -Match 'LoadNotes'
        $script:Shell | Should -Match 'incomplete data'
    }

    It 'treats a cancel as a cancel, not as a failed step' {
        $script:Shell | Should -Match "ErrorMsg -like '\*cancelled\*'"
    }
}