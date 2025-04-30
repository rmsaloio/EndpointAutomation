<#
    Script Name: Export Device Health Scripts from Microsoft Graph
    Description: This script connects to the Microsoft Graph API to export device health remediation scripts, 
                 including their detection and remediation components, as well as related metadata.
    Author: Rui Saloio
    Date: 2025-04-30
    Version: 1.0
#>

# Define authentication variables (replace these with actual values when using)
$tenantId = "<Tenant_ID>"  # Your Azure AD tenant ID
$clientId = "<Client_ID>"  # The client ID of your registered Azure AD app
$clientSecret = "<Client_Secret>"  # The client secret of your Azure AD app
$authority = "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token"  # Microsoft login authority for token acquisition
$resource = "https://graph.microsoft.com"  # Microsoft Graph API endpoint

# Create request body to obtain the OAuth token (client credentials flow)
$body = @{
    grant_type    = "client_credentials"  # Client credentials grant type for service-to-service authentication
    client_id     = $clientId  # Client ID for the Azure AD application
    client_secret = $clientSecret  # Client Secret for the Azure AD application
    scope         = "$resource/.default"  # Requesting access to Microsoft Graph API
}

# Obtain the access token by sending the request to the authority endpoint
$response = Invoke-RestMethod -Method Post -Uri $authority -ContentType "application/x-www-form-urlencoded" -Body $body

# Store the access token for further API calls
$accessToken = $response.access_token

# Get the directory where the script is located (for saving files in the same location)
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path

# Define the directory where exported files will be saved (called ExportFiles)
$exportDirectory = Join-Path $scriptDirectory "ExportFiles"

# Check if the ExportFiles directory exists, if not, create it
if (!(Test-Path -Path $exportDirectory)) {
    New-Item -ItemType Directory -Path $exportDirectory | Out-Null  # Create directory if it doesn't exist
}

# Define file extensions for detection and remediation scripts
$Detection = "Detection.ps1"
$Remediation = "Remediation.ps1"

# Set the version of the Graph API to use (currently using Beta for device management functionality)
$graphApiVersion = "Beta"
$graphUrl = "https://graph.microsoft.com/$graphApiVersion"

# Make the request to retrieve all remediation scripts from the device management API
$result = Invoke-RestMethod -Method Get -Uri "$graphUrl/deviceManagement/deviceHealthScripts" -Headers @{Authorization = "Bearer $accessToken"}

# Iterate through each script in the result
$scriptIds = $result.value | Select-Object id, displayName  # Extract the script ID and display name for each script
foreach($scriptId in $scriptIds) {
    # Request detailed information about each script by ID
    $script = Invoke-RestMethod -Method Get -Uri "$graphUrl/deviceManagement/deviceHealthScripts/$($scriptId.id)" -Headers @{Authorization = "Bearer $accessToken"}

    # Replace any invalid characters in the script display name (like brackets) to ensure valid filenames
    $safeDisplayName = $script.displayName -replace '[\[\]]', ''
    $fileSuffix = " - $($script.id)"  # Add script ID as a suffix for uniqueness

    # Define the file paths in the ExportFiles directory for detection, remediation, and metadata files
    $detectionFilePath = Join-Path $exportDirectory "$($safeDisplayName)$fileSuffix`_$Detection"
    $remediationFilePath = Join-Path $exportDirectory "$($safeDisplayName)$fileSuffix`_$Remediation"
    $jsonFilePath = Join-Path $exportDirectory "$($safeDisplayName)$fileSuffix.json"

    # Remove any existing files with matching names to avoid overwriting issues
    Get-ChildItem -Path $exportDirectory | Where-Object { $_.Name -match [regex]::Escape("$fileSuffix.json") } | Remove-Item -Force
    Get-ChildItem -Path $exportDirectory | Where-Object { $_.Name -match [regex]::Escape("$fileSuffix`_$Detection") } | Remove-Item -Force
    Get-ChildItem -Path $exportDirectory | Where-Object { $_.Name -match [regex]::Escape("$fileSuffix`_$Remediation") } | Remove-Item -Force

    # Save the detection script if it exists
    if ($script.detectionScriptContent) {
        [System.Text.Encoding]::ASCII.GetString([System.Convert]::FromBase64String($script.detectionScriptContent)) | Out-File -Encoding ASCII -FilePath $detectionFilePath
        Write-Host "Saving detection script: $detectionFilePath"  # Inform the user about the saved file
    }

    # Save the remediation script if it exists
    if ($script.remediationScriptContent) {
        [System.Text.Encoding]::ASCII.GetString([System.Convert]::FromBase64String($script.remediationScriptContent)) | Out-File -Encoding ASCII -FilePath $remediationFilePath
        Write-Host "Saving remediation script: $remediationFilePath"  # Inform the user about the saved file
    }

    # Retrieve assignments for the script (where it is assigned)
    $assignmentsResult = Invoke-RestMethod -Method Get -Uri "$graphUrl/deviceManagement/deviceHealthScripts/$($scriptId.id)/assignments" -Headers @{Authorization = "Bearer $accessToken"}
    $remediationData = @{
        id                          = $script.id
        publisher                   = $script.publisher
        version                     = $script.version
        displayName                 = $script.displayName
        description                 = $script.description
        detectionScriptContent      = $script.detectionScriptContent
        remediationScriptContent    = $script.remediationScriptContent
        createdDateTime             = $script.createdDateTime
        lastModifiedDateTime        = $script.lastModifiedDateTime
        runAsAccount                = $script.runAsAccount
        enforceSignatureCheck       = $script.enforceSignatureCheck
        runAs32Bit                  = $script.runAs32Bit
        roleScopeTagIds             = $script.roleScopeTagIds
        isGlobalScript              = $script.isGlobalScript
        highestAvailableVersion     = $script.highestAvailableVersion
        deviceHealthScriptType      = $script.deviceHealthScriptType
        detectionScriptParameters   = $script.detectionScriptParameters
        remediationScriptParameters = $script.remediationScriptParameters
        assignments = @()  # Placeholder to store assignment data for this script
        runSummary = @{}  # Placeholder for storing run summary data
    }

    # Loop through each assignment and retrieve group details
    foreach ($assignment in $assignmentsResult.value) {
        if ($assignment.target) {
            $groupId = $assignment.target.groupId
            $group = Invoke-RestMethod -Method Get -Uri "https://graph.microsoft.com/v1.0/groups/$groupId" -Headers @{Authorization = "Bearer $accessToken"}
            $remediationData.assignments += @{
                groupId = $groupId
                groupName = $group.displayName
            }
        }
    }

    # Retrieve the run summary for the script execution (if available)
    $runSummaryResult = Invoke-RestMethod -Method Get -Uri "$graphUrl/deviceManagement/deviceHealthScripts/$($scriptId.id)/runSummary" -Headers @{Authorization = "Bearer $accessToken"}
    if ($runSummaryResult) {
        $remediationData.runSummary = $runSummaryResult  # Store the run summary in remediation data
    }

    # Save all collected data as a JSON file in the export directory
    $remediationData | ConvertTo-Json -Depth 5 | Out-File -Encoding UTF8 -FilePath $jsonFilePath
    Write-Host "Saving remediation information as JSON: $jsonFilePath"  # Inform the user about the saved file
}
