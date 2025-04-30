<#
.SYNOPSIS
    Export all company-owned Intune-managed Windows and macOS devices and upload the CSV to Azure Blob Storage.

.DESCRIPTION
    This script connects to Microsoft Graph API using app credentials to fetch Intune-managed devices 
    with specific enrollment types and uploads the resulting CSV to an Azure Blob Storage container.

.AUTHOR
    Rui Saloio

.NOTES
    Requires the following PowerShell modules:
    - Microsoft.Graph
    - Az.Storage
#>

# Install necessary modules (only needed the first time)
Install-Module -Name Microsoft.Graph.Authentication -AllowClobber -Force
Install-Module -Name Microsoft.Graph.Intune -AllowClobber -Force
Install-Module -Name Microsoft.Graph.DeviceManagement -AllowClobber -Force
Install-Module -Name Az.Storage -AllowClobber -Force

# Set tenant and app credentials (REPLACE with secure values or use a secure credential store)
$tenantId = "<your-tenant-id>"
$authority = "https://login.windows.net/$tenantId"
$clientId = "<your-client-id>"
$clientSecret = "<your-client-secret>"

# Update MSGraph environment and connect
Update-MSGraphEnvironment -AppId $clientId -Quiet
Update-MSGraphEnvironment -AuthUrl $authority -Quiet
Connect-MSGraph -ClientSecret $clientSecret -Quiet

# Get authentication token for Microsoft Graph
$body =  @{
    Grant_Type    = "client_credentials"
    Scope         = "https://graph.microsoft.com/.default"
    Client_Id     = $clientId
    Client_Secret = $clientSecret
}
$connection = Invoke-RestMethod `
    -Uri "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token" `
    -Method POST `
    -Body $body

# Connect to Microsoft Graph with token
$token = ConvertTo-SecureString $connection.access_token -AsPlainText -Force
Connect-MgGraph -AccessToken $token | Out-Null

# Retrieve all Windows and macOS devices enrolled via specific methods
$allDevices = Get-IntuneManagedDevice `
    -Filter "(operatingSystem eq 'Windows') or (operatingSystem eq 'macOS')" |
    Get-MSGraphAllPages |
    Where-Object {
        $_.managedDeviceOwnerType -eq "company" -and (
            $_.deviceEnrollmentType -in @(
                "userEnrollment", 
                "appleBulkWithUser", 
                "windowsAzureADJoin", 
                "windowsAutoEnrollment", 
                "windowsBulkAzureDomainJoin", 
                "windowsCoManagement"
            )
        )
    }

# Export to CSV
$csvPath = "$PSScriptRoot\AllIntuneManagedDevice.csv"
$allDevices | Export-Csv -Path $csvPath -NoTypeInformation

# Upload to Azure Blob Storage
$storageAccountName = "<your-storage-account-name>"
$containerName = "<your-container-name>"
$sasToken = "<your-sas-token>"

$context = New-AzStorageContext -StorageAccountName $storageAccountName -SasToken $sasToken
Set-AzStorageBlobContent `
    -File $csvPath `
    -Container $containerName `
    -Blob "AllIntuneManagedDevice_$(Get-Date -Format yyyy-MM-dd).csv" `
    -Context $context
