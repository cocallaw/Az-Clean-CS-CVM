# Install the Microsoft Graph PowerShell module
#Install-Module Microsoft.Graph -Scope CurrentUser
Select-AzSubscription -Subscription ''
# Get VMs names
$resourceGroupName =
$hostPoolName =
$sessionHosts = Get-AzWvdSessionHost -ResourceGroupName $resourceGroupName -HostPoolName $hostPoolName
$unavailableHosts = $sessionHosts | Where-Object { $_.Status -eq "Unavailable" }
 
# Get the names of the session hosts
$sessionHostNames = $unavailableHosts | Select-Object -ExpandProperty Name
 
# Extract the part after the '/' character
$extractedNames = $sessionhostNames | ForEach-Object {
    $_.Split('/')[1]
}
 
$listNames = $extractedNames | ForEach-Object {
    "`"$_`""
}
 
# Join the names with commas
$formattedList = $listNames -join ", "
 
# Output the final list
#$formattedList
 
# Query Azure Resource Graph for VMs that are running and match the session host names
$query = @"
resources
| where type == 'microsoft.compute/virtualmachines'
| where name in ($formattedList)
| where properties.extended.instanceView.powerState.code == 'PowerState/running'
| project name, properties.extended.instanceView.powerState.code
"@
 
$runningVms = Search-AzGraph -Query $query
 
# Filter for running yet unavailable session hosts
$runningUnavailableHosts = $sessionHosts | Where-Object { $_.Status -eq "Unavailable" -and ($_.Name).Split('/')[-1] -in $runningVms.name }
 
# Extract the names of running yet unavailable VMs and store them in a list
$runningUnavailableVmNames = $runningUnavailableHosts | Select-Object -ExpandProperty Name
 
# Output the list of running yet unavailable VM names
#$runningUnavailableVmNames
 
# Extract the part after the '/' character
$vmNames = $runningUnavailableVmNames | ForEach-Object {
    $_.Split('/')[1]
}
 
# Connect to Microsoft Graph with the necessary scopes
Connect-MgGraph -Scopes "Device.Read.All", "BitLockerKey.Read.All"
 
$devices = @()
foreach ($vmName in $vmNames) {
    write-host $vmName
    $devices += Get-MgDevice -Filter "displayName eq '$vmName'"
}
#$device = Get-MgDevice -Filter "displayName eq '$vmName'"
 
# Initialize an array to store device recovery keys
$deviceRecoveryKeys = @()
 
# Loop through each device and retrieve its BitLocker recovery keys
foreach ($device in $devices) {
    $recoveryKeys = Get-MgInformationProtectionBitlockerRecoveryKey -Filter "deviceId eq '$($device.DeviceId)'"
    foreach ($key in $recoveryKeys) {
        $deviceRecoveryKeys += [PSCustomObject]@{
            DeviceName  = $device.DisplayName
            #DeviceId      = $device.DeviceId
            #RecoveryKeyId = $key.Id
            RecoveryKey = (Get-MgInformationProtectionBitlockerRecoveryKey -BitlockerRecoveryKeyId $key.Id -Property key).key
        }
    }
}
 
# Output the device recovery keys
$deviceRecoveryKeys