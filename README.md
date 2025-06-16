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

To join the session host to the hostpool you will need 3 components: 

- a Registration Key (obtained form Azure portal / Hostpool section)
- Azure Virtual Desktop Agent (<https://go.microsoft.com/fwlink/?linkid=2310011>)
- Azure Virtual Desktop Agent Bootloader (<https://go.microsoft.com/fwlink/?linkid=2311028>)

This will add the VM as a session host.

To get access to the AVD functionality the following roles must be assigned.

- Desktop Virtualization Application Group Reader (aebf23d0-b568-4e86-b8f9-fe83a2c6ab55)
- Desktop Virtualization Workspace Reader (0fa44ee9-7a7d-466b-9bb2-2bf446b1204d)
- Desktop Virtualization Contributor (082f0a83-3be5-4ba1-904c-961cca79b387)
- Virtual Machine Administrator  (1c0163c0-47e6-4577-8991-ea5c82e286e4)
- Virtual Machine User Login (fb879df8-f326-4884-b1cf-06f3ad86be52)

It is highly recommended to create an Entra Id group for the AVD users and a second group for the AVD administrators. These groups should be assigned the proper roles.

## Deployment options for minimal template

**BASH:**

```sh
az deployment group create --resource-group YourResourceGroup --template-file deploy.json --parameters parameters.json
```

or

**PowerShell:**

```ps
New-AzResourceGroupDeployment -ResourceGroupName YourResourceGroup -TemplateFile deploy.json -TemplateParameterFile parameters.json
```

## Assign roles with AZ CLI

We will run the commands in sequence, adding more rights step by step.

### BASH

```sh
az role assignment create --assignee heinz.test@beispiel.com  --role "Desktop Virtualization Application Group Reader" --scope /subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/MyResourceGroup

az role assignment create --assignee heinz.test@beispiel.com  --role "Desktop Virtualization Workspace Reader" --scope /subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/MyResourceGroup

az role assignment create --assignee heinz.test@beispiel.com  --role "Desktop Virtualization Contributor" --scope /subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/MyResourceGroup

az role assignment create --assignee heinz.test@beispiel.com  --role "Virtual Machine Administrator Login" --scope /subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/MyResourceGroup

az role assignment create --assignee heinz.test@beispiel.com  --role "Virtual Machine User Login" --scope /subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/MyResourceGroup
