<#
.SYNOPSIS
    Exports Microsoft Intune Device Compliance Policies and related details using Microsoft Graph API.

.DESCRIPTION
    This PowerShell script connects to Microsoft Graph API via client credentials to retrieve
    all device compliance policies, their assignments, device status overviews, settings, and status per device.
    It exports each policy with its associated metadata into individual JSON files for documentation or backup purposes.

.AUTHOR
    Rui Saloio

.NOTES
    Before running the script, replace the placeholders below with actual values:
    - $tenant = "<your-tenant-name>.onmicrosoft.com"
    - $tenantId = "<your-tenant-id>"
    - $clientId = "<your-client-id>"
    - $clientSecret = "<your-client-secret>"

    The script assumes appropriate Microsoft Graph API permissions (e.g., DeviceManagementConfiguration.Read.All).
#>

# Define authentication variables
$tenant = "<your-tenant-name>.onmicrosoft.com"
$tenantId = "<your-tenant-id>"
$clientId = "<your-client-id>"
$clientSecret = "<your-client-secret>"

# Microsoft Graph API base URL
$graphBaseUrl = "https://graph.microsoft.com/v1.0"

# Acquire access token using client credentials flow
$body = @{
    client_id     = $clientId
    client_secret = $clientSecret
    grant_type    = "client_credentials"
    scope         = "https://graph.microsoft.com/.default"
}
$tokenResponse = Invoke-RestMethod -Uri "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token" -Method POST -Body $body
$token = $tokenResponse.access_token

# Set authorization headers for all API calls
$headers = @{
    "Authorization" = "Bearer $token"
    "Content-Type"  = "application/json"
}

# Get all device compliance policies
$policiesUrl = "$graphBaseUrl/deviceManagement/deviceCompliancePolicies"
$policiesResponse = Invoke-RestMethod -Uri $policiesUrl -Headers $headers -Method GET
$policies = $policiesResponse.value

# Determine the directory of the current script
$scriptFolder = $PSScriptRoot

# Loop through each policy
foreach ($policy in $policies) {
    try {
        # Fetch full policy details
        $policyDetailsUrl = "$graphBaseUrl/deviceManagement/deviceCompliancePolicies/$($policy.id)"
        $policyDetailsResponse = Invoke-RestMethod -Uri $policyDetailsUrl -Headers $headers -Method GET

        # Fetch policy assignments (i.e., which groups the policy is assigned to)
        $assignmentsUrl = "$graphBaseUrl/deviceManagement/deviceCompliancePolicies/$($policy.id)/assignments"
        $assignmentsResponse = Invoke-RestMethod -Uri $assignmentsUrl -Headers $headers -Method GET
        $assignments = $assignmentsResponse.value

        # Fetch device compliance status overview
        $deviceStatusOverviewUrl = "$graphBaseUrl/deviceManagement/deviceCompliancePolicies/$($policy.id)/deviceStatusOverview"
        $deviceStatusOverview = Invoke-RestMethod -Uri $deviceStatusOverviewUrl -Headers $headers -Method GET

        # Fetch settings summary
        $deviceSettingStateSummariesUrl = "$graphBaseUrl/deviceManagement/deviceCompliancePolicies/$($policy.id)/deviceSettingStateSummaries"
        $deviceSettingStateSummariesResponse = Invoke-RestMethod -Uri $deviceSettingStateSummariesUrl -Headers $headers -Method GET
        $deviceSettingStateSummaries = $deviceSettingStateSummariesResponse.value.settingName

        # Fetch status of each device under the policy
        $deviceStatusesUrl = "$graphBaseUrl/deviceManagement/deviceCompliancePolicies/$($policy.id)/deviceStatuses"
        $deviceStatusesResponse = Invoke-RestMethod -Uri $deviceStatusesUrl -Headers $headers -Method GET

        # Append display group name to each assignment
        foreach ($assignment in $assignments) {
            if ($assignment.target.groupId) {
                $groupUrl = "$graphBaseUrl/groups/$($assignment.target.groupId)"
                $groupResponse = Invoke-RestMethod -Uri $groupUrl -Headers $headers -Method GET
                $groupName = $groupResponse.displayName
                $assignment | Add-Member -MemberType NoteProperty -Name "GroupName" -Value $groupName
            } else {
                $assignment | Add-Member -MemberType NoteProperty -Name "GroupName" -Value "No Group Assigned"
            }
        }

        # Build final object with all relevant policy data
        $policyDetailsWithAssignments = @{
            Basics           = $policyDetailsResponse
            Assignments      = $assignments
            ComplianceStatus = $deviceStatusOverview
            Settings         = $deviceSettingStateSummaries
        }

        # Convert to JSON
        $policyJson = $policyDetailsWithAssignments | ConvertTo-Json -Depth 5

        # Clean file name and save JSON to disk
        $displayFileName = $policy.displayName.Replace("[", "").Replace("]", "")
        $idFilename = $policyDetailsResponse.id
        $fileName = "$displayFileName - $idFilename.json"
        $filePath = Join-Path -Path $scriptFolder -ChildPath $fileName

        # Remove any old file with the same policy ID
        $existingFiles = Get-ChildItem -Path $scriptFolder -Filter "*- $idFilename.json"
        foreach ($file in $existingFiles) {
            Remove-Item -Path $file.FullName -Force
            Write-Host "Deleted existing file: $($file.FullName)"
        }

        # Save JSON to file
        $policyJson | Out-File -FilePath $filePath -Encoding UTF8

        Write-Host "Saved policy '$($policy.displayName)' to $filePath"
    } catch {
        Write-Host "Error processing policy $($policy.displayName): $_"
    }
}
