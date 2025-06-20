[CmdletBinding()]
param(
    [string]$DomainName = "azureessentials.de",
    
    [string]$SafeModeAdministratorPassword = "YourSecurePassword123!",

    [Parameter(Mandatory=$false)]
    [string]$NetBiosName = ($DomainName -split '\.')[0].ToUpper()
)

# Ensure running as administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    throw "This script must be run as Administrator"
}

try {
    # Configure PowerShell to use TLS 1.2
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    # Disable IE Enhanced Security Configuration
    $AdminKey = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}"
    $UserKey = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A8-37EF-4b3f-8CFC-4F3A74704073}"
    Set-ItemProperty -Path $AdminKey -Name "IsInstalled" -Value 0 -Force
    Set-ItemProperty -Path $UserKey -Name "IsInstalled" -Value 0 -Force

 # Set DNS configuration appropriate for Azure VM
    $adapter = Get-NetAdapter | Where-Object {$_.Status -eq "Up"}
    # Set primary DNS to loopback and secondary to Azure DNS
    Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses ("127.0.0.1","168.63.129.16")
        # Install required Windows Features
    Write-Host "Installing AD Domain Services and management tools..."
    $feature = Install-WindowsFeature -Name AD-Domain-Services, DNS -IncludeManagementTools
    if (-not $feature.Success) {
        throw "Failed to install required Windows features"
    }

    # Convert password to secure string
    $SecurePassword = ConvertTo-SecureString $SafeModeAdministratorPassword -AsPlainText -Force

    # Prepare forest configuration
    $forestParams = @{
        DomainName = $DomainName
        DomainNetbiosName = $NetBiosName
        SafeModeAdministratorPassword = $SecurePassword
        InstallDns = $true
        CreateDnsDelegation = $false
        DatabasePath = "C:\Windows\NTDS"
        LogPath = "C:\Windows\NTDS"
        SysvolPath = "C:\Windows\SYSVOL"
        #ForceReboot = $true
        NoRebootOnCompletion = $false
        Force = $true
    }

    # Test domain controller prerequisites
    Write-Host "Testing DC prerequisites..."
    $test = Test-ADDSForestInstallation @forestParams
    if ($test.Status -eq "Error") {
        throw "Prerequisites check failed: $($test.Message)"
    }

    # Install new forest and domain controller
    Write-Host "Installing new forest and promoting to Domain Controller..."
    Install-ADDSForest @forestParams

    # Create scheduled task to complete post-reboot configuration
    # Modify the scheduled task to maintain Azure DNS as secondary
    $action = New-ScheduledTaskAction -Execute 'Powershell.exe' -Argument '-NoProfile -WindowStyle Hidden -Command "Set-DnsClientServerAddress -InterfaceIndex (Get-NetAdapter | Where-Object {$_.Status -eq \"Up\"}).ifIndex -ServerAddresses (\"127.0.0.1\", \"168.63.129.16\"); Unregister-ScheduledTask -TaskName \"ConfigureDNS\" -Confirm:$false"'
    $trigger = New-ScheduledTaskTrigger -AtStartup
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    Register-ScheduledTask -TaskName "ConfigureDNS" -Action $action -Trigger $trigger -Principal $principal -Description "Configure DNS after DC promotion"

} catch {
    Write-Error "An error occurred during promotion: $_"
    exit 1
}

$postRebootScript = @"
# Configure DNS
Set-DnsClientServerAddress -InterfaceIndex (Get-NetAdapter | Where-Object {`$_.Status -eq "Up"}).ifIndex -ServerAddresses ("127.0.0.1", "168.63.129.16")

# Configure SCP for Azure AD Hybrid Join
Import-Module ActiveDirectory
try {
    `$domainDN = (Get-ADDomain).DistinguishedName
    `$configDN = "CN=Configuration,`$domainDN"
    `$servicesDN = "CN=Services,`$configDN"
    `$scpDN = "CN=62a0ff2e-97b9-4513-943f-0d221bd30080,`$servicesDN"
    
    # Check if SCP already exists
    if (-not (Get-ADObject -Filter {distinguishedName -eq `$scpDN} -ErrorAction SilentlyContinue)) {
        # Create SCP object
        New-ADObject -Name "62a0ff2e-97b9-4513-943f-0d221bd30080" -Type "serviceConnectionPoint" -Path `$servicesDN -OtherAttributes @{
            "keywords" = "azureADName:yourtenant.onmicrosoft.com"
            "serviceClassName" = "ms-DS-Device-Registration-Service"
        }
        Write-EventLog -LogName Application -Source "Application" -EventId 1000 -Message "SCP configured successfully for Azure AD Hybrid Join"
    }
} catch {
    Write-EventLog -LogName Application -Source "Application" -EventId 1001 -Message "Failed to configure SCP: `$_"
}

# Clean up scheduled task
Unregister-ScheduledTask -TaskName "ConfigureDNSAndSCP" -Confirm:`$false
"@

    $scriptPath = "C:\Windows\Temp\PostDCConfig.ps1"
    $postRebootScript | Out-File -FilePath $scriptPath -Encoding UTF8

    $action = New-ScheduledTaskAction -Execute 'Powershell.exe' -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`""
    $trigger = New-ScheduledTaskTrigger -AtStartup
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    Register-ScheduledTask -TaskName "ConfigureDNSAndSCP" -Action $action -Trigger $trigger -Principal $principal -Description "Configure DNS and SCP after DC promotion"

 catch {
    Write-Error "An error occurred during promotion: $_"
    exit 1
}