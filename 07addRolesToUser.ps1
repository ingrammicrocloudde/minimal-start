# Script to assign AVD roles using Azure PowerShell module
# Requires: Install-Module Az

# Check if Az module is installed
if (-not (Get-Module -ListAvailable -Name Az)) {
    Write-Host "Installing Azure PowerShell module..." -ForegroundColor Yellow
    Install-Module -Name Az -Force -AllowClobber
}

# Import required modules
Import-Module Az.Accounts
Import-Module Az.Resources

# Connect to Azure (if not already connected)
try {
    $context = Get-AzContext
    if (-not $context) {
        Connect-AzAccount
    }
}
catch {
    Connect-AzAccount
}

# User to assign roles to
$userPrincipalName = "Christoph.Zapatka@immpnde.onmicrosoft.com"

# Resource Group Configuration
$resourceGroupName = "rg-avd-resources"  # Change this to your resource group name

# Define the roles to assign
$roles = @(
    "Desktop Virtualization Application Group Reader",
    "Desktop Virtualization Contributor", 
    "Virtual Machine Administrator Login",
    "Virtual Machine User Login",
    "Desktop Virtualization Workspace Reader"
)

# Get current subscription
$subscription = Get-AzContext | Select-Object -ExpandProperty Subscription
$subscriptionId = $subscription.Id

Write-Host "Assigning roles to user: $userPrincipalName" -ForegroundColor Green
Write-Host "Subscription: $($subscription.Name) ($subscriptionId)" -ForegroundColor Yellow
Write-Host "Resource Group: $resourceGroupName" -ForegroundColor Yellow

# Verify resource group exists
try {
    $resourceGroup = Get-AzResourceGroup -Name $resourceGroupName -ErrorAction Stop
    Write-Host "Resource Group found: $($resourceGroup.ResourceGroupName)" -ForegroundColor Green
}
catch {
    Write-Error "Resource Group '$resourceGroupName' not found. Please update the `$resourceGroupName variable with the correct name."
    exit 1
}

# Get user object
try {
    $user = Get-AzADUser -UserPrincipalName $userPrincipalName
    if (-not $user) {
        throw "User not found"
    }
    Write-Host "User Object ID: $($user.Id)" -ForegroundColor Yellow
}
catch {
    Write-Error "User not found: $userPrincipalName"
    exit 1
}

# Assign each role
foreach ($role in $roles) {
    Write-Host "Assigning role: $role" -ForegroundColor Cyan
    
    try {
        New-AzRoleAssignment `
            -ObjectId $user.Id `
            -RoleDefinitionName $role `
            -ResourceGroupName $resourceGroupName
        
        Write-Host "✓ Successfully assigned role: $role" -ForegroundColor Green
    }
    catch {
        if ($_.Exception.Message -like "*already exists*") {
            Write-Host "→ Role already assigned: $role" -ForegroundColor Yellow
        } else {
            Write-Warning "Failed to assign role: $role"
            Write-Warning $_.Exception.Message
        }
    }
}

Write-Host "`nRole assignment completed!" -ForegroundColor Green
Write-Host "Verifying role assignments..." -ForegroundColor Yellow

# Verify role assignments at resource group level
Get-AzRoleAssignment -ObjectId $user.Id -ResourceGroupName $resourceGroupName | Format-Table RoleDefinitionName, Scope -AutoSize

Write-Host "`nScript execution completed." -ForegroundColor Green