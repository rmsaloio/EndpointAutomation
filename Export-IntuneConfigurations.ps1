<#
    Script Name: Export Intune Configuration Profiles to JSON
    Description: This script authenticates with Microsoft Graph API using client credentials and exports
                 Intune configuration profiles (device configurations, GPOs, and configuration policies)
                 along with their assignments and device status overviews (when available) to JSON files.
    Author: Rui Saloio
    Date: 2025-03-19
    Version: 1.0
#>

# Define authentication parameters (replace placeholders with actual values if using manually)
$tenant = "<tenant_name>.onmicrosoft.com"
$tenantid = "<tenant_id>"
$authority = "https://login.windows.net/$tenantid"
$clientId = "<client_id>"
$clientSecret = "<client_secret>"

# Function to obtain an OAuth2 access token from Microsoft identity platform
function Get-AccessToken {
    $body = @{
        client_id     = $clientId
        client_secret = $clientSecret
        grant_type    = "client_credentials"
        scope         = "https://graph.microsoft.com/.default"
    }
    $response = Invoke-RestMethod -Uri "$authority/oauth2/v2.0/token" -Method Post -ContentType "application/x-www-form-urlencoded" -Body $body
    return $response.access_token
}

# Function to fetch all paged results for a given Graph endpoint
function Get-AllConfigurations {
    param (
        [string]$url,
        [hashtable]$headers
    )
    
    $allConfigurations = @()
    do {
        $response = Invoke-RestMethod -Uri $url -Method Get -Headers $headers
        $allConfigurations += $response.value
        $url = $response.'@odata.nextLink'
    } while ($url)

    return $allConfigurations
}

# Fetch assignments for a specific configuration
function Get-Assignments {
    param (
        [string]$configurationId,
        [string]$configType,
        [hashtable]$headers
    )

    $assignmentsUrl = switch ($configType) {
        "deviceConfigurations"       { "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations/$configurationId/assignments" }
        "groupPolicyConfigurations"  { "https://graph.microsoft.com/beta/deviceManagement/groupPolicyConfigurations/$configurationId/assignments" }
        "configurationPolicies"      { "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies/$configurationId/assignments" }
        default { return @() }
    }

    try {
        $assignmentsResponse = Invoke-RestMethod -Uri $assignmentsUrl -Method Get -Headers $headers
        return $assignmentsResponse.value
    } catch {
        Write-Host "Error fetching assignments for ID: $configurationId"
        return @()
    }
}

# Retrieve device status overview (only valid for deviceConfigurations)
function Get-DeviceStatusOverview {
    param (
        [string]$configurationId,
        [string]$configType,
        [hashtable]$headers
    )

    if ($configType -ne "deviceConfigurations") {
        return $null
    }

    $statusUrl = "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations/$configurationId/deviceStatusOverview"

    try {
        $statusResponse = Invoke-RestMethod -Uri $statusUrl -Method Get -Headers $headers
        return $statusResponse
    } catch {
        Write-Host "Error fetching device status for ID: $configurationId"
        return $null
    }
}

# Lookup the name of an Azure AD group by its ID
function Get-GroupName {
    param ([string]$groupId, [hashtable]$headers)

    $groupUrl = "https://graph.microsoft.com/v1.0/groups/$groupId"
    try {
        $groupResponse = Invoke-RestMethod -Uri $groupUrl -Method Get -Headers $headers
        return $groupResponse.displayName
    } catch {
        return "Unknown Group"
    }
}

# Remove invalid characters from file names
function Clean-FileName {
    param ([string]$name)
    $invalidChars = '[\\/:*?"<>|\[\]]'
    $cleanName = $name -replace $invalidChars, ''
    return $cleanName.Trim()
}

# Acquire access token and prepare authorization header
$token = Get-AccessToken
$headers = @{
    Authorization = "Bearer $token"
    "Content-Type" = "application/json"
}

# Endpoints to query various configuration types
$endpoints = @{
    "deviceConfigurations"       = "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations"
    "groupPolicyConfigurations"  = "https://graph.microsoft.com/beta/deviceManagement/groupPolicyConfigurations"
    "configurationPolicies"      = "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies"
}

# Define the directory to output the JSON files (same as script location)
$outputDirectory = $PSScriptRoot
Write-Host "Files will be saved in: $outputDirectory"

# Loop through each configuration type and export their data
foreach ($configType in $endpoints.Keys) {
    $endpoint = $endpoints[$configType]
    Write-Host "Fetching data from: $endpoint"

    $allConfigurations = Get-AllConfigurations -url $endpoint -headers $headers

    foreach ($Configuration in $allConfigurations) {
        Write-Host "Processing configuration ID: $($Configuration.id)"

        if (-not $Configuration.id) {
            Write-Host "Error: Configuration ID missing"
            continue
        }

        # Get additional metadata
        $assignments = Get-Assignments -configurationId $Configuration.id -configType $configType -headers $headers
        $deviceStatus = Get-DeviceStatusOverview -configurationId $Configuration.id -configType $configType -headers $headers

        # Resolve group names for group-based assignments
        foreach ($assignment in $assignments) {
            if ($assignment.target.'@odata.type' -eq "#microsoft.graph.groupAssignmentTarget") {
                $groupId = $assignment.target.groupId
                $groupName = Get-GroupName -groupId $groupId -headers $headers
                $assignment | Add-Member -MemberType NoteProperty -Name "groupName" -Value $groupName -Force
            }
        }

        # Build export object
        $ConfigurationData = @{ }
        foreach ($property in $Configuration.PSObject.Properties) {
            $ConfigurationData[$property.Name] = $property.Value
        }
        $ConfigurationData["assignments"] = $assignments
        if ($deviceStatus) {
            $ConfigurationData["deviceStatusOverview"] = $deviceStatus
        }

        # Create sanitized file name
        $fileName = if ($Configuration.PSObject.Properties["displayName"]) {
            Clean-FileName $Configuration.displayName
        } else {
            Clean-FileName $Configuration.Name
        }

        $fileNameID = $Configuration.id
        $filePath = Join-Path -Path $outputDirectory -ChildPath "$fileName - $fileNameID.json"

        # Export configuration to JSON
        try {
            $ConfigurationData | ConvertTo-Json -Depth 5 | Out-File -FilePath $filePath -Encoding UTF8
            Write-Host "JSON file created: $filePath"
        } catch {
            Write-Host "Error creating file: $filePath"
            Write-Host $_.Exception.Message
        }
    }
}

Write-Host "All JSON files have been successfully created."
