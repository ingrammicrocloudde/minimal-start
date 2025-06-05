# PowerShell script to integrate Azure Premium File Storage account into a domain
# Modified: 2025-06-04
# Makes connections using storage account key authentication (no Azure AD Domain Services)
# Run this script as Administrator on a domain-joined machine

# Azure File Share Variables - change these as needed
param(
[string]$SubscriptionId = "00000000-0000-0000-0000-000000000000", # Your Azure subscription ID
[string]$ResourceGroupName = "YourResourceGroup",                 # Resource group containing the storage account
[string]$StorageAccountName = "yourstorageaccount",               # Azure storage account name
[string]$FileShareName = "premiumshare",                          # Name of the Azure file share
[string]$DriveLetter = "Z",                                       # Drive letter to map the share to (optional)
[string]$Username = "aktapaz",                                   # Username for the storage account (usually "Azure\<StorageAccountName>")
[string]$DomainName = "corp.example.com"                          # Your domain FQDN
)


# Login to Azure
Write-Host "Connecting to Azure..." -ForegroundColor Cyan
Connect-AzAccount -UseDeviceAuthentication 
Set-AzContext -Subscription $SubscriptionId

Get-AzContext.Subscription.Id 

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

# Install required modules if not already installed
if (-not (Get-Module -ListAvailable -Name Az.Storage)) {
    Write-Host "Installing Az.Storage module..." -ForegroundColor Cyan
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
        Write-Host "Removing existing drive mapping ${DriveLetter}:..." -ForegroundColor Yellow
        Remove-PSDrive -Name $DriveLetter -Force -ErrorAction SilentlyContinue
        net use ${DriveLetter}: /delete /y
    }
    
    # Create the persistent mapping
    Write-Host "Creating drive mapping ${DriveLetter}: -> $UncPath..." -ForegroundColor Cyan
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

# Function to create a script that can be run by end users to map the drive
function Create-MappingScript {
    param (
        [string]$DriveLetter,
        [string]$UncPath,
        [string]$Username,
        [string]$Password,
        [string]$OutputPath = "$env:USERPROFILE\Desktop\MapAzureDrive.ps1"
    )
    
    $scriptContent = @"
# Script to map Azure File Share
# Created: $(Get-Date -Format "yyyy-MM-dd")

# Map the Azure file share as a drive
`$DriveLetter = "$DriveLetter"
`$UncPath = "$UncPath"
`$Username = "$Username"
`$Password = "$Password"

# Remove existing drive mapping if present
if (Test-Path "`${DriveLetter}:") {
    Remove-PSDrive -Name `$DriveLetter -Force -ErrorAction SilentlyContinue
    net use `${DriveLetter}: /delete /y
}

# Create the persistent mapping
Write-Host "Mapping Azure file share to drive `${DriveLetter}:..."
`$result = net use `${DriveLetter}: `$UncPath /user:`$Username `$Password /persistent:yes

if (`$LASTEXITCODE -eq 0) {
    Write-Host "Successfully mapped drive `${DriveLetter}: to `$UncPath" -ForegroundColor Green
} else {
    Write-Host "Failed to map drive `${DriveLetter}: to `$UncPath. Error: `$result" -ForegroundColor Red
}

Write-Host "Press any key to continue..."
`$null = `$Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
"@

    $scriptContent | Out-File -FilePath $OutputPath -Encoding utf8
    Write-Host "Created mapping script at $OutputPath" -ForegroundColor Green
}

# Create a user-friendly mapping script
Create-MappingScript -DriveLetter $DriveLetter -UncPath $uncPath -Username "Azure\$StorageAccountName" -Password $storageAccountKey -OutputPath "$env:USERPROFILE\Desktop\MapAzureDrive.ps1"

# Create a logon script for Group Policy deployment
$logonScriptPath = "$env:WINDIR\SYSVOL\sysvol\$DomainName\scripts"
if (Test-Path -Path $logonScriptPath) {
    $gpoScriptPath = "$logonScriptPath\MapAzureDrive.ps1"
    Create-MappingScript -DriveLetter $DriveLetter -UncPath $uncPath -Username "Azure\$StorageAccountName" -Password $storageAccountKey -OutputPath $gpoScriptPath
    Write-Host "Created GPO logon script at $gpoScriptPath" -ForegroundColor Green
} else {
    Write-Host "SYSVOL path not accessible. Run this script on a domain controller to create a GPO logon script." -ForegroundColor Yellow
}

# Instructions for Group Policy deployment
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

# Alternatively, use the PowerShell logon script method
Write-Host "`nAlternatively, to use the PowerShell script for GPO:" -ForegroundColor Yellow
Write-Host "1. In Group Policy Management, edit your GPO" -ForegroundColor Gray
Write-Host "2. Under User Configuration > Policies > Windows Settings > Scripts > Logon" -ForegroundColor Gray
Write-Host "3. Add a new PowerShell script and browse to $gpoScriptPath" -ForegroundColor Gray

# Test the connection
Write-Host "`nTesting connection to Azure file share..." -ForegroundColor Cyan
if (Test-Path "${DriveLetter}:") {
    Write-Host "Connection successful! Drive ${DriveLetter}: is mapped to Azure file share." -ForegroundColor Green
    
    # Get some basic information about the share
    $driveInfo = Get-PSDrive -Name $DriveLetter
    Write-Host "Drive Information:" -ForegroundColor Cyan
    Write-Host "  Free Space: $([math]::Round($driveInfo.Free / 1GB, 2)) GB" -ForegroundColor Gray
    Write-Host "  Used Space: $([math]::Round(($driveInfo.Used / 1GB), 2)) GB" -ForegroundColor Gray
} else {
    Write-Host "Connection test failed. Please check your storage account credentials and network connectivity." -ForegroundColor Red
}

Write-Host "`nAzure Premium File Storage account integration completed!" -ForegroundColor Green
Write-Host "Script executed by: $Username on $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")" -ForegroundColor Gray