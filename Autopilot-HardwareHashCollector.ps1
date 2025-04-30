<#
.SYNOPSIS
Remediation Script to Retrieve and Upload Windows AutoPilot Hardware Hash
.DESCRIPTION
This script collects the hardware hash and related details from a Windows machine 
to support Windows AutoPilot deployment. It logs the process and uploads the data 
to a remote blob storage endpoint.
.AUTHOR
Rui Saloio
.VERSION
1.0
.LASTUPDATED
2024-04-8
#>

$RemediationName = "Windows - Get Hardware Hash"
$LogName = "REMEDIATION-REM_$RemediationName"

# Logging function
Function Write-Log {
    Param ([string]$LogString)
    $ScriptLogPath = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\$LogName.log"
    $Timestamp = "[{0:MM/dd/yy} {0:HH:mm:ss}]" -f (Get-Date)
    $LogMessage = "$Timestamp $LogString"
    $LogMessage | Tee-Object -Append $ScriptLogPath
}

# Start logging
$ScriptLogPath = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\$LogName.log"
"=================================================================================" | Tee-Object -Append $ScriptLogPath
Write-Log "Starting remediation script: '$LogName'."

# Get serial number and define output CSV file
$SerialNumber = (Get-WmiObject -Class Win32_BIOS).SerialNumber
$LogCSV = "$SerialNumber" + "_" + $env:COMPUTERNAME + "_HardwareHash.csv"

# Function to collect AutoPilot info
Function Get-WindowsAutoPilotInfo {
    [CmdletBinding()]
    Param(
        [Parameter(ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [Alias("DNSHostName", "ComputerName", "Computer")]
        [String[]]$Name = @($env:ComputerName),

        [String]$OutputFile = "", 
        [Switch]$Append = $false,
        [System.Management.Automation.PSCredential]$Credential = $null,
        [Switch]$Partner = $false,
        [Switch]$Force = $false
    )

    Begin { $computers = @() }

    Process {
        foreach ($comp in $Name) {
            $bad = $false
            Write-Verbose "Processing $comp"

            $serial = (Get-WmiObject -ComputerName $comp -Credential $Credential -Class Win32_BIOS).SerialNumber
            $devDetail = (Get-WmiObject -ComputerName $comp -Credential $Credential -Namespace root/cimv2/mdm/dmmap -Class MDM_DevDetail_Ext01 -Filter "InstanceID='Ext' AND ParentID='./DevDetail'")
            
            if ($devDetail -and (-not $Force)) {
                $hash = $devDetail.DeviceHardwareData
            } else {
                $bad = $true
                $hash = ""
            }

            if ($bad -or $Force) {
                $cs = Get-WmiObject -ComputerName $comp -Credential $Credential -Class Win32_ComputerSystem
                $make = $cs.Manufacturer.Trim()
                $model = $cs.Model.Trim()
                if ($Partner) { $bad = $false }
            } else {
                $make = ""
                $model = ""
            }

            $product = ""  # Product ID is not typically available

            $entry = if ($Partner) {
                [PSCustomObject]@{
                    "Device Serial Number" = $serial
                    "Windows Product ID"   = $product
                    "Hardware Hash"        = $hash
                    "Manufacturer name"    = $make
                    "Device model"         = $model
                }
            } else {
                [PSCustomObject]@{
                    "Device Serial Number" = $serial
                    "Windows Product ID"   = $product
                    "Hardware Hash"        = $hash
                }
            }

            if ($bad) {
                Write-Error "Could not retrieve hardware hash from $comp"
            } elseif ($OutputFile -eq "") {
                $entry
            } else {
                $computers += $entry
            }
        }
    }

    End {
        if ($OutputFile -ne "") {
            if ($Append -and (Test-Path $OutputFile)) {
                $computers += Import-Csv -Path $OutputFile
            }

            $selectFields = if ($Partner) {
                "Device Serial Number", "Windows Product ID", "Hardware Hash", "Manufacturer name", "Device model"
            } else {
                "Device Serial Number", "Windows Product ID", "Hardware Hash"
            }

            $computers |
                Select-Object $selectFields |
                ConvertTo-Csv -NoTypeInformation |
                ForEach-Object { $_ -replace '"', '' } |
                Out-File $OutputFile
        }
    }
}

# Execute hardware hash collection
Get-WindowsAutoPilotInfo -OutputFile "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\$LogCSV"
$file = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\$LogCSV"
Write-Log "CSV file created at $file"

# Placeholder URI for public upload (Replace with secure URI or upload logic)
$uri = "<INSERT_SECURE_BLOB_URI_HERE>"

# Define headers for blob upload
$headers = @{
    'x-ms-blob-type' = 'BlockBlob'
}

# Upload CSV file
Invoke-RestMethod -Uri $uri -Method Put -Headers $headers -InFile $file
Write-Log "File $file uploaded to remote location."

Write-Log "Script '$LogName' completed successfully."
EXIT
