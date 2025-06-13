<#
.SYNOPSIS
    Script to join a Windows 11 VM to Entra ID (Azure AD).

.DESCRIPTION
    This script performs the necessary steps to join a Windows 11 VM to Entra ID (Azure AD).
    It configures device registration settings and initiates the join process.
#>

[CmdletBinding()]
param()

# Ensure running as administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    throw "This script must be run as Administrator"
}

Write-Host "Starting Entra ID join process..." -ForegroundColor Green

try {
    # Configure Entra ID Join registry settings
    Write-Host "Configuring registry settings for Entra ID Join..." -ForegroundColor Cyan

    # Create registry path for workplace join if it doesn't exist
    $regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WorkplaceJoin"
    if (-not (Test-Path $regPath)) {
        New-Item -Path $regPath -Force | Out-Null
    }
    
    # Configure automatic device registration
    New-ItemProperty -Path $regPath -Name "autoWorkplaceJoin" -Value 1 -PropertyType DWORD -Force | Out-Null
    Write-Host "Automatic device registration enabled." -ForegroundColor Green

    # Force device registration with dsregcmd
    Write-Host "Initiating device registration with Entra ID..." -ForegroundColor Cyan
    
    # Perform the Azure AD join
    Write-Host "Starting Entra ID join process..." -ForegroundColor Cyan
    $joinResult = dsregcmd /join
    Write-Host $joinResult

    # Check registration status
    $status = dsregcmd /status
    Write-Host "`nDevice registration status:" -ForegroundColor Cyan
    
    # Extract and display relevant Azure AD Join information from status
    $azureAdJoinInfo = $status | Select-String -Pattern "AzureAdJoined|WorkplaceJoined|TenantId|TenantName" -Context 0,1
    $azureAdJoinInfo | ForEach-Object { Write-Host $_ -ForegroundColor Yellow }
    
    # Verify join status
    $joinStatus = $status | Select-String -Pattern "AzureAdJoined" -Context 0,1
    if ($joinStatus -match "YES") {
        Write-Host "`nEntra ID Join completed successfully!" -ForegroundColor Green
        Write-Host "A system restart is required to complete the process." -ForegroundColor Yellow
        
        # Ask for restart
        $restart = Read-Host "Do you want to restart the computer now to complete the process? (Y/N)"
        if ($restart -eq "Y" -or $restart -eq "y") {
            Restart-Computer -Force
        } else {
            Write-Host "Please restart the computer manually to complete the Entra ID Join process." -ForegroundColor Yellow
        }
    } else {
        Write-Warning "Entra ID Join may not have completed successfully. Please check status with 'dsregcmd /status'"
    }
    
} catch {
    $errorMessage = $_.Exception.Message
    Write-Error "Entra ID Join failed: $errorMessage"
    
    # Provide troubleshooting information
    Write-Host "`nTroubleshooting Information:" -ForegroundColor Cyan
    Write-Host "Common issues:" -ForegroundColor Cyan
    Write-Host "- Verify network connectivity to Azure AD endpoints"
    Write-Host "- Check DNS settings"
    Write-Host "- Ensure user has permissions to join devices to Azure AD"
    Write-Host "- Check firewall settings"
    
    # Additional diagnostic info
    Write-Host "`nRunning additional diagnostics..." -ForegroundColor Cyan
    
    Write-Host "`nCurrent DNS settings:"
    $adapter = Get-NetAdapter | Where-Object {$_.Status -eq "Up"} | Select-Object -First 1
    if ($adapter) {
        Get-DnsClientServerAddress | Where-Object {$_.InterfaceAlias -eq $adapter.Name} | Format-Table -AutoSize
    }
    
    Write-Host "`nDS Client Status:" 
    dsregcmd /status
    
    exit 1
}