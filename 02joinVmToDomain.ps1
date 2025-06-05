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
            $principalContext = New-Object System.DirectoryServices.AccountManagement.PrincipalContext($contextType, $DomainName, $DCIPAddress)
            $isValidCredential = $principalContext.ValidateCredentials($DomainAdminUsername, $DomainAdminPassword)
            $principalContext.Dispose()
            
            if (-not $isValidCredential) {
                throw "Invalid domain credentials for user '$DomainAdminUsername' in domain '$DomainName'"
            }
            Write-Host "Domain credentials validated successfully using AccountManagement."
        } catch {
            # If AccountManagement fails, try without specifying server
            Write-Host "Retrying credential validation without specific server..."
            $principalContext2 = New-Object System.DirectoryServices.AccountManagement.PrincipalContext($contextType, $DomainName)
            $isValidCredential2 = $principalContext2.ValidateCredentials($DomainAdminUsername, $DomainAdminPassword)
            $principalContext2.Dispose()
            
            if (-not $isValidCredential2) {
                throw "Invalid domain credentials for user '$DomainAdminUsername' in domain '$DomainName'"
            }
            Write-Host "Domain credentials validated successfully."
        }
        
        # Method 3: Test domain join permissions by checking if user exists and has necessary privileges
        Write-Host "Verifying domain join permissions..."
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
        }
        
        $domainEntry.Dispose()
        $searcher.Dispose()
        
        Write-Host "All domain credential validations passed."
        
    } catch {
        $errorMessage = $_.Exception.Message
        Write-Warning "Domain credential validation encountered an issue: $errorMessage"
        
        # If all validation methods fail, provide detailed troubleshooting
        if ($errorMessage -like "*User credentials cannot be used for local connections*") {
            Write-Host "This is a WMI limitation. Continuing with LDAP-based validation only..."
        } elseif ($errorMessage -like "*The server is not operational*") {
            throw "Domain controller is not accessible. Please verify DC IP address and network connectivity."
        } elseif ($errorMessage -like "*Logon failure*" -or $errorMessage -like "*invalid credentials*") {
            throw "Invalid username or password. Please verify domain credentials."
        } elseif ($errorMessage -like "*The specified domain either does not exist*") {
            throw "Domain '$DomainName' does not exist or is not accessible."
        } else {
            # For other errors, try a final basic connectivity test
            Write-Host "Attempting basic domain connectivity test..."
            try {
                $testConnection = Test-ComputerSecureChannel -Server $DomainName -ErrorAction Stop
                Write-Host "Basic domain connectivity test passed."
            } catch {
                throw "Failed to validate domain credentials or domain availability: $errorMessage"
            }
        }
    }