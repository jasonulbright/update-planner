#Requires -Modules Pester
# Static checks of the capture scripts in tools\guide-capture. The test opens no window and
# runs no capture. It parses the scripts and checks that they carry no password, secret or
# credential file path: the caller gives the credential script and the lab values as parameters.

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

    It 'has no password, secret or credential file literal in <Name>' -ForEach $script:ScriptCases {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$null)
        $strings = @($ast.FindAll({
                    param($n)
                    $n -is [System.Management.Automation.Language.StringConstantExpressionAst] -or
                    $n -is [System.Management.Automation.Language.ExpandableStringExpressionAst]
                }, $true) | ForEach-Object { $_.Value })
        $bad = foreach ($s in $strings) {
            # A password, key or token given as a value in a string.
            if ($s -match '(?i)\b(password|passwd|pwd|secret|apikey|api_key|token)\s*[:=]\s*\S') { "secret: $s"; continue }
            # The path of a credential file: the caller gives it as a parameter.
            if ($s -match '(?i)credentials?[^\\/]*\.local\.ps1') { "credential file: $s"; continue }
        }
        @($bad) | Should -BeNullOrEmpty
        # A secure string or a credential built from a literal password.
        $plain = @($ast.FindAll({
                    param($n)
                    $n -is [System.Management.Automation.Language.CommandAst] -and
                    $n.GetCommandName() -eq 'ConvertTo-SecureString' -and
                    @($n.CommandElements | Where-Object { $_ -is [System.Management.Automation.Language.StringConstantExpressionAst] -and $_.StringConstantType -ne 'BareWord' }).Count -gt 0
                }, $true))
        $plain | Should -BeNullOrEmpty
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
