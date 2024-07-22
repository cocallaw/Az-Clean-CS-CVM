# Install the Microsoft Graph PowerShell module
#Install-Module Microsoft.Graph -Scope CurrentUser
 
# Connect to Microsoft Graph with the necessary scopes
Connect-MgGraph -Scopes "Device.Read.All", "BitLockerKey.Read.All"
 
$vmNames = Get-content -Path "C:\Users\NAME\Desktop\VMs.txt"
 
$devices = @()
foreach ($vmName in $vmNames) {
    $devices += Get-MgDevice -Filter "displayName eq '$vmName'"
}
 
# Initialize an array to store device recovery keys
$deviceRecoveryKeys = @()
 
# Loop through each device and retrieve its BitLocker recovery keys
foreach ($device in $devices) {
    $recoveryKeys = Get-MgInformationProtectionBitlockerRecoveryKey -Filter "deviceId eq '$($device.DeviceId)'"
    foreach ($key in $recoveryKeys) {
        $deviceRecoveryKeys += [PSCustomObject]@{
            DeviceName    = $device.DisplayName
            DeviceId      = $device.DeviceId
            RecoveryKeyId = $key.Id
            RecoveryKey   = (Get-MgInformationProtectionBitlockerRecoveryKey -BitlockerRecoveryKeyId $key.Id -Property key).key
        }
    }
}
 
# Output the device recovery keys
$deviceRecoveryKeys