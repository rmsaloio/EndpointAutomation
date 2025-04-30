<#
.SYNOPSIS
    This script retrieves information about managed devices in an Azure AD tenant, searches for specific applications on those devices, and exports the results to CSV files.
.DESCRIPTION
    The script authenticates using client credentials with Microsoft Graph API, fetches the list of managed devices, and identifies which of the specified applications are installed on each device. The results are exported into CSV files, one per application.
.AUTHOR
    Rui Saloio
.NOTES
    Replace sensitive values (e.g., tenantId, clientId, clientSecret) with appropriate placeholders or environment variables.
#>

# Azure AD tenant information and client credentials
$tenantId = "your-tenant-id"  # Replace with your actual tenant ID
$clientId = "your-client-id"  # Replace with your actual client ID
$clientSecret = "your-client-secret"  # Replace with your actual client secret

# List of applications to search for (Modify as needed)
$AppNames = @("Pulse Secure")  # Specify the names of the applications you want to search for in the managed devices.

# Manually request an OAuth token from Microsoft
# Requesting an access token using client credentials (clientId and clientSecret) to authenticate with Microsoft Graph API
$tokenUri = "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token"
$tokenBody = @{
    grant_type    = "client_credentials"
    client_id     = $clientId
    client_secret = $clientSecret
    scope         = "https://graph.microsoft.com/.default"  # Scopes for Microsoft Graph API
}
# Send the POST request to obtain the access token
$tokenResponse = Invoke-RestMethod -Uri $tokenUri -Method Post -Body $tokenBody

# Extract the access token from the response
$AccessToken = $tokenResponse.access_token

# Set authentication headers for Microsoft Graph
# The authorization header will carry the Bearer token for accessing the Microsoft Graph API
$Headers = @{
    Authorization = "Bearer $AccessToken"
    "Content-Type" = "application/json"
}

# API URI to fetch managed devices, with a filter to get only Windows operating system devices
$filter = "operatingSystem eq 'Windows'"  # You can modify this filter to fetch devices with different operating systems
$uri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$expand=detectedApps&`$filter=$filter"

# Retrieve all devices with pagination handling (if there are more devices than a single page can return)
$AllDevices = @()
do {
    # Send GET request to fetch the list of managed devices
    $response = Invoke-RestMethod -Uri $uri -Headers $Headers -Method GET
    $AllDevices += $response.value  # Append devices to the AllDevices array
    $uri = $response.'@odata.nextLink'  # Get the next page URL if available
} while ($uri)

# Output the total number of devices retrieved
Write-Host "Total devices found: $($AllDevices.Count)"

# Estimate the execution time based on the number of devices
$averageTimePerDevice = 0.005  # This is an approximation, adjust if needed
$totalEstimatedTime = $AllDevices.Count * $averageTimePerDevice
Write-Host "Estimated execution time: $totalEstimatedTime minutes"

# Create a dictionary to store results per application
$Results = @{}
foreach ($AppName in $AppNames) {
    $Results[$AppName] = @()  # Initialize an empty array to store results for each app
}

# Process each device individually to fetch detected applications
foreach ($device in $AllDevices) {
    Write-Host "Searching for the apps '$($AppNames -join '", "')' on device: $($device.deviceName)"

    $ID = $device.id
    $deviceUri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices('$ID')?`$expand=detectedApps"
    
    # Fetch detected applications for the specific device
    $deviceData = Invoke-RestMethod -Uri $deviceUri -Headers $Headers -Method GET
    $appsfound = $deviceData.detectedApps  # Get the list of detected apps on the device

    # Check if any apps were found on the device
    if ($appsfound -and $appsfound.Count -gt 0) {
        foreach ($app in $appsfound) {
            # Search for the application name in the list of apps installed on the device
            foreach ($AppName in $AppNames) {
                if ($app.displayName -like "*$AppName*") {
                    # If the app is found, store relevant data in memory (in the Results dictionary)
                    $Results[$AppName] += [pscustomobject]@{
                        DeviceName        = $device.deviceName
                        AppName           = $app.displayName
                        AppVersion        = $app.version
                        userPrincipalName = $device.userPrincipalName
                        id                = $device.id
                        userId            = $device.userId
                        azureADDeviceId   = $device.azureADDeviceId
                        enrolledDateTime  = $device.enrolledDateTime
                        lastSyncDateTime  = $device.lastSyncDateTime
                        operatingSystem   = $device.operatingSystem
                        osVersion         = $device.osVersion
                        complianceState   = $device.complianceState
                    }
                }
            }
        }
    } else {
        # If no applications are detected for this device, output a message
        Write-Host "No applications detected for device: $($device.deviceName)"
    }
}

# Export results to CSV files only if data exists for each application
foreach ($AppName in $AppNames) {
    # Check if any devices have the specified application installed
    if ($Results[$AppName].Count -gt 0) {
        # Export the results to a CSV file named after the application
        $OutputFile = "$PSScriptRoot\DevicesPerApp_$($AppName)_$(Get-Date -Format yyyy-MM-dd).csv"
        $Results[$AppName] | Export-Csv -Path $OutputFile -NoTypeInformation  # Export to CSV
        Write-Host "File generated: $OutputFile"
    } else {
        # If no results were found for this application, notify the user
        Write-Host "No devices found with the application: $AppName."
    }
}
