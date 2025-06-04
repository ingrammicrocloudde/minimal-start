# Minimal Start

This repository contains ARM templates for deploying:
- Hub-spoke network architecture with two VNets
- Windows Server 2022 VM with public IP in the hub network
- Premium file storage

## Deploy to Azure

Click the button below to deploy this template to your Azure subscription:

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fingrammicrocloudde%2Fminimal-start%2Frefs%2Fheads%2Fmain%2Fdeploy.json%0A)

## Parameters

You can customize the deployment with these parameters:
- `location`: Azure region for deployment
- `hubVnetName` & `spokeVnetName`: Names for your virtual networks
- `vmName`: Name for your Windows Server VM
- `adminUsername` & `adminPassword`: Credentials for VM access
- `fileShareName`: Name for your premium file share

See `parameters.json` for default values and more options.


## Deployment options: 

**Azure CLI:**
```sh
az deployment group create --resource-group YourResourceGroup --template-file deploy.json --parameters parameters.json
```
or

**PowerShell:**
```ps
New-AzResourceGroupDeployment -ResourceGroupName YourResourceGroup -TemplateFile deploy.json -TemplateParameterFile parameters.json
```
