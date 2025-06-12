<#
.SYNOPSIS
    Joins Windows 11 VM to Entra ID
.DESCRIPTION
    This script joins a Windows 11 VM directly to Azure AD (Entra ID)
.NOTES
    Run this script with Administrator privileges
#>

param(
   [string]$TenantId = "your-tenant-id-here", # Replace with your actual tenant ID
    
    [string]$UserPrincipalName = "your.upn@beispiel.com", # Replace with your actual UPN
    
    [switch]$AutoEnrollMDM
)

# Check if running as Administrator
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Error "This script must be run as Administrator"
    exit 1
}

Write-Host "Starting Entra ID join for Windows 11..." -ForegroundColor Green

try {
    # Check if already joined to Azure AD
    $dsregStatus = dsregcmd /status
    if ($dsregStatus -match "AzureAdJoined\s*:\s*YES") {
        Write-Warning "Device is already joined to Azure AD"
        return
    }

    # Install required modules
    Write-Host "Installing required PowerShell modules..." -ForegroundColor Yellow
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
    Install-Module -Name AzureAD -Force -AllowClobber

    # Configure automatic MDM enrollment if requested
    if ($AutoEnrollMDM) {
        Write-Host "Configuring automatic MDM enrollment..." -ForegroundColor Yellow
        
        # Set registry keys for auto-enrollment
        $registryPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\MDM"
        if (!(Test-Path $registryPath)) {
            New-Item -Path $registryPath -Force
        }
        
        Set-ItemProperty -Path $registryPath -Name "AutoEnrollMDM" -Value 1 -Type DWord
        Set-ItemProperty -Path $registryPath -Name "UseAADCredentialType" -Value 1 -Type DWord
    }

    # Perform Azure AD join
    Write-Host "Joining device to Entra ID..." -ForegroundColor Yellow
    Write-Host "Tenant ID: $TenantId" -ForegroundColor Cyan
    
    # Use dsregcmd for joining
    $joinCommand = "dsregcmd /join /tenantid:$TenantId"
    Write-Host "Executing: $joinCommand" -ForegroundColor Gray
    
    $result = cmd /c $joinCommand 2>&1
    Write-Host $result
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Successfully initiated Azure AD join!" -ForegroundColor Green
        
        # Verify join status
        Write-Host "Verifying join status..." -ForegroundColor Yellow
        Start-Sleep -Seconds 10
        $status = dsregcmd /status
        Write-Host $status
        
        if ($status -match "AzureAdJoined\s*:\s*YES") {
            Write-Host "Device successfully joined to Azure AD!" -ForegroundColor Green
        } else {
            Write-Warning "Join may still be in progress. Check status later with: dsregcmd /status"
        }
        
    } else {
        Write-Error "Failed to join Azure AD. Exit code: $LASTEXITCODE"
        Write-Host "You may need to join manually through Settings > Accounts > Access work or school" -ForegroundColor Yellow
    }

    Write-Host "Post-join configuration..." -ForegroundColor Yellow
    
    # Enable Windows Hello for Business if available
    try {
        $whfbPath = "HKLM:\SOFTWARE\Policies\Microsoft\PassportForWork"
        if (!(Test-Path $whfbPath)) {
            New-Item -Path $whfbPath -Force
        }
        Set-ItemProperty -Path $whfbPath -Name "Enabled" -Value 1 -Type DWord
        Write-Host "Windows Hello for Business enabled" -ForegroundColor Green
    } catch {
        Write-Warning "Could not configure Windows Hello for Business: $($_.Exception.Message)"
    }

    Write-Host "Setup complete!" -ForegroundColor Green
    Write-Host "Recommended next steps:" -ForegroundColor Cyan
    Write-Host "1. Restart the computer" -ForegroundColor White
    Write-Host "2. Sign in with Azure AD credentials: $UserPrincipalName" -ForegroundColor White
    Write-Host "3. Verify MDM enrollment in Settings > Accounts > Access work or school" -ForegroundColor White

} catch {
    Write-Error "Error during Windows 11 Entra ID join: $($_.Exception.Message)"
    exit 1
}