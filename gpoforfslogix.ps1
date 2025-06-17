# PowerShell script to set up FSLogix Group Policy

# Import the Active Directory module
Import-Module ActiveDirectory
Import-Module GroupPolicy

# Define variables
$gpoName = "FSLogix-Configuration"
$fslogixTemplatesUrl = "https://raw.githubusercontent.com/microsoft/fslogix/master/fslogix-templates.zip"
$tempFolder = "$env:TEMP\FSLogix"
$templatesZipFile = "$tempFolder\fslogix-templates.zip"
$policiesFolder = "$tempFolder\fslogix-templates"

Write-Host "Setting up FSLogix Group Policy..." -ForegroundColor Green

# Create temp folder if it doesn't exist
if (-not (Test-Path $tempFolder)) {
    New-Item -Path $tempFolder -ItemType Directory -Force | Out-Null
}

# Download FSLogix Policy Templates
Write-Host "Downloading FSLogix policy templates..." -ForegroundColor Cyan
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $fslogixTemplatesUrl -OutFile $templatesZipFile -UseBasicParsing
    Write-Host "Templates downloaded successfully." -ForegroundColor Green
} catch {
    Write-Host "Error downloading templates: $_" -ForegroundColor Red
    exit 1
}

# Extract templates
Write-Host "Extracting templates..." -ForegroundColor Cyan
try {
    Expand-Archive -Path $templatesZipFile -DestinationPath $policiesFolder -Force
    Write-Host "Templates extracted successfully." -ForegroundColor Green
} catch {
    Write-Host "Error extracting templates: $_" -ForegroundColor Red
    exit 1
}

# Copy ADMX/ADML files to the Policy Definitions folder
Write-Host "Copying policy templates to the Group Policy Central Store..." -ForegroundColor Cyan

# Determine the domain name
$domain = (Get-ADDomain).DNSRoot
$policyDefinitionsPath = "\\$domain\SYSVOL\$domain\Policies\PolicyDefinitions"

# Check if Central Store exists, create if not
if (-not (Test-Path $policyDefinitionsPath)) {
    Write-Host "Central Store doesn't exist. Creating..." -ForegroundColor Yellow
    New-Item -Path $policyDefinitionsPath -ItemType Directory -Force | Out-Null
    New-Item -Path "$policyDefinitionsPath\en-US" -ItemType Directory -Force | Out-Null
}

# Copy ADMX files to PolicyDefinitions
try {
    Copy-Item -Path "$policiesFolder\*.admx" -Destination $policyDefinitionsPath -Force
    
    # Create en-US folder if it doesn't exist
    if (-not (Test-Path "$policyDefinitionsPath\en-US")) {
        New-Item -Path "$policyDefinitionsPath\en-US" -ItemType Directory -Force | Out-Null
    }
    
    # Copy ADML files to PolicyDefinitions\en-US
    Copy-Item -Path "$policiesFolder\en-US\*.adml" -Destination "$policyDefinitionsPath\en-US" -Force
    Write-Host "Templates copied to Central Store successfully." -ForegroundColor Green
} catch {
    Write-Host "Error copying templates to Central Store: $_" -ForegroundColor Red
}

# Create a new GPO for FSLogix
Write-Host "Creating FSLogix GPO..." -ForegroundColor Cyan
try {
    $gpo = New-GPO -Name $gpoName -Comment "FSLogix Configuration Settings"
    
    # Configure common FSLogix settings
    # 1. Enable FSLogix Profile Containers
    Set-GPRegistryValue -Name $gpoName -Key "HKLM\SOFTWARE\FSLogix\Profiles" -ValueName "Enabled" -Value 1 -Type DWord
    
    # 2. Set VHD Location (example path - adjust as needed)
    Set-GPRegistryValue -Name $gpoName -Key "HKLM\SOFTWARE\FSLogix\Profiles" -ValueName "VHDLocations" -Value "\\server\FSLogixProfiles" -Type String
    
    # 3. Configure VHD file format
    Set-GPRegistryValue -Name $gpoName -Key "HKLM\SOFTWARE\FSLogix\Profiles" -ValueName "VolumeType" -Value "VHDX" -Type String
    
    # 4. Set size in MB for the profile container (default 30GB)
    Set-GPRegistryValue -Name $gpoName -Key "HKLM\SOFTWARE\FSLogix\Profiles" -ValueName "SizeInMBs" -Value 30720 -Type DWord
    
    # 5. Configure Profile Container directory name
    Set-GPRegistryValue -Name $gpoName -Key "HKLM\SOFTWARE\FSLogix\Profiles" -ValueName "FlipFlopProfileDirectoryName" -Value 1 -Type DWord
    
    # 6. Delete local profile when FSLogix Profile is available
    Set-GPRegistryValue -Name $gpoName -Key "HKLM\SOFTWARE\FSLogix\Profiles" -ValueName "DeleteLocalProfileWhenVHDShouldApply" -Value 1 -Type DWord
    
    Write-Host "FSLogix GPO '$gpoName' created successfully." -ForegroundColor Green
    
    # Optional: Link the GPO to an OU
    # $targetOU = "OU=Terminal Servers,DC=contoso,DC=com"
    # New-GPLink -Name $gpoName -Target $targetOU -LinkEnabled Yes
    
} catch {
    Write-Host "Error creating FSLogix GPO: $_" -ForegroundColor Red
}

# Clean up temp files
Write-Host "Cleaning up temporary files..." -ForegroundColor Cyan
Remove-Item -Path $tempFolder -Recurse -Force

Write-Host "FSLogix GPO setup completed." -ForegroundColor Green
Write-Host "Remember to link the GPO to the appropriate OU and customize settings as needed." -ForegroundColor Yellow