[CmdletBinding(PositionalBinding = $false, SupportsShouldProcess = $true, ConfirmImpact = 'High')]
[OutputType([pscustomobject])]
param (
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$ComputerName = $env:COMPUTERNAME,

    [Parameter(Mandatory = $false)]
    [System.Management.Automation.PSCredential]$Credential,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9]{3}$')]
    [string]$SiteCode,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string[]]$TargetCollection,

    [Parameter(Mandatory = $false)]
    [datetime]$StartDate = (Get-Date).Date.AddDays(1),

    [Parameter(Mandatory = $false)]
    [ValidateRange(0, 365)]
    [int]$WaveSpacingDays = 7,

    [Parameter(Mandatory = $false)]
    [ValidateRange(0, 365)]
    [int]$DeadlineDays = 3,

    [Parameter(Mandatory = $false)]
    [ValidateSet(0, 2, 6, 8, 10)]
    [int]$MinimumSeverity = 0,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath = (Join-Path -Path (Get-Location).ProviderPath -ChildPath 'update-plan.json'),

    [Parameter(Mandatory = $false)]
    [switch]$IncludeWsus,

    [Parameter(Mandatory = $false)]
    [switch]$Apply
)

# .SYNOPSIS
# Reads the software update state of a ConfigMgr site and writes a reviewable update plan.
#
# .DESCRIPTION
# Default mode is plan only: the script reads the site, writes update-plan.json and
# update-plan.md, and changes nothing on the site. With -Apply it then creates one
# update deployment for each wave. -Apply supports -WhatIf and asks for confirmation
# before each deployment.
#
# .PARAMETER ComputerName
# The SMS Provider computer. The default is the local computer.
#
# .PARAMETER Credential
# Optional credential for the site drive.
#
# .PARAMETER SiteCode
# The three character site code.
#
# .PARAMETER TargetCollection
# Device collections, as names or IDs. The order is the order of the waves.
#
# .PARAMETER StartDate
# Start date of wave 1. The default is tomorrow.
#
# .PARAMETER WaveSpacingDays
# Days between wave start dates. The default is 7.
#
# .PARAMETER DeadlineDays
# Days from a wave start to its deadline. The default is 3.
#
# .PARAMETER MinimumSeverity
# Lowest severity number to plan (0, 2, 6, 8, 10). The default is 0.
#
# .PARAMETER OutputPath
# Path of the JSON plan file. The Markdown file uses the same name.
#
# .PARAMETER IncludeWsus
# Also read update counts from the WSUS server.
#
# .PARAMETER Apply
# Create one software update group and one deployment of that group for each wave that holds updates. Supports -WhatIf and asks for confirmation before each wave. Without this switch the script changes nothing on the site.
#
# .EXAMPLE
# .\Invoke-UpdatePlanner.ps1 -ComputerName SMS01 -SiteCode ABC -TargetCollection 'Pilot', 'Broad'
#
# # Writes update-plan.json and update-plan.md. Changes nothing on the site.
#
# .EXAMPLE
# .\Invoke-UpdatePlanner.ps1 -ComputerName SMS01 -SiteCode ABC -TargetCollection 'Pilot' -Apply -WhatIf
#
# # Writes the plan and shows the software update groups and deployments that -Apply would create.
#
# .INPUTS
# None. You can't pipe objects to this script.
#
# .OUTPUTS
# [pscustomobject] The files written (JsonPath, MarkdownPath). With -Apply, also one
# result object for each wave.
#
# .NOTES
# This script does not support positional parameters.
#
# Version: 2026.11.13.0007

Set-StrictMode -Version Latest
$strModulePath = Join-Path -Path (Split-Path -Path $PSCommandPath -Parent) -ChildPath 'Module'
$strModulePath = Join-Path -Path $strModulePath -ChildPath 'UpdatePlannerCommon.psd1'
Import-Module -Name $strModulePath -Force -ErrorAction Stop

$objConsole = Test-UpConsoleModule
if (-not $objConsole.Available) {
    Write-Warning -Message $objConsole.Message
    exit 2
}

$hashtableConnection = @{ ComputerName = $ComputerName; SiteCode = $SiteCode }
if ($PSBoundParameters.ContainsKey('Credential')) {
    $hashtableConnection['Credential'] = $Credential
}

$objState = Get-UpdatePlannerState @hashtableConnection -TargetCollection $TargetCollection -IncludeWsus:$IncludeWsus
$objPlan = New-UpdatePlan -State $objState -StartDate $StartDate -WaveSpacingDays $WaveSpacingDays -DeadlineDays $DeadlineDays -MinimumSeverity $MinimumSeverity
Export-UpdatePlan -Plan $objPlan -Path $OutputPath -WhatIf:$false

if ($Apply) {
    $hashtableApply = @{ Plan = $objPlan; ComputerName = $ComputerName; Apply = $true }
    if ($PSBoundParameters.ContainsKey('Credential')) {
        $hashtableApply['Credential'] = $Credential
    }
    # Module functions do not inherit preference variables from the caller. Pass the switches on.
    if ($WhatIfPreference) {
        $hashtableApply['WhatIf'] = $true
    }
    if ($ConfirmPreference -eq 'None') {
        $hashtableApply['Confirm'] = $false
    }
    Invoke-UpdatePlan @hashtableApply
}
