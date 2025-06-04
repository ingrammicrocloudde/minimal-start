# PowerShell script to promote a Windows Server to a Domain Controller (New Forest)
# Make sure to run this script as Administrator

# Variables - change these as needed
$DomainName = "corp.example.com"          # Set your desired FQDN
$SafeModeAdminPassword = (ConvertTo-SecureString "P@ssw0rd!" -AsPlainText -Force) # Set a strong password

# Install Active Directory Domain Services role
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools

# Promote the server to a Domain Controller
Install-ADDSForest `
    -DomainName $DomainName `
    -SafeModeAdministratorPassword $SafeModeAdminPassword `
    -DomainNetbiosName "CORP" `
    -InstallDNS `
    -Force

# Optional: Reboot the server after promotion
Restart-Computer -Force
