# Check if the device is domain joined
if ((Get-WmiObject Win32_ComputerSystem).PartOfDomain -ne $true) {
    Write-Host "The device is not domain-joined. Hybrid Azure AD Join requires the device to be joined to Active Directory."
    exit 1
}

# Force device registration (Hybrid Azure AD Join)
Write-Host "Forcing device registration (Hybrid Azure AD Join)..."
dsregcmd /join

# Show the status
Write-Host "Device registration status:"
dsregcmd /status