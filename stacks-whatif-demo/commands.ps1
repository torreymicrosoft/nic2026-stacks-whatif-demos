# Stacks What-If demo, NIC 2026
# Copy a command into the terminal and press Enter, or put the cursor on it and press Ctrl+Enter.
# Azure PowerShell first. The Azure CLI version is in the comment under it.

# The change: app.v2.bicep changes one line, the storage SKU.
code --diff app.v1.bicep app.v2.bicep

# 1. Regular What-If on the change.
New-AzResourceGroupDeployment -ResourceGroupName rg-demo-nic2026-stacks -TemplateFile app.v2.bicep -WhatIf
# az deployment group what-if --resource-group rg-demo-nic2026-stacks --template-file app.v2.bicep

# 2. Deploy the template that's running today, app.v1.bicep, as a stack. -Force is the only optional one.
New-AzResourceGroupDeploymentStack -Name stack-app -ResourceGroupName rg-demo-nic2026-stacks -TemplateFile app.v1.bicep -ActionOnUnmanage DetachAll -DenySettingsMode DenyDelete -Force
# az stack group create --name stack-app --resource-group rg-demo-nic2026-stacks --template-file app.v1.bicep --action-on-unmanage detachAll --deny-settings-mode denyDelete --yes

# 3. Stacks What-If on the same change. Every parameter is required except -Force.
$stackId = (Get-AzResourceGroupDeploymentStack -ResourceGroupName rg-demo-nic2026-stacks -Name stack-app).Id
# $stackId = az stack group show --name stack-app --resource-group rg-demo-nic2026-stacks --query id --output tsv
New-AzResourceGroupDeploymentStackWhatIfResult -Name whatif-sku -ResourceGroupName rg-demo-nic2026-stacks -StackResourceId $stackId -TemplateFile app.v2.bicep -ActionOnUnmanage DetachAll -DenySettingsMode DenyDelete -RetentionInterval PT1H -Force
# az stack-whatif group create --name whatif-sku --resource-group rg-demo-nic2026-stacks --stack-id $stackId --template-file app.v2.bicep --action-on-unmanage detachAll --deny-settings-mode denyDelete --retention-interval PT1H

# The next change: app.v3.bicep is app.v1.bicep, the one that's deployed, without the virtual network.
code --diff app.v1.bicep app.v3.bicep

# 4. Stacks What-If on that, with action on unmanage set to delete.
New-AzResourceGroupDeploymentStackWhatIfResult -Name whatif-delete -ResourceGroupName rg-demo-nic2026-stacks -StackResourceId $stackId -TemplateFile app.v3.bicep -ActionOnUnmanage DeleteResources -DenySettingsMode DenyDelete -RetentionInterval PT1H -Force
# az stack-whatif group create --name whatif-delete --resource-group rg-demo-nic2026-stacks --stack-id $stackId --template-file app.v3.bicep --action-on-unmanage deleteResources --deny-settings-mode denyDelete --retention-interval PT1H

# 5. Deploy it. The stack deletes the virtual network. This one takes about 3 minutes.
Set-AzResourceGroupDeploymentStack -Name stack-app -ResourceGroupName rg-demo-nic2026-stacks -TemplateFile app.v3.bicep -ActionOnUnmanage DeleteResources -DenySettingsMode DenyDelete -Force
# az stack group create --name stack-app --resource-group rg-demo-nic2026-stacks --template-file app.v3.bicep --action-on-unmanage deleteResources --deny-settings-mode denyDelete --yes

# 6. Try to delete one of the stack's resources outside of the stack.
Remove-AzResource -ResourceGroupName rg-demo-nic2026-stacks -ResourceName nsg-app -ResourceType Microsoft.Network/networkSecurityGroups -Force
# az network nsg delete --resource-group rg-demo-nic2026-stacks --name nsg-app

# 7. The What-If results are resources in Azure.
Get-AzResourceGroupDeploymentStackWhatIfResult -ResourceGroupName rg-demo-nic2026-stacks | Format-Table Name, Type
# az stack-whatif group list --resource-group rg-demo-nic2026-stacks --output table

# If Azure can't be reached, show what a rehearsal saved for that step instead, for example: ..\Show-Saved.ps1 3