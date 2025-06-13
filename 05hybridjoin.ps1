<#
.SYNOPSIS
    Script to join a Windows 11 VM to Entra ID (Azure AD) as a hybrid join.

.DESCRIPTION
    This script performs the necessary steps to join a Windows 11 VM to Entra ID (Azure AD) as a hybrid join.
    It configures device registration settings, validates domain join prerequisites, and initiates the hybrid join process.

.PARAMETER DomainName
    The name of the on-premises Active Directory domain

.PARAMETER DomainAdminUsername
    The username of a domain admin account with permission to join devices to the domain

.PARAMETER DomainAdminPassword
    The password of the domain admin account

.PARAMETER DCIPAddress
    The IP address of a domain controller (optional)

.PARAMETER OUPath
    The Organizational Unit path where the computer account should be created (optional)
#>

[CmdletBinding()]
param(
    [string]$DomainName = "yourdomain.com",
    
    [string]$DomainAdminUsername = "DomainAdmin",
    
    [string]$DomainAdminPassword = "P@ssw0rd",
    
    [string]$DCIPAddress = "10.0.0.4",
    
    [Parameter(Mandatory=$false)]
    [string]$OUPath
)

# Ensure running as administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    throw "This script must be run as Administrator"
}

Write-Host "Starting hybrid join process for Entra ID..." -ForegroundColor Green

# Step 1: Set DNS to DC IP if provided (important for domain discovery)
if ($DCIPAddress) {
    Write-Host "Setting DNS to Domain Controller IP: $DCIPAddress" -ForegroundColor Cyan
    try {
        $adapter = Get-NetAdapter | Where-Object {$_.Status -eq "Up"} | Select-Object -First 1
        if ($adapter) {
            Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses $DCIPAddress
            Write-Host "DNS set successfully" -ForegroundColor Green
            Start-Sleep -Seconds 3
        }
    } catch {
        Write-Warning "Failed to set DNS: $_"
    }
}

# Step 2: Test domain connection and credentials
Write-Host "Validating domain credentials and availability..." -ForegroundColor Cyan
try {
    # Try LDAP connection to validate credentials
    Write-Host "Testing LDAP connection to domain..."
    Add-Type -AssemblyName System.DirectoryServices
    $ldapPath = "LDAP://$DomainName"
    $directoryEntry = New-Object System.DirectoryServices.DirectoryEntry($ldapPath, "$DomainName\$DomainAdminUsername", $DomainAdminPassword)
    
    # Try to read a property to validate the connection
    $domainDN = $directoryEntry.distinguishedName
    if ([string]::IsNullOrEmpty($domainDN)) {
        throw "LDAP connection failed - could not retrieve domain distinguished name"
    }
    Write-Host "LDAP connection successful. Domain DN: $domainDN" -ForegroundColor Green
    $directoryEntry.Dispose()
    
    # Create credential object for domain join
    $SecurePassword = ConvertTo-SecureString $DomainAdminPassword -AsPlainText -Force
    $Credential = New-Object System.Management.Automation.PSCredential ("$DomainName\$DomainAdminUsername", $SecurePassword)
    
    # Step 3: First join the computer to the on-premises domain
    Write-Host "Joining on-premises domain $DomainName..." -ForegroundColor Cyan
    if ($OUPath) {
        Add-Computer -DomainName $DomainName -Credential $Credential -OUPath $OUPath -Force
    } else {
        Add-Computer -DomainName $DomainName -Credential $Credential -Force
    }
    
    Write-Host "On-premises domain join completed successfully." -ForegroundColor Green
    
    # Step 4: Configure Hybrid Azure AD Join registry settings
    Write-Host "Configuring registry settings for Hybrid Azure AD Join..." -ForegroundColor Cyan

    # Enable automatic device registration
    $regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WorkplaceJoin"
    if (-not (Test-Path $regPath)) {
        New-Item -Path $regPath -Force | Out-Null
    }
    
    # Configure automatic device registration
    New-ItemProperty -Path $regPath -Name "autoWorkplaceJoin" -Value 1 -PropertyType DWORD -Force | Out-Null
    Write-Host "Automatic device registration enabled." -ForegroundColor Green

    # Step 5: Force device registration with dsregcmd
    Write-Host "Forcing device registration with Entra ID..." -ForegroundColor Cyan
    $dsregResult = dsregcmd /join
    Write-Host $dsregResult

    # Check registration status
    $status = dsregcmd /status
    Write-Host "`nDevice registration status:" -ForegroundColor Cyan
    
    # Extract and display relevant Azure AD Join information from status
    $azureAdJoinInfo = $status | Select-String -Pattern "AzureAdJoined|DomainJoined|WorkplaceJoined|TenantId|TenantName" -Context 0,1
    $azureAdJoinInfo | ForEach-Object { Write-Host $_ -ForegroundColor Yellow }
    
    # Step 6: Verify hybrid join status
    $hybridJoinStatus = $status | Select-String -Pattern "AzureAdJoined" -Context 0,1
    if ($hybridJoinStatus -match "YES") {
        Write-Host "`nHybrid Azure AD Join completed successfully!" -ForegroundColor Green
        Write-Host "A system restart is required to complete the process." -ForegroundColor Yellow
        
        # Ask for restart
        $restart = Read-Host "Do you want to restart the computer now to complete the process? (Y/N)"
        if ($restart -eq "Y" -or $restart -eq "y") {
            Restart-Computer -Force
        } else {
            Write-Host "Please restart the computer manually to complete the Hybrid Azure AD Join process." -ForegroundColor Yellow
        }
    } else {
        Write-Warning "Hybrid Azure AD Join may not have completed successfully. Please check status with 'dsregcmd /status'"
    }
    
} catch {
    $errorMessage = $_.Exception.Message
    Write-Error "Hybrid Azure AD Join failed: $errorMessage"
    
    # Provide troubleshooting information
    Write-Host "`nTroubleshooting Information:" -ForegroundColor Cyan
    Write-Host "1. Domain Name: $DomainName"
    Write-Host "2. Username: $DomainAdminUsername"
    Write-Host "3. DC IP Address: $(if($DCIPAddress){$DCIPAddress}else{'Not specified'})"
    Write-Host "4. OU Path: $(if($OUPath){$OUPath}else{'Default Computers container'})"
    
    Write-Host "`nCommon issues:" -ForegroundColor Cyan
    Write-Host "- Verify network connectivity to domain controller"
    Write-Host "- Check DNS settings"
    Write-Host "- Verify username/password credentials"
    Write-Host "- Ensure Azure AD Connect is configured for Hybrid Azure AD Join"
    Write-Host "- Check if Service Connection Point (SCP) is properly configured in AD"
    Write-Host "- Ensure user has domain join permissions"
    Write-Host "- Check firewall settings"
    Write-Host "- Verify network access to Azure AD endpoints"
    
    # Additional diagnostic info
    Write-Host "`nRunning additional diagnostics..." -ForegroundColor Cyan
    Write-Host "`nCurrent DNS settings:"
    Get-DnsClientServerAddress | Where-Object {$_.InterfaceAlias -eq $adapter.Name} | Format-Table -AutoSize
    
    Write-Host "`nNetwork connectivity test to domain controller:"
    if ($DCIPAddress) {
        Test-Connection -ComputerName $DCIPAddress -Count 2 -ErrorAction SilentlyContinue
    } else {
        Write-Host "No DC IP specified for testing."
    }
    
    Write-Host "`nDS Client Status:" 
    dsregcmd /status
    
    exit 1
}