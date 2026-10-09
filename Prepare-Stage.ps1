<#
    Puts Azure at the demo's starting point. Run it the day before and again the morning
    of the session. Safe to run any number of times.

        .\Prepare-Stage.ps1                    # check and fix the starting point
        .\Prepare-Stage.ps1 -CaptureReplay     # also refresh the saved results used by -Replay
        .\Prepare-Stage.ps1 -SubscriptionId <id>  # use a different test subscription

    Starting point: resource group with one deployment stack ('stack-app') that manages
    vnet-app, nsg-app (HTTPS rule only) and the storage account, with deny settings on. Nothing
    else. For the AI demo, a second resource group ('rg-demo-nic2026-brownfield') with three
    hand-made resources and no stack.
#>
[CmdletBinding()]
param([string]$SubscriptionId, [switch]$CaptureReplay)

$ErrorActionPreference = 'Stop'
$cfgFile = Join-Path $PSScriptRoot 'demo.config.json'
$cfg = Get-Content $cfgFile -Raw | ConvertFrom-Json
$v1  = Join-Path $PSScriptRoot 'stacks-whatif-demo\app.v1.bicep'

function Say([string]$Text, [string]$Color = 'Gray') { Write-Host $Text -ForegroundColor $Color }

Say ''
Say 'Preparing the Stacks What-If demo' Cyan
Import-Module Az.Resources -MinimumVersion 10.2.1 -WarningAction SilentlyContinue

# 1. Sign in and pick the subscription.
if (-not (Get-AzContext -ErrorAction SilentlyContinue)) {
    Say '  Signing in to Azure (a browser window opens)...' Yellow
    Connect-AzAccount -WarningAction SilentlyContinue | Out-Null
}
if ($SubscriptionId) { $cfg.subscriptionId = $SubscriptionId }
$ctx = Set-AzContext -Subscription $cfg.subscriptionId -WarningAction SilentlyContinue
if ($ctx.Subscription.Name -match 'prod|production|shared|corp') {
    throw "Subscription '$($ctx.Subscription.Name)' looks like production. Use a disposable test subscription."
}
$cfg.subscriptionName = $ctx.Subscription.Name
$cfg | Add-Member -NotePropertyName tenantId -NotePropertyValue $ctx.Tenant.Id -Force
$cfg | ConvertTo-Json | Set-Content $cfgFile -Encoding utf8
Say "  OK   $($ctx.Account.Id) | $($ctx.Subscription.Name)" Green

# 2. Resource group. A slow or failed lookup must not look like "missing".
function Get-RgOrNull([string]$Name) {
    for ($i = 1; $i -le 3; $i++) {
        try { return Get-AzResourceGroup -Name $Name -ErrorAction Stop }
        catch {
            if ($_.Exception.Message -match 'does not exist|ResourceGroupNotFound') { return $null }
            if ($i -eq 3) { throw "Could not check resource group $Name ($(($_.Exception.Message -split "`r?`n")[0])). Run this again." }
            Start-Sleep -Seconds 5
        }
    }
}
$rg = Get-RgOrNull $cfg.resourceGroup
if (-not $rg) {
    $tags = @{ purpose = 'demo'; owner = $env:USERNAME; autoDelete = 'true'; event = 'NIC 2026'; created = (Get-Date).ToUniversalTime().ToString('s') + 'Z' }
    $null = New-AzResourceGroup -Name $cfg.resourceGroup -Location $cfg.location -Tag $tags
    Say "  OK   created $($cfg.resourceGroup) in $($cfg.location)" Green
}
else { Say "  OK   $($cfg.resourceGroup) ($($rg.Location))" Green }

# 3. Stack at the starting point.
function Reset-DemoStack {
    $stack = Get-AzResourceGroupDeploymentStack -ResourceGroupName $cfg.resourceGroup -Name $cfg.stackName -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
    $names = @($stack.Resources | ForEach-Object { ($_.Id -split '/')[-1] })
    $nsg = Get-AzResource -ResourceGroupName $cfg.resourceGroup -Name 'nsg-app' -ResourceType 'Microsoft.Network/networkSecurityGroups' -ExpandProperties -ErrorAction SilentlyContinue
    $rules = @($nsg.Properties.securityRules | ForEach-Object { $_.name })
    $atStart = $stack -and $stack.ProvisioningState -eq 'succeeded' -and $names.Count -eq 3 -and ($names -contains 'vnet-app') -and ($names -contains 'nsg-app') -and
               $stack.ResourcesCleanupAction -eq 'detach' -and "$($stack.DenySettings.Mode)" -match '^denyDelete$' -and -not ($rules -contains 'allow-ssh')
    if ($atStart) { Say "  OK   stack '$($cfg.stackName)' is at the starting point" Green }
    else {
        Say "  ..   deploying stack '$($cfg.stackName)' from app.v1.bicep (a few minutes)" DarkGray
        # DeleteResources first re-manages vnet-app and removes anything a rehearsal added (like rt-app
        # from the V2 demo). Then DetachAll puts action on unmanage back to detach for the demo.
        $null = Set-AzResourceGroupDeploymentStack -Name $cfg.stackName -ResourceGroupName $cfg.resourceGroup -TemplateFile $v1 `
            -ActionOnUnmanage DeleteResources -DenySettingsMode $cfg.denySettingsMode -Force -WarningAction SilentlyContinue
        $null = Set-AzResourceGroupDeploymentStack -Name $cfg.stackName -ResourceGroupName $cfg.resourceGroup -TemplateFile $v1 `
            -ActionOnUnmanage DetachAll -DenySettingsMode $cfg.denySettingsMode -Force -WarningAction SilentlyContinue
        Say "  OK   stack '$($cfg.stackName)' reset to the starting point" Green
    }

    # 4. Detached leftovers from V2 rehearsals (only rt-app, only in this resource group).
    $rt = Get-AzResource -ResourceGroupName $cfg.resourceGroup -Name 'rt-app' -ErrorAction SilentlyContinue
    if ($rt) { Remove-AzResource -ResourceId $rt.ResourceId -Force | Out-Null; Say '  OK   removed leftover rt-app' Green }
}
Reset-DemoStack

# 5. Old What-If results, so the list in step 9 is clean.
$old = @(Get-AzResourceGroupDeploymentStackWhatIfResult -ResourceGroupName $cfg.resourceGroup -ErrorAction SilentlyContinue)
foreach ($w in $old) { Remove-AzResourceGroupDeploymentStackWhatIfResult -ResourceGroupName $cfg.resourceGroup -Name $w.Name -Force -Confirm:$false -ErrorAction SilentlyContinue | Out-Null }
if ($old.Count) { Say "  OK   cleared $($old.Count) old What-If results" Green }

# 6. The brownfield resource group for the AI demo (hand-made resources, no stack).
& (Join-Path $PSScriptRoot 'Prepare-Brownfield.ps1')

# 7. Optional: refresh the saved results used by -Replay with a full live pass.
if ($CaptureReplay) {
    Say '  ..   running a full live pass to refresh the saved results (a few minutes)' DarkGray
    & (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'demo.ps1') -NoPause | Out-Null
    $saved = @(Get-ChildItem (Join-Path $PSScriptRoot '_replay') -Filter '*.txt').Count
    Say "  OK   $saved saved results refreshed" Green
    # The live pass really deploys the change in step 10, so put the stack back again.
    Reset-DemoStack
    foreach ($w in @(Get-AzResourceGroupDeploymentStackWhatIfResult -ResourceGroupName $cfg.resourceGroup -ErrorAction SilentlyContinue)) {
        Remove-AzResourceGroupDeploymentStackWhatIfResult -ResourceGroupName $cfg.resourceGroup -Name $w.Name -Force -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
    }
}

Say ''
Say 'Ready for the stage.' Green
