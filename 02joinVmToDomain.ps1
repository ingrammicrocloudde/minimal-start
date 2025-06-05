[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$DomainName,

    [Parameter(Mandatory=$true)]
    [string]$DomainAdminUsername,

    [Parameter(Mandatory=$true)]
    [string]$DomainAdminPassword,

    [Parameter(Mandatory=$false)]
    [string]$DCIPAddress,

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
        # For Azure VMs: Keep Azure DNS as secondary
        Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses ($DCIPAddress, "168.63.129.16")
    }

    # Test domain connectivity
    Write-Host "Testing domain connectivity..."
    if (-not (Test-Connection -ComputerName $DomainName -Count 1 -Quiet)) {
        throw "Cannot reach domain controller. Please check network connectivity and DNS settings."
    }

    # Create credential object
    $SecurePassword = ConvertTo-SecureString $DomainAdminPassword -AsPlainText -Force
    $Credential = New-Object System.Management.Automation.PSCredential ("$DomainName\$DomainAdminUsername", $SecurePassword)

    ## Prepare domain join parameters
    #$joinParams = @{
    #    DomainName = $DomainName
    #    Credential = $Credential
    #    Force = $true
    #    Restart = $true
    #}

    ## Add OU path if specified
    #if ($OUPath) {
    #    $joinParams.OUPath = $OUPath
    #}

    # Join domain
    Write-Host "Joining domain $DomainName..."
    if ($OUPath) {
        Add-Computer -DomainName $DomainName -Credential $Credential -OUPath $OUPath -Force -Restart -Verbose
    }
else {
        Add-Computer -DomainName $DomainName -Credential $Credential -Force -Restart -Verbose
    }

    Write-Host "Domain join initiated successfully. Computer will restart to complete the process."

} catch {
    Write-Error "An error occurred while joining the domain: $_"
    exit 1
}
