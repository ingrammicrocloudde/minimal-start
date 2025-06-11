# Minimal Start

This repository contains ARM templates for deploying a minimal environment for starters:

- Hub-spoke network architecture with two VNets and peering
- Windows Server 2022 VM with public IP in the hub network (will become DC)
- and a second vm (win11) to be made session host later.

**Powershell scripts for configuration:**

- Premium file storage deployment
- promote vm to DC
- join WIN11 to domain
- domain join fileshare
- install FSlogix

## Deploy to Azure

Click the button below to deploy the base template to your Azure subscription:

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fingrammicrocloudde%2Fminimal-start%2Frefs%2Fheads%2Fmain%2Fdeploy.json%0A)

## Parameters

You can customize the deployment with these parameters:

- `location`: Azure region for deployment
- `hubVnetName` & `spokeVnetName`: Names for your virtual networks
- `vmName`: Name for your Windows Server VM
- `adminUsername` & `adminPassword`: Credentials for VM access
- `fileShareName`: Name for your premium file share

See `parameters.json` for default values and more options.

**Easy Deployment of AVD backend:**
AVD needs a backend consiting of:

- Hostpool
- Application Group
- Workspace

No need to work your way through the Azure portal.

Please **click the button below** to deploy the AVD template to your Azure subscription:

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fingrammicrocloudde%2Fminimal-start%2Frefs%2Fheads%2Fmain%2F06deployavd.json)

To get access to the AVD functionality the following roles must be assigned.

- Desktop Virtualization Application Group Reader
- Desktop Virtualization Workspace Reader
- Desktop Virtualization Contributor
- Virtual Machine Administrator Login
- Virtual Machine User  Login

It is highly recommended to create an Entra Id group for the AVD users and a second group for the AVD administrators. These groups should be assigned the proper roles.

## Deployment options for minimal template

**Azure CLI:**

```sh
az deployment group create --resource-group YourResourceGroup --template-file deploy.json --parameters parameters.json
```

or

**PowerShell:**

```ps
New-AzResourceGroupDeployment -ResourceGroupName YourResourceGroup -TemplateFile deploy.json -TemplateParameterFile parameters.json
```
