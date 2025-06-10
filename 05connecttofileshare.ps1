param(
    [string]$StorageAccountName = "sa29012025n002",
    [string]$ShareName = "share",
    [string]$ResourceGroupName = "new-week-rg",
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
Write-Output "Testing network connectivity to $StorageAccountName.file.core.windows.net on port 445..."
$connectTestResult = Test-NetConnection -ComputerName "$StorageAccountName.file.core.windows.net" -Port 445

if ($connectTestResult.TcpTestSucceeded) {
    Write-Output "Network connectivity test passed"
    
    try {
        # Disconnect any existing drive mapping
        Write-Output "Checking for existing drive mapping on $DriveLetter`:"
        try {
            $null = net use "$DriveLetter`:" /delete /yes 2>&1
            Write-Output "Removed existing drive mapping"
        } catch {
            Write-Output "No existing drive mapping found"
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
} else {
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