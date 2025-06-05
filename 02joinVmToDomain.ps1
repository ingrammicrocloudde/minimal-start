[CmdletBinding()]
param(
    [string]$DomainName = "contoso.com",

    [string]$DomainAdminUsername = "Administrator",

    [string]$DomainAdminPassword = "P@ssw0rd",

    [string]$DCIPAddress= "10.0.0.4",

    [Parameter(Mandatory=$false)]
    [string]$OUPath
)

# Ensure running as administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    throw "This script must be run as Administrator"
}

try {
    Write-Host "Starting domain join process..."

    # If DC IP is provided, set DNS to DC IP first
    if ($DCIPAddress) {
        Write-Host "Setting DNS to Domain Controller IP..."
        $adapter = Get-NetAdapter | Where-Object {$_.Status -eq "Up"}
        if (-not $adapter) {
            throw "No active network adapter found."
        }
        Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses ($DCIPAddress)
        Start-Sleep -Seconds 5  # Allow DNS changes to propagate
    }

    # Test domain controller connectivity
    Write-Host "Testing domain controller connectivity..."
    if ($DCIPAddress) {
        if (-not (Test-Connection -ComputerName $DCIPAddress -Count 2 -Quiet)) {
            throw "Cannot reach domain controller at IP $DCIPAddress. Please check network connectivity."
        }
    }

    # Test domain name resolution
    Write-Host "Testing domain name resolution..."
    try {
        $domainIP = Resolve-DnsName -Name $DomainName -Type A -ErrorAction Stop
        Write-Host "Domain $DomainName resolved to: $($domainIP.IPAddress -join ', ')"
    } catch {
        throw "Cannot resolve domain name $DomainName. DNS resolution failed: $_"
    }

    # Test domain connectivity
    Write-Host "Testing domain connectivity..."
    if (-not (Test-Connection -ComputerName $DomainName -Count 2 -Quiet)) {
        throw "Cannot reach domain $DomainName. Please check network connectivity and DNS settings."
    }

    # Create credential object
    $SecurePassword = ConvertTo-SecureString $DomainAdminPassword -AsPlainText -Force
    $Credential = New-Object System.Management.Automation.PSCredential ("$DomainName\$DomainAdminUsername", $SecurePassword)

    # Test domain credentials and availability
    Write-Host "Validating domain credentials and availability..."
    try {
        # Try to get domain information using the provided credentials
        $domain = Get-WmiObject -Class Win32_NTDomain -Filter "DomainName='$DomainName'" -Credential $Credential -ErrorAction Stop
        if (-not $domain) {
            # Alternative method using DirectoryServices
            Add-Type -AssemblyName System.DirectoryServices.AccountManagement
            $contextType = [System.DirectoryServices.AccountManagement.ContextType]::Domain
            $principalContext = New-Object System.DirectoryServices.AccountManagement.PrincipalContext($contextType, $DomainName)
            
            $isValidCredential = $principalContext.ValidateCredentials($DomainAdminUsername, $DomainAdminPassword)
            $principalContext.Dispose()
            
            if (-not $isValidCredential) {
                throw "Invalid domain credentials for user '$DomainAdminUsername' in domain '$DomainName'"
            }
        }
        Write-Host "Domain credentials validated successfully."
    } catch {
        throw "Failed to validate domain credentials or domain availability: $_"
    }

    # Validate OU Path if provided
    if ($OUPath) {
        Write-Host "Validating OU Path..."
        try {
            Add-Type -AssemblyName System.DirectoryServices
            $domainPath = "LDAP://$DomainName"
            $directoryEntry = New-Object System.DirectoryServices.DirectoryEntry($domainPath, "$DomainName\$DomainAdminUsername", $DomainAdminPassword)
            $searcher = New-Object System.DirectoryServices.DirectorySearcher($directoryEntry)
            $searcher.Filter = "(distinguishedName=$OUPath)"
            $result = $searcher.FindOne()
            
            if (-not $result) {
                throw "OU Path '$OUPath' not found in domain '$DomainName'"
            }
            Write-Host "OU Path validated successfully."
            
            $directoryEntry.Dispose()
            $searcher.Dispose()
        } catch {
            throw "Failed to validate OU Path '$OUPath': $_"
        }
    }

    # Final connectivity test before joining
    Write-Host "Performing final connectivity test..."
    Start-Sleep -Seconds 2
    if (-not (Test-Connection -ComputerName $DomainName -Count 1 -Quiet)) {
        throw "Final connectivity test failed. Cannot proceed with domain join."
    }

    # Join domain
    Write-Host "All validations passed. Joining domain $DomainName..."
    if ($OUPath) {
        Add-Computer -DomainName $DomainName -Credential $Credential -OUPath $OUPath -Force -Restart -Verbose
    } else {
        Add-Computer -DomainName $DomainName -Credential $Credential -Force -Restart -Verbose
    }

    Write-Host "Domain join initiated successfully. Computer will restart to complete the process."

} catch {
    Write-Error "An error occurred while joining the domain: $_"
    Write-Host "Troubleshooting tips:"
    Write-Host "1. Verify the domain name is correct: $DomainName"
    Write-Host "2. Verify the username is correct: $DomainAdminUsername"
    Write-Host "3. Verify the password is correct"
    Write-Host "4. Ensure the DC IP address is reachable: $DCIPAddress"
    Write-Host "5. Check if the account has domain join permissions"
    Write-Host "6. Verify the OU path (if specified): $OUPath"
    exit 1
}