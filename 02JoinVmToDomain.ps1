[CmdletBinding()]
param(
    [string]$DomainName = "azureessentials.de",
    
    [string]$DomainAdminUsername = "username",
    
    [string]$DomainAdminPassword = "YourSecurePassword123!",
    
    [string]$DCIPAddress = "10.0.0.4",
    
    [Parameter(Mandatory=$false)]
    [string]$OUPath
)

# Ensure running as administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    throw "This script must be run as Administrator"
}

Write-Host "Starting domain join validation for domain: $DomainName"
Write-Host "Using username: $DomainAdminUsername"

# Set DNS to DC IP if provided
if ($DCIPAddress) {
    Write-Host "Setting DNS to Domain Controller IP: $DCIPAddress"
    try {
        $adapter = Get-NetAdapter | Where-Object {$_.Status -eq "Up"} | Select-Object -First 1
        if ($adapter) {
            Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses $DCIPAddress
            Write-Host "DNS set successfully"
            Start-Sleep -Seconds 3
        }
    } catch {
        Write-Warning "Failed to set DNS: $_"
    }
}

# Test domain credentials and availability
Write-Host "Validating domain credentials and availability..."
try {
    # Method 1: Try LDAP connection to validate credentials
    Write-Host "Testing LDAP connection to domain..."
    Add-Type -AssemblyName System.DirectoryServices
    $ldapPath = "LDAP://$DomainName"
    $directoryEntry = New-Object System.DirectoryServices.DirectoryEntry($ldapPath, "$DomainName\$DomainAdminUsername", $DomainAdminPassword)
    
    # Try to read a property to validate the connection
    $domainDN = $directoryEntry.distinguishedName
    if ([string]::IsNullOrEmpty($domainDN)) {
        throw "LDAP connection failed - could not retrieve domain distinguished name"
    }
    Write-Host "LDAP connection successful. Domain DN: $domainDN"
    $directoryEntry.Dispose()
    
    # Method 2: Alternative credential validation using DirectoryServices.AccountManagement
    Write-Host "Validating credentials using AccountManagement..."
    Add-Type -AssemblyName System.DirectoryServices.AccountManagement
    $contextType = [System.DirectoryServices.AccountManagement.ContextType]::Domain
    
    try {
        if ($DCIPAddress) {
            $principalContext = New-Object System.DirectoryServices.AccountManagement.PrincipalContext($contextType, $DomainName, $DCIPAddress)
        } else {
            $principalContext = New-Object System.DirectoryServices.AccountManagement.PrincipalContext($contextType, $DomainName)
        }
        $isValidCredential = $principalContext.ValidateCredentials($DomainAdminUsername, $DomainAdminPassword)
        $principalContext.Dispose()
        
        if (-not $isValidCredential) {
            throw "Invalid domain credentials for user '$DomainAdminUsername' in domain '$DomainName'"
        }
        Write-Host "Domain credentials validated successfully using AccountManagement."
    } catch {
        # If AccountManagement fails, try without specifying server
        Write-Host "Retrying credential validation without specific server..."
        try {
            $principalContext2 = New-Object System.DirectoryServices.AccountManagement.PrincipalContext($contextType, $DomainName)
            $isValidCredential2 = $principalContext2.ValidateCredentials($DomainAdminUsername, $DomainAdminPassword)
            $principalContext2.Dispose()
            
            if (-not $isValidCredential2) {
                throw "Invalid domain credentials for user '$DomainAdminUsername' in domain '$DomainName'"
            }
            Write-Host "Domain credentials validated successfully."
        } catch {
            Write-Warning "AccountManagement validation failed: $_"
        }
    }
    
    # Method 3: Test domain join permissions by checking if user exists and has necessary privileges
    Write-Host "Verifying domain join permissions..."
    try {
        $domainUserPath = "LDAP://$DomainName"
        $domainEntry = New-Object System.DirectoryServices.DirectoryEntry($domainUserPath, "$DomainName\$DomainAdminUsername", $DomainAdminPassword)
        $searcher = New-Object System.DirectoryServices.DirectorySearcher($domainEntry)
        $searcher.Filter = "(&(objectClass=user)(sAMAccountName=$DomainAdminUsername))"
        $userResult = $searcher.FindOne()
        
        if ($userResult) {
            $userEntry = $userResult.GetDirectoryEntry()
            $memberOf = $userEntry.Properties["memberOf"]
            Write-Host "User found in domain. Member of $($memberOf.Count) groups."
            
            # Check if user is in Domain Admins or has necessary permissions
            $isDomainAdmin = $false
            foreach ($group in $memberOf) {
                if ($group -like "*Domain Admins*" -or $group -like "*Administrators*") {
                    $isDomainAdmin = $true
                    break
                }
            }
            
            if ($isDomainAdmin) {
                Write-Host "User has domain administrative privileges."
            } else {
                Write-Warning "User may not have domain join privileges. Proceeding anyway..."
            }
            
            $userEntry.Dispose()
        } else {
            Write-Warning "Could not find user in domain directory."
        }
        
        $domainEntry.Dispose()
        $searcher.Dispose()
    } catch {
        Write-Warning "Could not verify user permissions: $_"
    }
    
    Write-Host "Domain credential validations completed."
    
    # Validate OU Path if provided
    if ($OUPath) {
        Write-Host "Validating OU Path: $OUPath"
        try {
            $ouEntry = New-Object System.DirectoryServices.DirectoryEntry("LDAP://$OUPath", "$DomainName\$DomainAdminUsername", $DomainAdminPassword)
            $ouDN = $ouEntry.distinguishedName
            if ([string]::IsNullOrEmpty($ouDN)) {
                throw "OU Path not found"
            }
            Write-Host "OU Path validated successfully."
            $ouEntry.Dispose()
        } catch {
            throw "Invalid OU Path '$OUPath': $_"
        }
    }
    
    # Create credential object for domain join
    $SecurePassword = ConvertTo-SecureString $DomainAdminPassword -AsPlainText -Force
    $Credential = New-Object System.Management.Automation.PSCredential ("$DomainName\$DomainAdminUsername", $SecurePassword)
    
    # Perform domain join
    Write-Host "All validations passed. Joining domain $DomainName..."
    if ($OUPath) {
        Add-Computer -DomainName $DomainName -Credential $Credential -OUPath $OUPath -Force -Restart -Verbose
    } else {
        Add-Computer -DomainName $DomainName -Credential $Credential -Force -Restart -Verbose
    }
    
    Write-Host "Domain join initiated successfully. Computer will restart to complete the process."
    
} catch {
    $errorMessage = $_.Exception.Message
    Write-Error "Domain join failed: $errorMessage"
    
    # Provide troubleshooting information
    Write-Host "`nTroubleshooting Information:"
    Write-Host "1. Domain Name: $DomainName"
    Write-Host "2. Username: $DomainAdminUsername"
    Write-Host "3. DC IP Address: $(if($DCIPAddress){$DCIPAddress}else{'Not specified'})"
    Write-Host "4. OU Path: $(if($OUPath){$OUPath}else{'Default Computers container'})"
    Write-Host "`nCommon issues:"
    Write-Host "- Verify network connectivity to domain controller"
    Write-Host "- Check DNS settings"
    Write-Host "- Verify username/password credentials"
    Write-Host "- Ensure user has domain join permissions"
    Write-Host "- Check firewall settings"
    
    exit 1
}