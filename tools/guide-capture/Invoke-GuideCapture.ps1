<#
.SYNOPSIS
    Regenerates every image of the user guide with one command.

.DESCRIPTION
    Copies this app to a lab workstation, runs the capture steps in an interactive
    session of a lab account (scheduled task, interactive logon), copies the PNG
    files back, and removes the task and the copy. Only the images that already
    exist in docs\images are replaced, and only when every step passed.

    One capture runs at a time on a lab workstation. The script takes the lock file
    C:\guide\capture.lock (New-Item fails when the file exists) and waits while another
    capture holds it. The script touches the lock every 5 seconds while its capture runs, so a
    live capture never looks stale. A lock older than 60 minutes is stale and the script removes it.
    The script works in its own folder C:\guide\update-planner and its own task
    GuideShots-update-planner. It removes the lock and its own files at the end. It never
    removes the folder C:\guide.

    Two runs: steps-guide.ps1 walks every view, dialog and setting (43 images), and
    steps-console-missing.ps1 starts a copy of the app whose console lookup returns
    nothing (1 image).

    The lab workstation needs the Configuration Manager console, a reachable SMS
    Provider and PowerShell remoting for the account of the credential script. The
    capture reads the site and runs a dry run. It opens the deploy confirmation and
    selects No. It never creates a deployment.

    The script holds no computer name, account or site value. The caller gives them.

.PARAMETER CredentialScript
    A script that sets $LabCredential (a PSCredential). Keep it outside the repository.

.PARAMETER Target
    The name or address of the lab workstation.

.PARAMETER LogonUser
    The domain account that has the interactive session on the lab workstation (domain\account).

.PARAMETER SiteCode
    The site code of the lab site.

.PARAMETER SmsProvider
    The FQDN of the SMS Provider of the lab site.

.PARAMETER Waves
    Three device collection names of the lab site, in rollout order. The first one is also
    the collection of the duplicate wave image.

.PARAMETER Minutes
    The time limit of each run.

.PARAMETER LockWaitMinutes
    How long to wait for the capture lock of another capture before the script stops.

.PARAMETER AddNew
    Also copy images that are not in docs\images yet. Use it for the first capture of a new page.

.EXAMPLE
    .\tools\guide-capture\Invoke-GuideCapture.ps1 -CredentialScript <credential script> -Target <workstation> -LogonUser <domain\account> -SiteCode <site code> -SmsProvider <provider FQDN> -Waves '<collection 1>', '<collection 2>', '<collection 3>'
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', 'CredentialScript', Justification = 'The parameter is the path of a script, not a password.')]
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$CredentialScript,
    [Parameter(Mandatory)][string]$Target,
    [Parameter(Mandatory)][string]$LogonUser,
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9]{3}$')][string]$SiteCode,
    [Parameter(Mandatory)][string]$SmsProvider,
    [Parameter(Mandatory)][ValidateCount(3, 3)][string[]]$Waves,
    [int]$Minutes = 30,
    [int]$LockWaitMinutes = 90,
    [switch]$AddNew
)
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$repo = (Resolve-Path (Join-Path $here '..\..')).Path
$app = 'update-planner'
$images = Join-Path $repo 'docs\images'
$LabCredential = $null
. $CredentialScript
if (-not ($LabCredential -is [System.Management.Automation.PSCredential])) { throw 'The credential script must set $LabCredential to a PSCredential.' }
# Own folder and own task name, so that two captures in the lab never meet. The C:\guide folder itself stays.
$root = "C:\guide\$app"
$taskName = "GuideShots-$app"
$lockPath = 'C:\guide\capture.lock'
$lockToken = [guid]::NewGuid().ToString('N')
$haveLock = $false
$captureJson = @{ SiteCode = $SiteCode; SmsProvider = $SmsProvider; Waves = @($Waves) } | ConvertTo-Json
$failed = New-Object System.Collections.Generic.List[string]
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('guide-capture-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $tmp | Out-Null
$session = New-PSSession -ComputerName $Target -Credential $LabCredential
try {
    # The lock: New-Item with -ErrorAction Stop fails with an IOException when the file exists.
    # Wait for the holder. A lock that is older than the stale age belongs to a dead capture and is removed.
    $haveLock = Invoke-Command $session {
        param($path, $token, $staleMinutes, $waitMinutes)
        New-Item -ItemType Directory -Path (Split-Path -Path $path -Parent) -Force | Out-Null
        $deadline = (Get-Date).AddMinutes($waitMinutes)
        while ($true) {
            try {
                $null = New-Item -ItemType File -Path $path -ErrorAction Stop
                Set-Content -LiteralPath $path -Value $token
                return $true
            }
            catch [System.IO.IOException] {
                $held = Get-Item -LiteralPath $path -ErrorAction SilentlyContinue
                if ($held -and ((Get-Date) - $held.LastWriteTime).TotalMinutes -gt $staleMinutes) {
                    # Read the age again right before the delete: the holder may have touched the lock. Retry at once
                    # only when the lock is gone. Otherwise fall to the deadline check and the sleep, so the loop never spins.
                    $again = Get-Item -LiteralPath $path -ErrorAction SilentlyContinue
                    if ($again -and ((Get-Date) - $again.LastWriteTime).TotalMinutes -gt $staleMinutes) {
                        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
                    }
                    if (-not (Test-Path -LiteralPath $path)) { continue }
                }
                if ((Get-Date) -gt $deadline) { return $false }
                Start-Sleep -Seconds 15
            }
        }
    } -ArgumentList $lockPath, $lockToken, 60, $LockWaitMinutes
    if (-not $haveLock) { throw "Another capture holds $lockPath. The wait of $LockWaitMinutes minutes is over." }
    foreach ($steps in 'steps-guide.ps1', 'steps-console-missing.ps1') {
        $dest = $root
        # A fresh copy for each run. Stop only the leftovers of an earlier capture of this app.
        Invoke-Command $session {
            param($d)
            Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -like "*$d\*" -and $_.ProcessId -ne $PID } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
            Start-Sleep -Seconds 2
            if (Test-Path $d) { Remove-Item $d -Recurse -Force }
            New-Item -ItemType Directory $d, (Join-Path $d 'ui') -Force | Out-Null
        } -ArgumentList $dest
        # The app files only: no saved settings, logs, reports, tests or documentation.
        foreach ($item in Get-ChildItem -LiteralPath $repo -Force | Where-Object { $_.Name -notin '.git', '.claude', '.github', 'Logs', 'Reports', 'docs', 'Tests', 'tools' -and $_.Name -notlike '*.prefs.json' -and $_.Name -notlike '*.windowstate.json' -and $_.Name -notlike '*.local.*' -and $_.Name -notlike '*.png' }) {
            Copy-Item -LiteralPath $item.FullName -Destination "$dest\$($item.Name)" -ToSession $session -Recurse -Force
        }
        Copy-Item (Join-Path $here 'guilib.ps1') (Join-Path $root 'ui\guilib.ps1') -ToSession $session -Force
        Copy-Item (Join-Path $here 'main.ps1') (Join-Path $root 'ui\main.ps1') -ToSession $session -Force
        Copy-Item (Join-Path $here $steps) (Join-Path $root 'ui\steps.ps1') -ToSession $session -Force
        Invoke-Command $session {
            param($r, $user, $json, $task)
            Set-Content (Join-Path $r 'ui\capture.json') $json -Encoding UTF8
            Remove-Item (Join-Path $r 'ui\out') -Recurse -Force -ErrorAction SilentlyContinue
            $act = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$r\ui\main.ps1`" -GuideRoot `"$r`""
            $pr = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest
            Register-ScheduledTask -TaskName $task -Action $act -Principal $pr -Force | Out-Null
            Start-ScheduledTask $task
        } -ArgumentList $root, $LogonUser, $captureJson, $taskName
        $end = (Get-Date).AddMinutes($Minutes)
        do {
            Start-Sleep 5
            # The poll also touches the lock, so that a long capture is never taken for a stale one.
            $done = Invoke-Command $session { param($r, $path) (Get-Item -LiteralPath $path -ErrorAction SilentlyContinue).LastWriteTime = Get-Date; Test-Path (Join-Path $r 'ui\out\finished.flag') } -ArgumentList $root, $lockPath
        } while (-not $done -and (Get-Date) -lt $end)
        if (-not $done) { throw "The capture did not finish: $steps" }
        $out = Join-Path $tmp ([IO.Path]::GetFileNameWithoutExtension($steps))
        New-Item -ItemType Directory $out | Out-Null
        Copy-Item (Join-Path $root 'ui\out\*') $out -FromSession $session -Recurse -Force
        $flag = (Get-Content -LiteralPath (Join-Path $out 'finished.flag') -Raw).Trim()
        if ($flag -ne 'finished') { Write-Warning ('{0}: {1}' -f $steps, $flag); $failed.Add(('{0}: {1}' -f $steps, $flag)) }
        $log = Join-Path $out 'run.log'
        if (Test-Path $log) { Get-Content $log | Where-Object { $_ -match 'ERROR' } | ForEach-Object { Write-Warning $_; $failed.Add($_) } }
    }
    # A failed step stops the capture before any guide image is replaced.
    if ($failed.Count) { throw ("The capture failed. No image was replaced.`n" + ($failed -join "`n")) }
    $captured = @(Get-ChildItem $tmp -Recurse -Filter *.png | Where-Object { $_.Name -notlike 'fail-*' })
    $missing = @(Get-ChildItem $images -Filter *.png | Where-Object { $captured.Name -notcontains $_.Name } | ForEach-Object { $_.Name })
    if ($missing.Count) { throw ("The capture did not produce these guide images. No image was replaced.`n" + ($missing -join "`n")) }
    foreach ($png in $captured) {
        if ($AddNew -or (Test-Path (Join-Path $images $png.Name))) { Copy-Item $png.FullName (Join-Path $images $png.Name) -Force }
    }
    Write-Output ('Replaced {0} images in {1}.' -f @($captured | Where-Object { Test-Path (Join-Path $images $_.Name) }).Count, $images)
}
finally {
    # Each cleanup runs on its own, so that a failed cleanup cannot replace the original error.
    # Stop a capture that still runs (a timeout leaves it running), then remove the task. Stop the task first, then the
    # powershell.exe processes of this folder, then unregister, so that nothing keeps writing into the folder or the lock.
    try {
        Invoke-Command $session {
            param($t, $r)
            Stop-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue
            Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -like "*$r\*" -and $_.ProcessId -ne $PID } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
            Start-Sleep -Seconds 2
            Unregister-ScheduledTask -TaskName $t -Confirm:$false -ErrorAction SilentlyContinue
        } -ArgumentList $taskName, $root
    } catch { Write-Warning "Cleanup of the scheduled task failed: $($_.Exception.Message)" }
    try { Invoke-Command $session { param($r) Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue } -ArgumentList $root } catch { Write-Warning "Cleanup of $root failed: $($_.Exception.Message)" }
    # Remove the lock only when this capture took it.
    try {
        if ($haveLock) {
            Invoke-Command $session { param($path, $token) if ((Test-Path -LiteralPath $path) -and ((Get-Content -LiteralPath $path -Raw -ErrorAction SilentlyContinue).Trim() -eq $token)) { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue } } -ArgumentList $lockPath, $lockToken
        }
    } catch { Write-Warning "Removing the capture lock failed: $($_.Exception.Message)" }
    try { Remove-PSSession $session } catch { Write-Warning "Closing the session failed: $($_.Exception.Message)" }
    try { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue } catch { Write-Warning "Cleanup of $tmp failed: $($_.Exception.Message)" }
}
