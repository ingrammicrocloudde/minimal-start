<#
.SYNOPSIS
    Joins Domain Controller to Entra ID for hybrid scenario
.DESCRIPTION
    This script configures the Domain Controller for Entra ID Connect and hybrid join
.NOTES
    Run this script with Administrator privileges
#>

param(
    [string]$TenantId = "your-tenant-id-here", # Replace with your actual tenant ID
    
    [string]$DomainName = "yourdomain.com", # Replace with your actual domain name
        
    [Parameter(Mandatory=$false)]
    [string]$EntraConnectPath = "$env:TEMP\AzureADConnect.msi"
)

# Check if running as Administrator
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Error "This script must be run as Administrator"
    exit 1
}

Write-Host "Starting Entra ID integration for Domain Controller..." -ForegroundColor Green

try {
    # Install required PowerShell modules
    Write-Host "Installing required PowerShell modules..." -ForegroundColor Yellow
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
    Install-Module -Name MSOnline -Force -AllowClobber
    Install-Module -Name AzureAD -Force -AllowClobber

    # Download Azure AD Connect
    Write-Host "Downloading Azure AD Connect..." -ForegroundColor Yellow
    $downloadUrl = "https://download.microsoft.com/download/B/0/0/B00291D0-5A83-4DE7-86F5-980BC00DE05A/AzureADConnect.msi"
    Invoke-WebRequest -Uri $downloadUrl -OutFile $EntraConnectPath

    # Install Azure AD Connect
    Write-Host "Installing Azure AD Connect..." -ForegroundColor Yellow
    Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$EntraConnectPath`" /quiet /norestart" -Wait

    # Configure firewall rules for Azure AD Connect
    Write-Host "Configuring firewall rules..." -ForegroundColor Yellow
    New-NetFirewallRule -DisplayName "Azure AD Connect - HTTPS Outbound" -Direction Outbound -Protocol TCP -LocalPort 443 -Action Allow
    New-NetFirewallRule -DisplayName "Azure AD Connect - HTTP Outbound" -Direction Outbound -Protocol TCP -LocalPort 80 -Action Allow

    # Enable required services
    Write-Host "Enabling required services..." -ForegroundColor Yellow
    Set-Service -Name "Microsoft Azure AD Sync" -StartupType Automatic
    Start-Service -Name "Microsoft Azure AD Sync" -ErrorAction SilentlyContinue

    Write-Host "Domain Controller preparation complete!" -ForegroundColor Green
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "1. Run Azure AD Connect configuration wizard" -ForegroundColor White
    Write-Host "2. Use tenant ID: $TenantId" -ForegroundColor White
    Write-Host "3. Configure password hash synchronization or federation" -ForegroundColor White

} catch {
    Write-Error "Error during DC Entra ID setup: $($_.Exception.Message)"
    exit 1
}