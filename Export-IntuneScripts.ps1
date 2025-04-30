<#
    Script Name: Intune Device Management Script Backup
    Description: This script authenticates to Microsoft Graph using client credentials and performs a backup 
                 of Intune Device Management Scripts using the IntuneBackupAndRestore module.
    Author: Rui Saloio
    Date: 2025-02-15
    Version: 1.0
#>

# Ensure Microsoft.Graph module is installed
if (-not (Get-Module -ListAvailable -Name Microsoft.Graph)) {
    Install-Module -Name Microsoft.Graph -Force -Scope CurrentUser
}

# Ensure IntuneBackupAndRestore module is installed
if (-not (Get-Module -ListAvailable -Name IntuneBackupAndRestore)) {
    Install-Module -Name IntuneBackupAndRestore -Force -Scope CurrentUser
}

# Import the IntuneBackupAndRestore module to use its backup functionality
Import-Module IntuneBackupAndRestore

# Define authentication variables (replace with your actual values when using the script)
$tenantId = "<Tenant_ID>"  # Your Azure AD tenant ID
$clientId = "<Client_ID>"  # The client ID of your Azure AD application
$clientSecret = "<Client_Secret>"  # The client secret for the application

# Define the token endpoint URL
$authority = "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token"
$resource = "https://graph.microsoft.com"

# Get the path where this script is located (used for output directory)
$scriptPath = Split-Path -Path $MyInvocation.MyCommand.Path -Parent

# Create the request body for obtaining the OAuth2 token
$body = @{
    client_id     = $clientId
    scope         = "$resource/.default"  # Permission scope required by Microsoft Graph
    client_secret = $clientSecret
    grant_type    = "client_credentials"  # Client credentials grant for app-only auth
}

# Request the access token from Azure AD
$response = Invoke-RestMethod -Method Post -Uri $authority -ContentType "application/x-www-form-urlencoded" -Body $body

# Store the access token from the response
$accessToken = $response.access_token

# Convert the access token to a SecureString format for use with Connect-MgGraph
$secureAccessToken = ConvertTo-SecureString -String $accessToken -AsPlainText -Force

# Connect to Microsoft Graph using the access token
Connect-MgGraph -AccessToken $secureAccessToken

# Perform the backup of Intune Device Management Scripts to the same folder as the script
Invoke-IntuneBackupDeviceManagementScript -Path $scriptPath
