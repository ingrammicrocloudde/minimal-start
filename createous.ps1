# PowerShell script to create OUs and GPO for hybrid join with MDM sync

# Import the Active Directory module
Import-Module ActiveDirectory

# Define variables
$domainDN = (Get-ADDomain).DistinguishedName
$usersOUName = "Users.OU"
$computersOUName = "Computers.OU"
$gpoName = "HybridJoin"

# Create OUs
Write-Host "Creating OUs..." -ForegroundColor Green

try {
    # Create Users OU
    New-ADOrganizationalUnit -Name $usersOUName -Path $domainDN -ProtectedFromAccidentalDeletion $true
    Write-Host "Users OU created successfully" -ForegroundColor Green
} catch {
    Write-Host "Error creating Users OU: $_" -ForegroundColor Red
}

try {
    # Create Computers OU
    New-ADOrganizationalUnit -Name $computersOUName -Path $domainDN -ProtectedFromAccidentalDeletion $true
    Write-Host "Computers OU created successfully" -ForegroundColor Green
} catch {
    Write-Host "Error creating Computers OU: $_" -ForegroundColor Red
}

# Create GPO for Hybrid Join and MDM sync
Write-Host "Creating Hybrid Join GPO with MDM sync settings..." -ForegroundColor Green

try {
    # Create a new GPO
    $gpo = New-GPO -Name $gpoName -Comment "Enables MDM sync for hybrid joined devices"

    # Configure the MDM sync settings via Group Policy registry settings
    # The registry key for MDM enrollment is:
    # HKLM\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\MDM
    
    # Enable automatic MDM enrollment using AAD credentials
    $registrySettings = @{
        "AutoEnrollMDM" = "1";  # 1 = Enabled
        "UseAADCredentialForAutoenrollment" = "1"  # Use AAD credentials
    }

    foreach ($setting in $registrySettings.GetEnumerator()) {
        $key = "HKLM\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\MDM"
        $valueName = $setting.Key
        $valueData = $setting.Value
        $valueType = "DWORD"
        
        Set-GPRegistryValue -Name $gpoName -Key $key -ValueName $valueName -Value $valueData -Type $valueType
    }

    # Link GPO to the Computers OU
    $computersOUPath = "OU=$computersOUName,$domainDN"
    New-GPLink -Name $gpoName -Target $computersOUPath -LinkEnabled Yes
    
    Write-Host "GPO created and linked successfully" -ForegroundColor Green
} catch {
    Write-Host "Error creating or configuring GPO: $_" -ForegroundColor Red
}

Write-Host "Script execution completed" -ForegroundColor Green