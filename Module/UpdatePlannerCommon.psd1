@{
    RootModule        = 'UpdatePlannerCommon.psm1'
    ModuleVersion     = '2026.11.13.0007'
    GUID              = '5b0f4a0e-6d0c-4c43-9f1b-2f6f2d1c7a41'
    Author            = 'Jason Ulbright'
    Description       = 'Reads Configuration Manager and WSUS software update state and builds a reviewable update plan with waves and dates. Optional step that creates the deployments.'
    PowerShellVersion = '5.1'

    FunctionsToExport = @(
        # Logging and settings come from the vendored SuiteCommon module
        # (Lib\SuiteCommon), imported globally by the root module.

        # Plan
        'Get-UpdatePlannerState'
        'New-UpdatePlan'
        'Export-UpdatePlan'
        'Invoke-UpdatePlan'

        # Window support
        'Get-UpdatePlannerCollection'
        'Test-UpConsoleModule'
        'ConvertFrom-UpdatePlanJson'
        'Resolve-UpdatePlannerSetting'
        'ConvertTo-UpdatePlanRow'
        'ConvertTo-UpdatePlanSkippedRow'
        'ConvertTo-UpdatePlanResultRow'
        'ConvertTo-UpdatePlanMarkdown'
        'ConvertTo-UpdatePlanHtml'
        'Get-UpdatePlanDeploymentPreview'
        'Test-UpdatePlanApplyAllowed'
        'Write-UpdatePlanFile'
        'Write-UpdatePlanAudit'
        'ConvertTo-UpdatePlanJson'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags       = @('ConfigMgr', 'WSUS', 'SoftwareUpdates', 'Patching', 'UpdatePlan', 'Waves', 'Collections', 'Supersedence', 'Pester')
            LicenseUri = 'https://github.com/jasonulbright/update-planner/blob/main/LICENSE'
            ProjectUri = 'https://github.com/jasonulbright/update-planner'
        }
    }
}
