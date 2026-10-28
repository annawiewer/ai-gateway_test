#Requires -Version 7.0
# Compatibility entry point for existing automation.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][guid]$SubscriptionId,
    [Parameter(Mandatory)][guid]$TenantId,
    [Parameter(Mandatory)][ValidatePattern('^[a-zA-Z0-9_.()-]+$')][string]$ResourceGroup,
    [Parameter(Mandatory)][string]$ReportDirectory,
    [string[]]$AdditionalVarFile = @(),
    [switch]$RunPrivateProbe,
    [ValidateRange(0, 900)][int]$TelemetryWaitSeconds = 300,
    [ValidateSet('private-connectivity', 'private-only')][string]$NetworkProfile = 'private-connectivity'
)

& (Join-Path $PSScriptRoot 'Test-DeploymentAcceptance.ps1') @PSBoundParameters
