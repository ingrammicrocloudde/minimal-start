param(
    [string]$ResourceGroupName = "avd-bootcamp-rg
",
    [string]$RandomSuffix = (Get-Random -Minimum 1000 -Maximum 9999),
    [string]$StorageAccountName = "sanavd$RandomSuffix",
    [string]$ShareName = "share",
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
# Change the execution policy to bypass for importing AzFilesHybrid.psm1 module
    Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
    Set-PSRepository -Name "PSGallery" -InstallationPolicy:Trusted
    
    # Install PowerShellGet if needed without restart warnings
    $PowerShellGetModule = Get-Module PowerShellGet -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1
    if (-not $PowerShellGetModule -or $PowerShellGetModule.Version -lt [Version]"2.2.5") {
        Write-Output "Installing PowerShellGet module..."
        Install-Module -Name PowerShellGet -MinimumVersion 2.2.5 -Force -AllowClobber -Scope CurrentUser -SkipPublisherCheck -Confirm:$false
        Remove-Module PowerShellGet -Force -ErrorAction SilentlyContinue
        Import-Module PowerShellGet -MinimumVersion 2.2.5 -Force
    }
    
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
            Install-Module -Name $M.Key -MinimumVersion $($M.Value) -Force -AllowClobber -Scope CurrentUser -SkipPublisherCheck -Confirm:$false
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
                Install-Module -Name $M.Key -MinimumVersion $($M.Value) -Force -AllowClobber -Scope CurrentUser -SkipPublisherCheck -Confirm:$false
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
        $zipUrl = "https://github.com/Azure-Samples/azure-files-samples/releases/download/v0.3.2/AzFilesHybrid.zip"

        # Temporaeres Verzeichnis erstellen
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

        Write-Output "Copy AzFilesHybrid module to PowerShell module path"
        # Save current location
        $originalLocation = Get-Location
        Set-Location $extractionPath
        . .\CopyToPSPath.ps1
        # Restore original location before cleanup
        Set-Location $originalLocation
  
        Write-Output "Remove temporary files"
        Remove-Item -Path $zipFilePath -Force
        Remove-Item -Path $extractionPath -Recurse -Force
        }
    catch {
        throw "Failed to extract ZIP file: $_"
    }
    Write-Output "The AzFilesHybrid module has been installed. Attempting to import it now..."
try {
    Import-Module -Name AzFilesHybrid -Force -WarningAction:SilentlyContinue
    Write-Output "AzFilesHybrid module imported successfully."
} catch {
    Write-Warning "Failed to import AzFilesHybrid module. You may need to restart PowerShell and run the script again."
    throw "Module import failed: $_"
}
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
                                -SkuName Premium_LRS `
                                -Kind FileStorage `
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

# Create the premium file share
$SAKey = (Get-AzStorageAccountKey -ResourceGroupName $ResourceGroupName -AccountName $StorageAccountName)[0].Value
$SAContext = New-AzStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $SAKey

# Create the file share first
$fileShare = New-AzStorageShare -Context $SAContext -Name $ShareName

# Set the quota for premium file share (required for premium storage)
Set-AzStorageShareQuota -ShareName $ShareName -Context $SAContext -Quota 100

Write-Output "Premium file share '$ShareName' created successfully with 100 GiB quota."

$Uri = "\\" + $account.PrimaryEndpoints.File.Split('/')[2] + "\" + $fileShare.Name

if ( $CheckConfiguration ) {
    Debug-AzStorageAccountAuth -StorageAccountName $StorageAccountName -ResourceGroupName $ResourceGroupName -Verbose
    New-PSDrive -Name Z -PSProvider FileSystem -Root $Uri -Persist:$false -Scope Global
    #net use Z: $Uri #/user:localhost\$($StorageAccountName) $SAKey /persistent:no
}

Write-host "Created Share: $Uri"

Write-Output "Script Add-StorageAccount2AD.ps1 version $Version completed."
