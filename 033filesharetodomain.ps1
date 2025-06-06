<#
.SYNOPSIS
    This script configures an Azure Storage Account and integrates it with Active Directory.

.DESCRIPTION
    The script performs the following tasks:
    - Checks if the script is running with administrative privileges.
    - Installs required PowerShell modules if they are not already installed.
    - Configures the Azure Storage Account.
    - Integrates the Storage Account with Active Directory.
    - Sets default permissions for the Storage Account.
    - Optionally configures a private DNS zone.

.PARAMETER ResourceGroupName
    The name of the resource group where the storage account is located. This parameter is mandatory.

.PARAMETER StorageAccountName
    The name of the storage account to be configured. This parameter is mandatory.

.PARAMETER ShareName
    The name of the file share to be created in the storage account. This parameter is mandatory.

.PARAMETER OuDistinguishedName
    The distinguished name of the organizational unit (OU) in Active Directory where the storage account will be integrated.

.PARAMETER defaultPermission
    The default permission to be set for the storage account. Valid values are:
    - None
    - StorageFileDataSmbShareContributor
    - StorageFileDataSmbShareReader
    - StorageFileDataSmbShareElevatedContributor
    Default value is "StorageFileDataSmbShareContributor".

.PARAMETER privateDnsZoneName
    The name of the private DNS zone to be configured. Default value is "privatelink.file.core.windows.net".

.PARAMETER ADDnsZone
    A switch parameter to indicate if an AD DNS zone should be configured.

.PARAMETER CheckConfiguration
    A switch parameter to indicate if the script should check the existing configuration before making changes.

.EXAMPLE
    .\Add-StorageAccount2AD.ps1 -ResourceGroupName "MyResourceGroup" -StorageAccountName "mystorageaccount" -ShareName "myshare" -OuDistinguishedName "OU=Computers,OU=MyOU,DC=mydomain,DC=com"

.NOTES
    Version: 0.5.3
    Author: Robert Rasp (robert.rasp@ingrammicro.com)
    Date: 3.03.2025
#>

param(
    [Parameter(Mandatory=$true)][string]$ResourceGroupName, #= "RR-OCC-02-Peering",
    [Parameter(Mandatory=$true)][string]$StorageAccountName, #= "sa29012025n002",
    [Parameter(Mandatory=$true)][string]$ShareName, #= "share",
    [string]$OuDistinguishedName, # = "OU=Computers,OU=OU1,OU=RootOU,DC=truekillrob,DC=com",
    [ValidateSet("None","StorageFileDataSmbShareContributor","StorageFileDataSmbShareReader","StorageFileDataSmbShareElevatedContributor")] # Set the default permission of your choice
    [string]$defaultPermission = "StorageFileDataSmbShareContributor",    
    [string]$privateDnsZoneName = "privatelink.file.core.windows.net",
    #[switch]$ADDnsZone, # Not working yet
    [switch]$CheckConfiguration
)

$Version = "0.5.3"

Write-Output "Starting script $($MyInvocation.MyCommand.Name) version $Version"

# Check if the script is running as Administrator
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $IsAdmin) {
    throw "This script must be run as an Administrator."
}

try {
# Change the execution policy to unblock importing AzFilesHybrid.psm1 module
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope:Process
    Set-PSRepository -Name "PSGallery" -InstallationPolicy:Trusted
    Write-Output "Check installed modules..."
    $Modules = @{
        "Az.Accounts" = "3.0.5"
        "Az.Storage" = "7.4.0"
        "Az.Network" = "7.9.0"
        "Az.Resources" = "7.5.0"
        "Az.PrivateDns" = "1.1.0"
    }

    foreach ( $M in $Modules.GetEnumerator()) {
        $InstMod = Get-Module $M.Key -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1
        if ( -not $InstMod -or $InstMod.Version -lt [Version]$M.Value ) {
            Write-Output "Install $($M.Key) module..."
            Install-Module -Name $M.Key -MinimumVersion $($M.Value) -Force -AllowClobber
        }
    }

    if ( $CheckConfiguration ) {
        $Modules = @{
            "Microsoft.Graph.Authentication" = "2.25.0"
            "Microsoft.Graph.Users" = "2.25.0"
            "Microsoft.Graph.Groups" = "2.25.0"
            "Microsoft.Graph.Identity.DirectoryManagement" = "2.25.0"
        }
        foreach ( $M in $Modules.GetEnumerator()) {
            $InstMod = Get-Module $M.Key -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1
            if ( -not $InstMod -or $InstMod.Version -lt [Version]$M.Value ) {
                Write-Output "Install $($M.Key) module..."
                Install-Module -Name $M.Key -MinimumVersion $($M.Value) -Force -AllowClobber
            }
        }
    }
}
catch {
    throw "Failed to install or import required modules: $_"
}

$InstMod = Get-Module "AzFilesHybrid" -ListAvailable
if ( -not $InstMod ) {
Write-Output "Install AzFilesHybrid module..."
    try {
        # URL der ZIP-Datei for AzFilesHybrid
        $zipUrl = "https://github.com/Azure-Samples/azure-files-samples/releases/download/latest/AzFilesHybrid.zip"   #"https://github.com/Azure-Samples/azure-files-samples/releases/download/v0.3.2/AzFilesHybrid.zip"

        # TemporÃ¤res Verzeichnis erstellen
        $tempDir = [System.IO.Path]::GetTempPath()
        $zipFilePath = Join-Path -Path $tempDir -ChildPath "AzFilesHybrid.zip"

        # ZIP-Datei herunterladen
        Write-Output "Download ZIP file from $zipUrl"
        Write-Output "to $zipFilePath"
        Invoke-WebRequest -Uri $zipUrl -OutFile $zipFilePath
    }
    catch {
        throw "Failed to download ZIP file: $_"
    }

    # ZIP-Datei entpacken
    try {
        # Verzeichnis zum Entpacken erstellen
        $extractionPath = Join-Path -Path $tempDir -ChildPath "AzFilesHybrid"
        if (-Not (Test-Path -Path $extractionPath)) {
            New-Item -ItemType Directory -Path $extractionPath | Out-Null
        }
        Write-Output "ZIP file extracted to $extractionPath"
        Expand-Archive -Path $zipFilePath -DestinationPath $extractionPath -Force

        Write-Output "Copy AzFliesHybrid module to PowerShell module path"
        Set-Location $extractionPath
        . .\CopyToPSPath.ps1
  
        Write-Output "Remove temporary files"
        Remove-Item -Path $zipFilePath -Force
        Remove-Item -Path $extractionPath -Recurse -Force
        }
    catch {
        throw "Failed to extract ZIP file: $_"
    }
    Write-Warning "The AzFilesHybrid module has been installed. Please open a new PowerShell-Window and restart the script."
    exit
}

try {
    write-output "Import Azure-Modules module..."
    Import-Module -Name Az.Accounts, Az.Storage, Az.Network, Az.Resources, Az.PrivateDns -WarningAction:SilentlyContinue
    write-output "Import ActiveDirectory-Modules module..."
    Import-Module ActiveDirectory
    write-output "Import AzFilesHybrid-Modules module..."
    Import-Module -Name AzFilesHybrid -WarningAction:SilentlyContinue
    if ( $CheckConfiguration ) {
        write-output "Import MSGraph-Modules module..."
        Import-Module -Name Microsoft.Graph.Users, Microsoft.Graph.Groups, Microsoft.Graph.Identity.DirectoryManagement -WarningAction:SilentlyContinue
    }
}
catch {
    throw "Failed to import modules: $_"
}

if ( -not $OuDistinguishedName ) {
    $ADDomain = Get-ADDomain
    $OuDistinguishedName = $ADDomain.ComputersContainer
}

Clear-AzContext -ErrorAction:SilentlyContinue -force
$Error.Clear()
try {
    Connect-AzAccount -DeviceAuth

    $AZContext = Get-AzContext
    Select-AzSubscription -SubscriptionId $AZContext.Subscription.Id | Out-Null
}
catch {
    throw "Failed to login to Azure: $_"
}

$RG = Get-AzResourceGroup -ResourceGroupName $ResourceGroupName
if ( -not $RG ) {
    throw "Resource group '$ResourceGroupName' not found."
}

$StorageAccount = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -ErrorAction:SilentlyContinue
if ( -not $StorageAccount ) {
    $Error.Clear()

    # Retrieve the virtual network and subnet
    $vnet = Get-AzVirtualNetwork -ResourceGroupName $ResourceGroupName | Select-Object -First 1
    $Location = $vnet.Location
    $subnet = Get-AzVirtualNetworkSubnetConfig -VirtualNetwork $vnet -ErrorAction:SilentlyContinue | Where-Object { $_.Name -ne "GatewaySubnet" } | Select-Object -First 1

    if ( -not $subnet ) {
        throw "No suitable subnet found in virtual network '$($vnet.Name)'."
    }
    
    try {# Create the storage account
            $storageAccount = New-AzStorageAccount `
                                -ResourceGroupName $ResourceGroupName `
                                -Name $StorageAccountName `
                                -Location $Location `
                                -SkuName Standard_LRS `
                                -Kind StorageV2 `
                                -MinimumTlsVersion TLS1_2 `
                                -EnableHierarchicalNamespace $false

        Write-Output "Storage account '$StorageAccountName' created successfully."

        # Create the private endpoint
        $privateEndpoint = New-AzPrivateEndpoint `
                                    -ResourceGroupName $ResourceGroupName `
                                    -Name $("pe_" + $StorageAccountName) `
                                    -Location $Location -Subnet $subnet `
                                    -PrivateLinkServiceConnection @{"Name"="file";"PrivateLinkServiceId"=$storageAccount.Id;"GroupIds"=@("file")}

        Write-Output "Private endpoint '$("pe_" + $StorageAccountName)' created successfully."
    }
    catch {
        throw "Failed to create StorageAccount: $_"
    }
    
    if ( -not $ADDnsZone) {
        $privateDnsZone = Get-AzPrivateDnsZone -ResourceGroupName $ResourceGroupName | Where-Object { $_.Name -eq $privateDnsZoneName }
        try {            # Create the private DNS zone
            if ( -not $privateDnsZone ) {
                $Error.Clear()
                Write-Output "Create Private DNS-Zone: $ResourceGroupName / $privateDnsZoneName"
                $privateDnsZone = New-AzPrivateDnsZone -ResourceGroupName $ResourceGroupName -Name $privateDnsZoneName

                # Link the virtual network to the private DNS zone
                New-AzPrivateDnsVirtualNetworkLink `
                        -ResourceGroupName $ResourceGroupName `
                        -ZoneName $privateDnsZoneName `
                        -Name "myVNetLink" `
                        -VirtualNetworkId $vnet.Id `
                        -ResolutionPolicy "NxDomainRedirect" `
                        -EnableRegistration:$false | Out-Null

                Write-Output "Private DNS zone '$privateDnsZoneName' linked to virtual network '$vnetName' successfully."
            }
            else {
                Write-Output "Private DNS-Zone exists: $ResourceGroupName / $privateDnsZoneName"
                $PrivateLink = Get-AzPrivateDnsVirtualNetworkLink -Zonename $privateDnsZone.Name -ResourceGroupName $privateDnsZone.ResourceGroupName
                if ( $Privatelink.ResolutionPolicy -ne "NxDomainRedirect" -or $PrivateLink.RegistrationEnabled -ne $false ) {
                    Set-AzPrivateDnsVirtualNetworkLink `
                            -ResourceGroupName $privateDnsZone.ResourceGroupName `
                            -ZoneName $privateDnsZone.Name `
                            -Name $PrivateLink.Name `
                            -IsRegistrationEnabled:$false `
                            -ResolutionPolicy "NxDomainRedirect" | Out-Null
                }
            }

            # Create a DNS record for the private endpoint
            $dnsRecord = New-AzPrivateDnsRecordConfig -IPv4Address $privateEndpoint.CustomDnsConfigs[0].IpAddresses[0]
            New-AzPrivateDnsRecordSet `
                    -ResourceGroupName $ResourceGroupName `
                    -ZoneName $privateDnsZoneName `
                    -Name $StorageAccountName `
                    -RecordType A -Ttl 3600 `
                    -PrivateDnsRecords $dnsRecord | Out-Null

            Write-Output "DNS record for private endpoint created successfully."
        }
        catch {
            throw "Failed to create Private DNS Zone: $_"
        }
    }
    else {
        $DNSZone = Get-DNSServerZone -Name $privateDnsZoneName -ErrorAction:SilentlyContinue
        try {
        if ( -not $DNSZone ) {
            $Error.Clear()
            $DNSZone = Add-DNSServerPrimaryZone `
                    -Name $privateDnsZoneName `
                    -DynamicUpdate Secure `
                    -ReplicationScope:Domain
        }
        Add-DnsServerResourceRecordA `
                -ZoneName $privateDnsZoneName `
                -Name $StorageAccountName `
                -IPv4Address $privateEndpoint.CustomDnsConfigs[0].IpAddresses[0] | Out-Null
        }
        catch {
            throw "Failed to create DNS Zone: $_"
        }
    }
}
else {
    Write-Output "Storage account '$StorageAccountName' already exists."
}
# Join the storage account to the Active Directory domain
# Encryption method is AES-256 Kerberos.

Write-Host "Joining Storage Account to AD"
Join-AzStorageAccount `
        -ResourceGroupName $ResourceGroupName `
        -StorageAccountName $StorageAccountName `
        -SamAccountName $StorageAccountName `
        -DomainAccountType "ComputerAccount" `
        -OrganizationUnitDistinguishedName $OuDistinguishedName `
        -OverwriteExistingADObject

$account = Set-AzStorageAccount -ResourceGroupName $ResourceGroupName -AccountName $StorageAccountName -DefaultSharePermission $defaultPermission
#$account.AzureFilesIdentityBasedAuth

# Create the file share
$SAKey = (Get-AzStorageAccountKey -ResourceGroupName $ResourceGroupName -AccountName $StorageAccountName)[0].Value
$SAContext = New-AzStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $SAKey
$fileShare = New-AzStorageShare -Context $SAContext -Name $ShareName
Write-Output "File share '$ShareName' created successfully."

$Uri = "\\" + $account.PrimaryEndpoints.File.Split('/')[2] + "\" + $fileShare.Name

if ( $CheckConfiguration ) {
    Debug-AzStorageAccountAuth -StorageAccountName $StorageAccountName -ResourceGroupName $ResourceGroupName -Verbose
    New-PSDrive -Name Z -PSProvider FileSystem -Root $Uri -Persist:$false -Scope Global
    #net use Z: $Uri #/user:localhost\$($StorageAccountName) $SAKey /persistent:no
}

Write-host "Created Share: $Uri"

Write-Output "Script Add-StorageAccount2AD.ps1 version $Version completed."
