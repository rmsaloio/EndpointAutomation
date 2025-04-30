<#
.SYNOPSIS
Remediation Script to Delete Win32Apps Registry Keys for Intune Management Extension
.DESCRIPTION
This script removes invalid or orphaned registry keys under the IntuneManagementExtension\Win32Apps path.
It is typically used in remediation scenarios to clear remnants of failed app installations or configurations.
.AUTHOR
Rui Saloio
.VERSION
1.0
.LASTUPDATED
2024-06-06
#>

$RemediationName = "Windows - Delete IntuneManagementExtension Win32Apps Keys"
$LogName = "REMEDIATION-REM_$RemediationName"

# Logging function
Function Write-Log {
    Param ([string]$LogString)
    $LogPath = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\$LogName.log"
    $Timestamp = "[{0:MM/dd/yy} {0:HH:mm:ss}]" -f (Get-Date)
    $LogMessage = "$Timestamp $LogString"
    $LogMessage | Tee-Object -Append $LogPath
}

# Start of log
$ScriptLogPath = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\$LogName.log"
"=================================================================================" | Tee-Object -Append $ScriptLogPath
Write-Log "Starting remediation script: '$LogName'."

# Registry base path for Win32Apps keys
$baseRegistryPath = "HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\Win32Apps"

# Get all subkeys under the Win32Apps path
$subKeys = Get-ChildItem -Path $baseRegistryPath

# Filter keys that appear to be GUIDs (36 characters) but exclude a known placeholder GUID
$filteredKeys = $subKeys | Where-Object {
    $_.Name.Length -eq 110 -and
    $_.Name -ne "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\IntuneManagementExtension\Win32Apps\00000000-0000-0000-0000-000000000000"
}

# Log the keys to be removed
$filteredKeys | ForEach-Object { Write-Log "Key to remove: $($_.Name)" }

# Remove each filtered key
$filteredKeys | ForEach-Object {
    Write-Output $_

    # Convert full registry path to PowerShell-friendly format
    $removePath = $_.Name -replace "^HKEY_LOCAL_MACHINE", "HKLM:"
    
    # Delete the registry key and its subkeys
    Remove-Item -Path $removePath -Recurse -Force
}

Write-Log "Registry keys successfully removed."

# Restart the Intune Management Extension service to apply changes
$serviceName = "IntuneManagementExtension"
Restart-Service -Name $serviceName -Force
Write-Log "Service '$serviceName' restarted."

Write-Log "Script completed successfully."
EXIT
