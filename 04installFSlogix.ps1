[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$DownloadPath = "$env:TEMP\FSLogix",
    
    [Parameter(Mandatory=$false)]
    [switch]$ConfigureBasicSettings,
    
    [Parameter(Mandatory=$false)]
    [string]$ProfileContainerPath,
    
    [Parameter(Mandatory=$false)]
    [string]$OfficeContainerPath,
    
    [Parameter(Mandatory=$false)]
    [switch]$EnableProfileContainer,
    
    [Parameter(Mandatory=$false)]
    [switch]$EnableOfficeContainer,
    
    [Parameter(Mandatory=$false)]
    [switch]$NoRestart
)

# Ensure running as administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    throw "This script must be run as Administrator"
}

Write-Host "Starting FSLogix download and installation..." -ForegroundColor Green

try {
    # Create download directory
    if (-not (Test-Path $DownloadPath)) {
        New-Item -Path $DownloadPath -ItemType Directory -Force | Out-Null
        Write-Host "Created download directory: $DownloadPath" -ForegroundColor Yellow
    }

    # FSLogix download URL (Microsoft official download)
    $fslogixUrl = "https://aka.ms/fslogix_download"
    $zipFile = Join-Path $DownloadPath "FSLogix.zip"
    $extractPath = Join-Path $DownloadPath "FSLogix"

    # Download FSLogix
    Write-Host "Downloading FSLogix from Microsoft..." -ForegroundColor Yellow
    try {
        # Use Invoke-WebRequest with better error handling
        $progressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $fslogixUrl -OutFile $zipFile -UseBasicParsing
        Write-Host "FSLogix downloaded successfully" -ForegroundColor Green
    } catch {
        throw "Failed to download FSLogix: $_"
    }

    # Extract the zip file
    Write-Host "Extracting FSLogix installation files..." -ForegroundColor Yellow
    try {
        if (Test-Path $extractPath) {
            Remove-Item $extractPath -Recurse -Force
        }
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($zipFile, $extractPath)
        Write-Host "FSLogix extracted successfully" -ForegroundColor Green
    } catch {
        throw "Failed to extract FSLogix: $_"
    }

    # Find the installer based on system architecture
    $arch = if ([Environment]::Is64BitOperatingSystem) { "x64" } else { "x86" }
    Write-Host "Detected system architecture: $arch" -ForegroundColor Yellow

    # Look for the installer
    $installerPath = Get-ChildItem -Path $extractPath -Recurse -Filter "FSLogixAppsSetup.exe" | 
                     Where-Object { $_.DirectoryName -like "*$arch*" } | 
                     Select-Object -First 1

    if (-not $installerPath) {
        # Fallback: look for any FSLogixAppsSetup.exe
        $installerPath = Get-ChildItem -Path $extractPath -Recurse -Filter "FSLogixAppsSetup.exe" | 
                         Select-Object -First 1
    }

    if (-not $installerPath) {
        throw "FSLogix installer not found in extracted files"
    }

    Write-Host "Found FSLogix installer: $($installerPath.FullName)" -ForegroundColor Green

    # Install FSLogix
    Write-Host "Installing FSLogix..." -ForegroundColor Yellow
    try {
        $installArgs = "/install /quiet /norestart"
        $process = Start-Process -FilePath $installerPath.FullName -ArgumentList $installArgs -Wait -PassThru -NoNewWindow
        
        if ($process.ExitCode -eq 0) {
            Write-Host "FSLogix installed successfully" -ForegroundColor Green
        } elseif ($process.ExitCode -eq 3010) {
            Write-Host "FSLogix installed successfully (reboot required)" -ForegroundColor Yellow
        } else {
            throw "FSLogix installation failed with exit code: $($process.ExitCode)"
        }
    } catch {
        throw "Failed to install FSLogix: $_"
    }

    # Configure basic settings if requested
    if ($ConfigureBasicSettings) {
        Write-Host "Configuring FSLogix basic settings..." -ForegroundColor Yellow
        
        # Registry path for FSLogix
        $fslogixRegPath = "HKLM:\SOFTWARE\FSLogix\Profiles"
        $officeRegPath = "HKLM:\SOFTWARE\Policies\FSLogix\ODFC"
        
        # Ensure registry paths exist
        if (-not (Test-Path $fslogixRegPath)) {
            New-Item -Path $fslogixRegPath -Force | Out-Null
        }
        
        if (-not (Test-Path $officeRegPath)) {
            New-Item -Path $officeRegPath -Force | Out-Null
        }

        # Configure Profile Container
        if ($EnableProfileContainer) {
            Write-Host "Enabling FSLogix Profile Container..." -ForegroundColor Yellow
            Set-ItemProperty -Path $fslogixRegPath -Name "Enabled" -Value 1 -Type DWord
            
            if ($ProfileContainerPath) {
                Set-ItemProperty -Path $fslogixRegPath -Name "VHDLocations" -Value $ProfileContainerPath -Type String
                Write-Host "Profile Container path set to: $ProfileContainerPath" -ForegroundColor Green
            }
            
            # Additional recommended settings
            Set-ItemProperty -Path $fslogixRegPath -Name "SizeInMBs" -Value 30000 -Type DWord
            Set-ItemProperty -Path $fslogixRegPath -Name "IsDynamic" -Value 1 -Type DWord
            Set-ItemProperty -Path $fslogixRegPath -Name "VolumeType" -Value "VHDX" -Type String
            Set-ItemProperty -Path $fslogixRegPath -Name "FlipFlopProfileDirectoryName" -Value 1 -Type DWord
            
            Write-Host "Profile Container configured successfully" -ForegroundColor Green
        }

        # Configure Office Container
        if ($EnableOfficeContainer) {
            Write-Host "Enabling FSLogix Office Container..." -ForegroundColor Yellow
            Set-ItemProperty -Path $officeRegPath -Name "Enabled" -Value 1 -Type DWord
            
            if ($OfficeContainerPath) {
                Set-ItemProperty -Path $officeRegPath -Name "VHDLocations" -Value $OfficeContainerPath -Type String
                Write-Host "Office Container path set to: $OfficeContainerPath" -ForegroundColor Green
            }
            
            # Additional recommended settings for Office
            Set-ItemProperty -Path $officeRegPath -Name "SizeInMBs" -Value 30000 -Type DWord
            Set-ItemProperty -Path $officeRegPath -Name "IsDynamic" -Value 1 -Type DWord
            Set-ItemProperty -Path $officeRegPath -Name "VolumeType" -Value "VHDX" -Type String
            Set-ItemProperty -Path $officeRegPath -Name "IncludeOneNote" -Value 1 -Type DWord
            Set-ItemProperty -Path $officeRegPath -Name "IncludeOneNoteUWP" -Value 1 -Type DWord
            Set-ItemProperty -Path $officeRegPath -Name "IncludeOutlook" -Value 1 -Type DWord
            Set-ItemProperty -Path $officeRegPath -Name "IncludeOutlookPersonalization" -Value 1 -Type DWord
            Set-ItemProperty -Path $officeRegPath -Name "IncludeSharepoint" -Value 1 -Type DWord
            Set-ItemProperty -Path $officeRegPath -Name "IncludeSkype" -Value 1 -Type DWord
            Set-ItemProperty -Path $officeRegPath -Name "IncludeTeams" -Value 1 -Type DWord
            
            Write-Host "Office Container configured successfully" -ForegroundColor Green
        }
    }

    # Clean up download files
    Write-Host "Cleaning up temporary files..." -ForegroundColor Yellow
    try {
        Remove-Item $zipFile -Force -ErrorAction SilentlyContinue
        Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "Cleanup completed" -ForegroundColor Green
    } catch {
        Write-Warning "Could not clean up temporary files: $_"
    }

    # Check if reboot is required
    $rebootRequired = $false
    if (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired" -ErrorAction SilentlyContinue) {
        $rebootRequired = $true
    }
    
    if (Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending" -ErrorAction SilentlyContinue) {
        $rebootRequired = $true
    }

    Write-Host "`nFSLogix installation completed successfully!" -ForegroundColor Green
    
    if ($ConfigureBasicSettings) {
        Write-Host "`nConfiguration Summary:" -ForegroundColor Cyan
        if ($EnableProfileContainer) {
            Write-Host "✓ Profile Container: Enabled" -ForegroundColor Green
            if ($ProfileContainerPath) {
                Write-Host "  Path: $ProfileContainerPath" -ForegroundColor White
            }
        }
        if ($EnableOfficeContainer) {
            Write-Host "✓ Office Container: Enabled" -ForegroundColor Green
            if ($OfficeContainerPath) {
                Write-Host "  Path: $OfficeContainerPath" -ForegroundColor White
            }
        }
    }

    Write-Host "`nNext Steps:" -ForegroundColor Cyan
    Write-Host "1. Configure additional FSLogix settings as needed" -ForegroundColor White
    Write-Host "2. Set up your profile container storage location" -ForegroundColor White
    Write-Host "3. Configure appropriate permissions on storage" -ForegroundColor White
    Write-Host "4. Test with a user account" -ForegroundColor White

    if ($rebootRequired -and -not $NoRestart) {
        Write-Host "`nA system reboot is required to complete the installation." -ForegroundColor Yellow
        $response = Read-Host "Would you like to restart now? (Y/N)"
        if ($response -eq 'Y' -or $response -eq 'y') {
            Write-Host "Restarting system..." -ForegroundColor Yellow
            Restart-Computer -Force
        }
    } elseif ($rebootRequired) {
        Write-Host "`nA system reboot is required to complete the installation." -ForegroundColor Yellow
    }

} catch {
    Write-Error "FSLogix installation failed: $_"
    Write-Host "`nTroubleshooting:" -ForegroundColor Red
    Write-Host "1. Ensure you're running as Administrator" -ForegroundColor White
    Write-Host "2. Check internet connectivity" -ForegroundColor White
    Write-Host "3. Verify Windows version compatibility" -ForegroundColor White
    Write-Host "4. Check available disk space" -ForegroundColor White
    exit 1
}
