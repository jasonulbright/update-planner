#Requires -Modules Pester
[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'The cut-out shell functions read these stand-in controls through scope.')]
[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '', Justification = 'The shell keeps its preferences in globals; the tests set the same names.')]
[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingComputerNameHardcoded', '', Justification = 'Test inputs are fake computer names.')]
param ()
# Start-up without the ConfigMgr console: the message is plain text, the start
# script checks the console before it builds a window and exits with code 2, and
# no raw exception reaches the user.

BeforeAll {
    . "$PSScriptRoot\TestHelpers.ps1"
    Import-AppModule
    $script:ShellPath = Join-Path $script:AppRoot 'start-updateplanner.ps1'
    $script:Ast = [System.Management.Automation.Language.Parser]::ParseFile($script:ShellPath, [ref]$null, [ref]$null)
}

Describe 'Console check without the ConfigMgr module' {
    BeforeEach {
        Mock Resolve-ConfigurationManagerModulePath { $null } -ModuleName UpdatePlannerCommon
    }

    It 'returns a plain message and no module path' {
        $check = Test-UpConsoleModule
        $check.Available | Should -BeFalse
        $check.Path | Should -Be ''
        $check.Message | Should -BeLike 'The Configuration Manager console is not installed on this computer.*'
    }

    It 'writes no PowerShell error text such as a stack trace or exception type' {
        (Test-UpConsoleModule).Message | Should -Not -Match 'Exception|at <ScriptBlock>|CategoryInfo|FullyQualifiedErrorId|Import-Module'
    }

    It 'tells the user what to do' {
        (Test-UpConsoleModule).Message | Should -Match 'Install the console, then start Update Planner again\.$'
    }

    It 'stops Connect-UpSite with the same plain message before any site call' {
        Mock New-PSDrive { } -ModuleName UpdatePlannerCommon
        Mock Set-Location { } -ModuleName UpdatePlannerCommon
        $message = $null
        try { InModuleScope UpdatePlannerCommon { Connect-UpSite -ComputerName 'sms01' -SiteCode 'ABC' } } catch { $message = $_.Exception.Message }
        $message | Should -Be (Test-UpConsoleModule).Message
        Should -Invoke New-PSDrive -ModuleName UpdatePlannerCommon -Times 0 -Scope It
        Should -Invoke Set-Location -ModuleName UpdatePlannerCommon -Times 0 -Scope It
    }
}

Describe 'Connect-UpSite input' {
    BeforeEach {
        Mock Resolve-ConfigurationManagerModulePath { 'C:\Console\bin\ConfigurationManager.psd1' } -ModuleName UpdatePlannerCommon
        Mock New-PSDrive { } -ModuleName UpdatePlannerCommon
    }

    It 'rejects the site code "<Code>" before any site call' -ForEach @(
        @{ Code = '' }, @{ Code = 'AB' }, @{ Code = 'ABCD' }, @{ Code = 'A B' }, @{ Code = 'A-C' }
    ) {
        { InModuleScope UpdatePlannerCommon -Parameters @{ Code = $Code } { param($Code) Connect-UpSite -ComputerName 'sms01' -SiteCode $Code } } | Should -Throw
        Should -Invoke New-PSDrive -ModuleName UpdatePlannerCommon -Times 0 -Scope It
    }

    It 'rejects an empty provider name before any site call' {
        { InModuleScope UpdatePlannerCommon { Connect-UpSite -ComputerName '' -SiteCode 'ABC' } } | Should -Throw
        Should -Invoke New-PSDrive -ModuleName UpdatePlannerCommon -Times 0 -Scope It
    }
}

Describe 'Start script start-up order' {
    BeforeAll {
        $script:Calls = @($script:Ast.FindAll({ param($x) $x -is [System.Management.Automation.Language.CommandAst] }, $true))
        $script:Gate = $script:Calls | Where-Object { $_.GetCommandName() -eq 'Test-UpConsoleModule' } | Select-Object -First 1
        $script:Load = $script:Ast.Find({ param($x) $x -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and $x.Member.Value -eq 'Load' -and $x.Expression.Extent.Text -match 'XamlReader' }, $true)
    }

    It 'checks the console' {
        $script:Gate | Should -Not -BeNullOrEmpty
    }

    It 'checks the console before it loads the window XAML' {
        $script:Load | Should -Not -BeNullOrEmpty
        $script:Gate.Extent.StartOffset | Should -BeLessThan $script:Load.Extent.StartOffset
    }

    It 'shows the plain message, then exits with code 2 when the console is missing' {
        $if = $script:Ast.Find({ param($x) $x -is [System.Management.Automation.Language.IfStatementAst] -and $x.Clauses[0].Item1.Extent.Text -match 'Available' }, $true)
        $if | Should -Not -BeNullOrEmpty
        $body = $if.Clauses[0].Item2.Extent.Text
        $body | Should -Match 'Write-Warning -Message \$__console\.Message'
        $body | Should -Match 'MessageBox\]::Show\(\$__console\.Message'
        $body | Should -Match '(?m)^\s*exit 2\s*$'
    }

    It 'imports the module before the console check' {
        $import = $script:Calls | Where-Object { $_.GetCommandName() -eq 'Import-Module' -and $_.Extent.Text -match '__modulePath' } | Select-Object -First 1
        $import | Should -Not -BeNullOrEmpty
        $import.Extent.StartOffset | Should -BeLessThan $script:Gate.Extent.StartOffset
    }
}
