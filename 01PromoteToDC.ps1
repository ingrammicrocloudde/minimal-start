# PowerShell script to promote a Windows Server to a Domain Controller (New Forest)
# Make sure to run this script as Administrator

param(
    [string]$DomainName = "example.com", # Name der neuen Domäne
    [string]$SafeModeAdministratorPassword = "YourSecurePassword123!" # Passwort für den Wiederherstellungsmodus
)

Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools
$SecurePassword = ConvertTo-SecureString $SafeModeAdministratorPassword -AsPlainText -Force
Install-ADDSForest -DomainName $DomainName -SafeModeAdministratorPassword $SecurePassword -Force
Restart-Computer -Force
