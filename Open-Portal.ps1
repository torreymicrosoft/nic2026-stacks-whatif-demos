<#
    Opens Edge with the portal tabs for the demo: the stack, its resource group, and the
    brownfield resource group for the AI demo. Sign in once, then leave the window open.
#>
$cfg = Get-Content (Join-Path $PSScriptRoot 'demo.config.json') -Raw | ConvertFrom-Json
$tenant = if ($cfg.tenantId) { "@$($cfg.tenantId)" } else { '' }
$base = "https://portal.azure.com/#$tenant/resource/subscriptions/$($cfg.subscriptionId)/resourceGroups"
$urls = @(
    "$base/$($cfg.resourceGroup)/providers/Microsoft.Resources/deploymentStacks/$($cfg.stackName)/overview",
    "$base/$($cfg.resourceGroup)/overview",
    "$base/$($cfg.brownfieldResourceGroup)/overview"
)
Start-Process msedge.exe -ArgumentList (@('--new-window') + $urls)
