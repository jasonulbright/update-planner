#Requires -Modules Pester
# Static checks of the capture scripts in tools\guide-capture. The test opens no window and
# runs no capture. It parses the scripts and checks that they carry no computer name, account
# or address: the caller gives the lab values as parameters.

BeforeDiscovery {
    $script:CaptureDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'tools\guide-capture'
    $script:ScriptCases = @(Get-ChildItem -LiteralPath $script:CaptureDir -Filter '*.ps1' -File | ForEach-Object { @{ Name = $_.Name; Path = $_.FullName } })
}

BeforeAll {
    $script:Root = Split-Path -Parent $PSScriptRoot
    $script:CaptureDir = Join-Path $script:Root 'tools\guide-capture'
    $script:InvokePath = Join-Path $script:CaptureDir 'Invoke-GuideCapture.ps1'
}

Describe 'Capture scripts' {
    It 'has the five capture scripts' {
        foreach ($n in 'Invoke-GuideCapture.ps1', 'guilib.ps1', 'main.ps1', 'steps-guide.ps1', 'steps-console-missing.ps1') {
            Test-Path -LiteralPath (Join-Path $script:CaptureDir $n) | Should -BeTrue -Because $n
        }
    }

    It 'parses <Name> without error' -ForEach $script:ScriptCases {
        $errors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$errors)
        @($errors) | Should -BeNullOrEmpty
    }

    It 'has no network address, host name or account literal in <Name>' -ForEach $script:ScriptCases {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$null)
        $strings = @($ast.FindAll({
                    param($n)
                    $n -is [System.Management.Automation.Language.StringConstantExpressionAst] -or
                    $n -is [System.Management.Automation.Language.ExpandableStringExpressionAst]
                }, $true) | ForEach-Object { $_.Value })
        # An IPv4 address, or a host name with a domain: two dots and a letter label at the end,
        # not a file name and not a .NET type name.
        $fileExt = '\.(ps1|psm1|psd1|json|png|log|flag|txt|exe|dll|md|html|xaml)$'
        # The lab names are built from parts, so that this file does not carry them as text either.
        $parts = @(('C', 'M01'), ('CLI', 'ENT01'), ('D', 'C01'), ('con', 'toso')) | ForEach-Object { $_ -join '' }
        $labNames = '\b(' + ($parts -join '|') + ')'
        $bad = foreach ($s in $strings) {
            if ($s -match '\b\d{1,3}(\.\d{1,3}){3}\b') { "address: $s"; continue }
            if ($s -match $labNames) { "lab name: $s"; continue }
            foreach ($m in [regex]::Matches($s, '\b[A-Za-z0-9-]+(\.[A-Za-z0-9-]+){2,}\b')) {
                if ($m.Value -match '^(System|Microsoft)\.') { continue }
                if ($m.Value -notmatch $fileExt -and $m.Value -match '\.[A-Za-z]{2,}$') { "host: $($m.Value)" }
            }
        }
        @($bad) | Should -BeNullOrEmpty
    }

    It 'takes the lab computer, the logon account, the credential and the site values only from parameters without a default' {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($script:InvokePath, [ref]$null, [ref]$null)
        $params = @{}
        foreach ($p in $ast.ParamBlock.Parameters) { $params[$p.Name.VariablePath.UserPath] = $p }
        foreach ($n in 'CredentialScript', 'Target', 'LogonUser', 'SiteCode', 'SmsProvider', 'Waves') {
            $params.ContainsKey($n) | Should -BeTrue -Because $n
            $params[$n].DefaultValue | Should -BeNullOrEmpty -Because $n
            ($params[$n].Attributes | Where-Object { $_.Extent.Text -match 'Mandatory' }) | Should -Not -BeNullOrEmpty -Because $n
        }
    }

    It 'connects and schedules the task with the values of the caller' {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($script:InvokePath, [ref]$null, [ref]$null)
        $calls = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -in 'New-PSSession', 'New-ScheduledTaskPrincipal' }, $true))
        $calls.Count | Should -Be 2
        foreach ($c in $calls) {
            $text = $c.Extent.Text
            if ($c.GetCommandName() -eq 'New-PSSession') {
                $text | Should -Match '-ComputerName \$Target\b'
                $text | Should -Match '-Credential \$LabCredential\b'
            }
            else { $text | Should -Match '-UserId \$user\b' }
        }
        [System.IO.File]::ReadAllText($script:InvokePath) | Should -Match '-ArgumentList \$app, \$LogonUser, \$captureJson'
    }

    It 'stops before it replaces an image when a step failed' {
        $text = [System.IO.File]::ReadAllText($script:InvokePath)
        $iThrow = $text.IndexOf('if ($failed.Count) { throw')
        $iCopy = $text.IndexOf('foreach ($png in $captured)')
        $iThrow | Should -BeGreaterThan 0
        $iCopy | Should -BeGreaterThan $iThrow
        [System.IO.File]::ReadAllText((Join-Path $script:CaptureDir 'main.ps1')) | Should -Match "'failed: '"
    }

    It 'produces in its steps every image of the guide' {
        $steps = (Get-ChildItem -LiteralPath $script:CaptureDir -Filter 'steps-*.ps1' | ForEach-Object { [System.IO.File]::ReadAllText($_.FullName) }) -join "`n"
        $shots = @([regex]::Matches($steps, "\bShot\s+\`$\w+\s+'([a-z0-9-]+)'") | ForEach-Object { $_.Groups[1].Value })
        $shots += @([regex]::Matches($steps, "\bShot\s+\`$dlg\s+\(\`$shot \+ '-selected'\)") | ForEach-Object { 'plan-picker-selected' })
        $shots += @([regex]::Matches($steps, "Add-Wave [^\r\n]*'(plan-[a-z-]+)'") | ForEach-Object { $_.Groups[1].Value })
        $images = @(Get-ChildItem -LiteralPath (Join-Path $script:Root 'docs\images') -Filter '*.png' | ForEach-Object { $_.BaseName })
        @($images | Where-Object { $shots -notcontains $_ }) | Should -BeNullOrEmpty
    }

    It 'documents the one command that retakes the captures in the guide index and in the README' {
        foreach ($f in (Join-Path $script:Root 'docs\index.md'), (Join-Path $script:Root 'README.md')) {
            [System.IO.File]::ReadAllText($f) | Should -Match 'tools\\guide-capture\\Invoke-GuideCapture\.ps1' -Because $f
        }
    }
}
