<#
.SYNOPSIS
This script connects to Microsoft Graph, retrieves mobile app details from Intune, 
and generates a report of the app's attributes and assignments.

.DESCRIPTION
The script:
1. Installs necessary modules.
2. Authenticates using client credentials (AppId, TenantId, and ClientSecret).
3. Fetches details of mobile apps and their assignments from Intune via Microsoft Graph API.
4. Collects app details, including detection rules, and exports them to a CSV file.
5. Uploads the generated CSV report to Azure Blob Storage.

.AUTHOR
Rui Saloio

#>

# Install necessary PowerShell modules
Install-Module -Name Az.Storage -AllowClobber -Force
Install-Module -Name Microsoft.Graph.DeviceManagement -Force
Install-Module -Name Microsoft.Graph.Authentication -Force

# Define Global Variables
$CSVfile = "$PSScriptRoot\CATALOG.csv"

# Connect to Microsoft Graph using client credentials (Please ensure credentials are set in a secure way)
##################################################################################################################### 
# Update these values with your actual credentials. Ensure no secrets are hardcoded in the script for security purposes.
$tenant = "YOUR_TENANT_NAME.onmicrosoft.com"  # Your tenant name
$tenantid = "YOUR_TENANT_ID"  # Tenant ID
$authority = "https://login.windows.net/$tenantid"
$clientId = "YOUR_CLIENT_ID"  # Application (client) ID
$clientSecret = "YOUR_CLIENT_SECRET"  # Application client secret

# Update Microsoft Graph Environment
Update-MSGraphEnvironment -AppId $clientId -Quiet
Update-MSGraphEnvironment -AuthUrl $authority -Quiet

# Authenticate using the client secret
Connect-MSGraph -ClientSecret $ClientSecret -Quiet

# Obtain the OAuth2 token for authentication
$body = @{
    Grant_Type    = "client_credentials"
    Scope         = "https://graph.microsoft.com/.default"
    Client_Id     = $clientId
    Client_Secret = $clientSecret
}
$connection = Invoke-RestMethod -Uri "https://login.microsoftonline.com/$tenantid/oauth2/v2.0/token" -Method POST -Body $body
$token = ConvertTo-SecureString($connection.access_token) -AsPlainText -Force

# Connect to Microsoft Graph API using the obtained token
Connect-MgGraph -AccessToken $token | Out-Null

# Fetch mobile apps and their assignments from Microsoft Graph
$Resource = "deviceAppManagement/mobileApps"
$graphApiVersion = "Beta"
$uri = "https://graph.microsoft.com/$graphApiVersion/$($Resource)?`$expand=Assignments"
$Apps = (Invoke-MgGraphRequest -Method GET -Uri $uri).Value

# Initialize the report collection
$Report = [System.Collections.Generic.List[Object]]::new()

# Process each app and gather details
Foreach ($App in $Apps) { 
    # Clean up variables for each app
    $splitdetectiontype = ""
    $win32LobApp = ""
    $GroupDisplayName = ""
    $GroupIDList = ""
    $intent = ""
    $GroupDisplayName = ""
    $GroupIdAssignment = ""
    $GroupIntent = ""
    $GroupMgData = ""
    $MgID = ""
    $notifications = ""
    $Category = ""

    # Get app categories
    $categoriesUri = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($App.ID)/categories"
    $Category = Invoke-MgGraphRequest -Method GET -Uri $categoriesUri -ErrorAction Stop

    # Get list of assignments for the app
    foreach ($assignment in $App.assignments) { 
        $MgID = $assignment.target.groupId
        if ($MgID) { 
            $GroupMgData = (Get-MgGroup -Filter "Id eq '$MgID'") 
        }

        If ($GroupDisplayName) {
            $GroupDisplayName = $GroupDisplayName + " ; " + $GroupMgData.DisplayName
            $GroupIdAssignment = $GroupIdAssignment + " ; " + $assignment.target.groupId
            $GroupIntent = $GroupIntent + " ; " + $assignment.intent
            $notifications = $notifications + " ; " + $assignment.settings.notifications
        } Else {
            $GroupDisplayName = $GroupMgData.DisplayName
            $GroupIdAssignment = $assignment.target.groupId
            $GroupIntent = $assignment.intent
        }
    }                                                                                                                                                                                              

    # Get detection rules based on the app detection type
    $datatype = $App.'@odata.type'
    if ($datatype) { $splittype = $datatype.Split(".") }
 
    $detectiontype = $App.detectionRules.'@odata.type'
    if ($detectiontype) { $splitdetectiontype = $detectiontype.Split(".") }

    # Handle different types of detection rules
    If ($splitdetectiontype[-1] -eq "win32LobAppProductCodeDetection") {
        $win32LobApp = "ProductCode: " +$App.detectionRules.productCode + " ; ProductVersion: " +$App.detectionRules.productVersion + " ; ProductVersionOperator: " +$App.detectionRules.productVersionOperator
    }

    If ($splitdetectiontype[-1] -eq "win32LobAppPowerShellScriptDetection") {
        $win32LobApp = "ScriptContent: " +$App.detectionRules.scriptContent + " ; RunAs32Bit: " +$App.detectionRules.runAs32Bit + " ; EnforceSignatureCheck: " +$App.detectionRules.enforceSignatureCheck
    }

    If ($splitdetectiontype[-1] -eq "win32LobAppFileSystemDetection") {
        $win32LobApp = "Path: " +$App.detectionRules.path + " ; FileOrFolderName: " +$App.detectionRules.fileOrFolderName + " ; DetectionValue: " +$App.detectionRules.detectionValue + " ; Operator: " +$App.detectionRules.operator + " ; DetectionType: " +$App.detectionRules.detectionType + " ; DetectionValue: " +$App.detectionRules.detectionValue + " ; Check32BitOn64System: " +$App.detectionRules.check32BitOn64System
    }

    If ($splitdetectiontype[-1] -eq "win32LobAppRegistryDetection") {
        $win32LobApp = "KeyPath: " +$App.detectionRules.keyPath + " ; DetectionValue: " +$App.detectionRules.detectionValue + " ; ValueName: " +$App.detectionRules.valueName + " ; Operator: " +$App.detectionRules.operator + " ; DetectionType: " +$App.detectionRules.detectionType + " ; Check32BitOn64System: " +$App.detectionRules.check32BitOn64System
    }

    # Create a report entry for the app
    $ReportLine  = [PSCustomObject] @{                                                                                                                                     

        DISPLAYNAME = $App.displayName
        TYPE = $splittype[-1]
        PUBLISHER = $App.publisher
        DISPLAYVERSION = $App.displayVersion
        DESCRIPTION = $App.description
        OWNER = $App.owner
        NOTES = $App.notes
        LARGEICON = $App.largeIcon
        INFORMATIONURL = $App.informationUrl
        PRIVACYINFORMATIONURL = $App.privacyInformationUrl
        CREATEDDATETIME = $App.createdDateTime
        LASTMODIFIEDDATETIME = $App.lastModifiedDateTime
        APPLICABLEDEVICETYPE = $App.applicableDeviceType
        ID = $App.id
        CATEGORY = $Category.value.displayName
        PUBLISHINGSTATE = $App.publishingState
        PACKAGEIDENTIFIER = $App.packageIdentifier
        BUNDLID = $App.bundleId
        ISASSIGNED = $App.isAssigned
        FILENAME = $App.fileName
        COMMITTEDCONTENTVERSION = $App.committedContentVersion
        SETUPFILEPATH = $App.setupFilePath
        INSTALLCOMMANDLINE = $App.installCommandLine
        UNINSTALLCOMMANDLINE = $App.uninstallCommandLine
        ALLOWAVAILABLEUNINSTALL = $App.allowAvailableUninstall
        SIZE = $App.size
        DEVICERESTARTBEHAVIOR = $App.installExperience.deviceRestartBehavior
        MAXRUNTIMEMINUTES = $App.installExperience.maxRunTimeInMinutes
        RUNASACCOUNT = $App.installExperience.runAsAccount
        SUPERSEDINGAPPCOUNT = $App.supersedingAppCount
        MINIMUMSUPPORTEDWINDOWSRELEASE = $App.minimumSupportedWindowsRelease
        MINIMUMCPUSPEEDINMHZ = $App.minimumCpuSpeedInMHz
        MINIMUMMEMORYINMB   = $App.minimumMemoryInMB  
        APPLICABLEARCHITECTURES = $App.applicableArchitectures
        MINIMUMFREEDISKSPACEINMB = $App.minimumFreeDiskSpaceInMB
        MINIMUMNUMBEROFPROCESSORS = $App.minimumNumberOfProcessors
        DEVELOPER = $App.developer
        ISFEATURED = $App.isFeatured
        UPLOADSTATE = $App.uploadState
        DEPENDENTAPPCOUNT = $App.dependentAppCount
        SUPERSEDEDAPPCOUNT = $App.supersededAppCount
        DETECTIONTYPEAPP = $splitdetectiontype[-1] 
        DETECTIONTRULES = $win32LobApp
        ASSIGNMENTINTENTDISPLAYNAME = $GroupDisplayName
        ASSIGNMENTINTENTID = $GroupIdAssignment
        ASSIGNMENTINTENT = $GroupIntent
        ASSIGNMENTNOTIFICATIONS = $notifications

        }  

    # Add the report line to the report
    $Report.Add($ReportLine)   
}

# Export the report to a CSV file
$Report | Export-Excel $CSVfile 

# Upload the CSV file to Azure Blob Storage
$FileBlob = "CATALOG_$(get-date -f yyyy-MM-dd).csv"
$Context = New-AzStorageContext -StorageAccountName "YOUR_STORAGE_ACCOUNT_NAME" -StorageAccountKey "YOUR_STORAGE_ACCOUNT_KEY"
Set-AzStorageBlobContent -File "$PSScriptRoot\CATALOG.csv" -Container "wp20intunebackups" -Blob $FileBlob -Context $Context
