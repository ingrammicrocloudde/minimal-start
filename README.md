# minimal-start




## Deployment options: 
Azure CLI: 
az deployment group create --resource-group YourResourceGroup --template-file deploy.json --parameters parameters.json
or
Powershell: 
New-AzResourceGroupDeployment -ResourceGroupName YourResourceGroup -TemplateFile deploy.json -TemplateParameterFile parameters.json
