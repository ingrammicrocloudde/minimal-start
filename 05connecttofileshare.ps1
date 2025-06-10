param(
    [Parameter(Mandatory=$false)]
    [ValidatePattern('^[a-z0-9]{3,24}$')]
    [string]$StorageAccountName = "sa29012025n002",
    
    [Parameter(Mandatory=$false)]
    [ValidatePattern('^[a-z0-9\-]{3,63}$')]
    [string]$ShareName = "share",
    
    [Parameter(Mandatory=$false)]
    [ValidateNotNullOrEmpty()]
    [string]$ResourceGroupName = "new-week-rg",
    
    [Parameter(Mandatory=$false)]
    [ValidatePattern('^[A-Z]$')]
    [string]$DriveLetter = "Z"
)
# Ensure user is logged into Azure
try {
    $context = Get-AzContext
    if (-not $context) {
        Write-Output "Logging into Azure..."
        Connect-AzAccount
    }
} catch {
    Write-Error "Failed to authenticate with Azure: $_"
    exit 1
}

# Get the storage account key
try {
    Write-Output "Retrieving storage account key for $StorageAccountName..."
    $storageAccountKey = (Get-AzStorageAccountKey -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -ErrorAction Stop)[0].Value
    Write-Output "Successfully retrieved storage account key"
} catch {
    Write-Error "Failed to retrieve storage account key: $_"
    Write-Output "Make sure you have the correct permissions and the storage account exists in the specified resource group."
    exit 1
}

# Test network connectivity first
$fileEndpoint = "$StorageAccountName.file.core.windows.net"
Write-Output "Testing network connectivity to $fileEndpoint on port 445..."

try {
    $connectTestResult = Test-NetConnection -ComputerName $fileEndpoint -Port 445 -WarningAction SilentlyContinue
    
    if (-not $connectTestResult.TcpTestSucceeded) {
        Write-Error "Network connectivity test failed. Unable to reach $fileEndpoint on port 445."
        Write-Output "This could be due to:"
        Write-Output "  - Corporate firewall blocking port 445"
        Write-Output "  - ISP blocking SMB traffic"
        Write-Output "  - Network configuration issues"
        Write-Output "Consider using Azure VPN Gateway or ExpressRoute."
        exit 1
    }
    
    Write-Output "Network connectivity test passed (Response time: $($connectTestResult.PingReplyDetails.RoundtripTime)ms)"
} catch {
    Write-Error "Network connectivity test encountered an error: $_"
    exit 1
}
    
    try {
        # Disconnect any existing drive mapping
        Write-Output "Checking for existing drive mapping on $DriveLetter`:"
        try {
            $existingMapping = Get-WmiObject -Class Win32_LogicalDisk | Where-Object { $_.DeviceID -eq "$DriveLetter`:" }
            if ($existingMapping) {
                $null = net use "$DriveLetter`:" /delete /yes 2>&1
                Write-Output "Removed existing drive mapping"
            } else {
                Write-Output "No existing drive mapping found"
            }
        } catch {
            Write-Output "No existing drive mapping found or failed to remove: $($_.Exception.Message)"
        }
        
        # Mount the drive using net use command
        $uncPath = "\\$StorageAccountName.file.core.windows.net\$ShareName"
        $username = "Azure\$StorageAccountName"
        
        Write-Output "Mounting Azure file share..."
        Write-Output "UNC Path: $uncPath"
        Write-Output "Username: $username"
        
        # Use net use to mount the drive
        $result = cmd /c "net use $DriveLetter`: `"$uncPath`" /user:`"$username`" `"$storageAccountKey`" /persistent:no 2>&1"
        
        if ($LASTEXITCODE -eq 0) {
            Write-Output "Successfully mounted Azure file share as $DriveLetter`: drive"
        } else {
            Write-Error "Net use command failed with exit code: $LASTEXITCODE"
            Write-Output "Command output: $result"
            throw "Failed to mount drive"
        }
    }
    catch {
        Write-Error "Failed to mount Azure file share: $_"
        Write-Output ""
        Write-Output "Manual command to try:"
        Write-Output "net use $DriveLetter`: `"\\$StorageAccountName.file.core.windows.net\$ShareName`" /user:`"Azure\$StorageAccountName`" `"<storage-account-key>`" /persistent:no"
    }
 else {
    Write-Error "Network connectivity test failed. Unable to reach $StorageAccountName.file.core.windows.net on port 445."
    Write-Output "Check to make sure your organization or ISP is not blocking port 445, or use Azure P2S VPN, Azure S2S VPN, or Express Route to tunnel SMB traffic over a different port."
    exit 1
}

# Test the mounted drive
Write-Output "Testing mounted drive..."
if (Test-Path "$DriveLetter`:\") {
    Write-Output "Drive $DriveLetter`: is accessible"
    try {
        $items = Get-ChildItem "$DriveLetter`:\" -ErrorAction Stop
        Write-Output "Contents of $DriveLetter`:\"
        if ($items.Count -eq 0) {
            Write-Output "  (empty)"
        } else {
            $items | ForEach-Object { Write-Output "  $($_.Name)" }
        }
    } catch {
        Write-Warning "Could not list contents of $DriveLetter`:\ - $($_.Exception.Message)"
    }
} else {
    Write-Warning "Drive $DriveLetter`: is not accessible after mounting"
}

Write-Output "Script completed successfully"