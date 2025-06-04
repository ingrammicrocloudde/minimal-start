# PowerShell script to integrate Azure Premium File Storage account into a domain
# Make sure to run this script as Administrator on a domain-joined machine

# Azure File Share Variables - change these as needed
$SubscriptionId = "00000000-0000-0000-0000-000000000000" # Your Azure subscription ID
$ResourceGroupName = "YourResourceGroup"                 # Resource group containing the storage account
$StorageAccountName = "yourstorageaccount"               # Azure storage account name
$FileShareName = "premiumshare"                          # Name of the Azure file share
$DriveLetter = "Z"                                       # Drive letter to map the share to (optional)

# Domain Variables
$DomainName = "corp.example.com"                         # Your domain FQDN
$DomainAdminsGroup = "$DomainName\Domain Admins"         # Domain Admins group
$DomainUsersGroup = "$DomainName\Domain Users"           # Domain Users group

# Login to Azure
Write-Host "Connecting to Azure..." -ForegroundColor Cyan
Connect-AzAccount
Set-AzContext -Subscription $SubscriptionId

# Get the storage account and create a context
Write-Host "Getting storage account context..." -ForegroundColor Cyan
$storageAccount = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName
$storageAccountKey = (Get-AzStorageAccountKey -ResourceGroupName $ResourceGroupName -Name $StorageAccountName)[0].Value
$ctx = New-AzStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $storageAccountKey

# Check if file share exists, create it if it doesn't
$share = Get-AzStorageShare -Name $FileShareName -Context $ctx -ErrorAction SilentlyContinue
if (-not $share) {
    Write-Host "Creating new Azure file share: $FileShareName" -ForegroundColor Green
    $share = New-AzStorageShare -Name $FileShareName -Context $ctx
} else {
    Write-Host "Azure file share $FileShareName already exists" -ForegroundColor Yellow
}

# Enable Azure AD Domain Services authentication for the storage account
Write-Host "Enabling Azure AD Domain Services authentication for the storage account..." -ForegroundColor Cyan
Update-AzStorageAccountAuthForAES256 -ResourceGroupName $ResourceGroupName -StorageAccountName $StorageAccountName

# Get storage account
$storageAccount = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName

# Enable AD authentication on the storage account
Set-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -EnableActiveDirectoryDomainServicesForFile $true -ActiveDirectoryDomainName $DomainName

# Install required modules if not already installed
if (-not (Get-Module -ListAvailable -Name Az.Storage)) {
    Install-Module -Name Az.Storage -Force -AllowClobber
}

# Create a directory to store credentials
$credentialPath = "$env:USERPROFILE\.azurestorageaccountkeys"
if (-not (Test-Path -Path $credentialPath)) {
    New-Item -Path $credentialPath -ItemType Directory -Force
}

# Save the storage account key to a secure file
$secureKey = ConvertTo-SecureString -String $storageAccountKey -AsPlainText -Force
$credentialFile = "$credentialPath\$StorageAccountName.cred"
New-Object System.Management.Automation.PSCredential -ArgumentList "Azure\$StorageAccountName", $secureKey | Export-Clixml -Path $credentialFile
Write-Host "Storage account credentials saved to $credentialFile" -ForegroundColor Green

# Function to create a persistent drive mapping that will survive reboots
function Create-PersistentDriveMapping {
    param (
        [string]$DriveLetter,
        [string]$UncPath,
        [string]$Username,
        [string]$Password
    )
    
    # Remove existing drive mapping if present
    if (Test-Path "${DriveLetter}:") {
        Remove-PSDrive -Name $DriveLetter -Force -ErrorAction SilentlyContinue
        net use ${DriveLetter}: /delete /y
    }
    
    # Create the persistent mapping
    $result = net use ${DriveLetter}: $UncPath /user:$Username $Password /persistent:yes
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Successfully mapped drive ${DriveLetter}: to $UncPath" -ForegroundColor Green
    } else {
        Write-Host "Failed to map drive ${DriveLetter}: to $UncPath. Error: $result" -ForegroundColor Red
    }
}

# Create the UNC path to the Azure file share
$uncPath = "\\$StorageAccountName.file.core.windows.net\$FileShareName"

# Optional: Map the Azure file share as a network drive
if ($DriveLetter) {
    Write-Host "Mapping Azure file share to drive ${DriveLetter}:..." -ForegroundColor Cyan
    Create-PersistentDriveMapping -DriveLetter $DriveLetter -UncPath $uncPath -Username "Azure\$StorageAccountName" -Password $storageAccountKey
}

# Create a group policy to map the drive for domain users (requires Group Policy Management tools)
Write-Host "`nTo create a GPO to map this drive for domain users:" -ForegroundColor Yellow
Write-Host "1. Install Group Policy Management tools: Install-WindowsFeature -Name GPMC" -ForegroundColor Gray
Write-Host "2. Create a new GPO and edit it" -ForegroundColor Gray
Write-Host "3. Under User Configuration > Preferences > Windows Settings > Drive Maps, create a new mapped drive" -ForegroundColor Gray
Write-Host "4. Configure the following settings:" -ForegroundColor Gray
Write-Host "   - Action: Create" -ForegroundColor Gray
Write-Host "   - Location: $uncPath" -ForegroundColor Gray
Write-Host "   - Drive Letter: ${DriveLetter}:" -ForegroundColor Gray
Write-Host "   - Reconnect: Enabled" -ForegroundColor Gray
Write-Host "   - Connect as: Azure\$StorageAccountName" -ForegroundColor Gray
Write-Host "   - Enter the storage account key as the password" -ForegroundColor Gray

# Instructions for Azure AD Kerberos authentication setup
Write-Host "`nFor Azure AD Kerberos authentication (recommended for domain-joined computers):" -ForegroundColor Yellow
Write-Host "1. Run Set-AzStorageAccount with the following parameters:" -ForegroundColor Gray
Write-Host "   Set-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -EnableAzureActiveDirectoryKerberosForFile `$true -ActiveDirectoryDomainName $DomainName" -ForegroundColor Gray
Write-Host "2. Assign the 'Storage File Data SMB Share Contributor' role to the appropriate AD groups" -ForegroundColor Gray
Write-Host "   New-AzRoleAssignment -RoleDefinitionName 'Storage File Data SMB Share Contributor' -ApplicationId 'Provide your application ID' -ResourceName $StorageAccountName -ResourceType 'Microsoft.Storage/storageAccounts' -ResourceGroupName $ResourceGroupName" -ForegroundColor Gray

Write-Host "`nAzure Premium File Storage account integration completed!" -ForegroundColor Green
