#region parameters
param(
    [Parameter(Mandatory)]
    [string]$VMListFilePath,
    [Parameter(Mandatory)]
    [string]$AVDRGName,
    [Parameter(Mandatory)]
    [string]$RescueVMName,
    [Parameter(Mandatory)]
    [string]$BlankDiskName
)
#end region parameters
#region functions
function Swap-Disk-To-Rescue {
    param (
        [Parameter(Mandatory)]
        [string]$ResourceGroup,
        [Parameter(Mandatory)]
        [string]$VMName,
        [Parameter(Mandatory)]
        [string]$RescueVMName,
        [Parameter(Mandatory)]
        [string]$BlankDiskID
    )
    #Get the properties of the OS disk on the bad VM
    $aDiskID = (get-azvm -ResourceGroupName $ResourceGroup -name $VMName).StorageProfile.OsDisk.ManagedDisk.id
    Write-Host "Swapping Disk Blank Disk in for $aDiskID on $VMName"
    $bdName = ($BlankDiskID -replace '.*\/', '')
    Swap-OSDisk -ResourceGroup $ResourceGroup -VMName $VMName -NewDisk $bdName
    Write-Host "Mounting $aDiskID as a data disk on $RescueVMName"
    $aDiskName = ($aDiskID -replace '.*\/', '')
    Mount-OSasDataDisk -ResourceGroup $ResourceGroup -VMName $RescueVMName -NewDataDisk $aDiskName
    Write-Host "Disk $aDiskID is now mounted as a data disk on $RescueVMName"
    return $aDiskID
}
function Swap-Disk-From-Rescue {
    param (
        [Parameter(Mandatory)]
        [string]$ResourceGroup,
        [Parameter(Mandatory)]
        [string]$VMName,
        [Parameter(Mandatory)]
        [string]$aDiskID,
        [Parameter(Mandatory)]
        [string]$RescueVMName
    )
    UnMount-OsasDataDisk -ResourceGroup $ResourceGroup -VMName $RescueVMName -DataDisk $aDiskID
    $aDiskName = ($aDiskID -replace '.*\/', '')
    Swap-OSDisk -ResourceGroup $ResourceGroup -VMName $VMName -NewDisk $aDiskName
}
function Swap-OSDisk {
    param (
        [Parameter(Mandatory)]
        [string]$ResourceGroup,
        [Parameter(Mandatory)]
        [string]$VMName,
        [Parameter(Mandatory)]
        [string]$NewDisk
    )
    $vm = Get-AzVM -ResourceGroupName $ResourceGroup -Name $VMName
    Write-Host "Stopping $VMName"
    Stop-AzVM -ResourceGroupName $vm.ResourceGroupName -Name $vm.Name -Force
    $disk = Get-AzDisk -ResourceGroupName $ResourceGroup -Name $NewDisk
    Write-Host "Setting $NewDisk as the OS disk for $VMName"
    Set-AzVMOSDisk -VM $vm -ManagedDiskId $disk.Id -Name $disk.Name
    Write-Host "Updating $VMName with the new OS disk"
    Update-AzVM -ResourceGroupName $ResourceGroup -VM $vm
}
function Mount-OSasDataDisk {
    param (
        [Parameter(Mandatory)]
        [string]$ResourceGroup,
        [Parameter(Mandatory)]
        [string]$VMName,
        [Parameter(Mandatory)]
        [string]$NewDataDisk
    )
    $disk = Get-AzDisk -ResourceGroupName $ResourceGroup -Name $NewDataDisk
    $vm = Get-AzVM -ResourceGroupName $ResourceGroup -Name $VMName
    $vm = Add-AzVMDataDisk -CreateOption Attach -Lun 0 -VM $vm -ManagedDiskId $disk.Id
    Update-AzVM -VM $vm -ResourceGroupName $ResourceGroup
}
function UnMount-OsasDataDisk {
    param (
        [Parameter(Mandatory)]
        [string]$ResourceGroup,
        [Parameter(Mandatory)]
        [string]$VMName,
        [Parameter(Mandatory)]
        [string]$DataDiskID
    )
    $vm = Get-AzVM -ResourceGroupName $ResourceGroup -Name $VMName
    $ddname = ($DataDiskID -replace '.*\/', '')
    Remove-AzVMDataDisk -VM $vm -Name $ddname
    Update-AzVM -VM $vm -ResourceGroupName $ResourceGroup
}
function Get-BLKeys {
    param (
        [Parameter(Mandatory)]
        [string]$VMLPath
    )
    $vmNames = Get-content -Path $VMLPath
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
    return $deviceRecoveryKeys
}
#end region functions
#region variables
$OperationsScriptPath = ".\Clean-CS-CVM.ps1"
#end region variables
#region main
Write-Host "Connecting to Microsoft Graph with the necessary scopes"
try {
    Connect-MgGraph -Scopes "Device.Read.All", "BitLockerKey.Read.All"
}
catch {
    Write-Host "Failed to connect to Microsoft Graph with the necessary scopes"
    exit
}
Write-Host "Getting BitLocker keys for VMs in file $VMListFilePath"
[array]$BLKeys = Get-BLKeys -VMLPath $VMListFilePath
Write-Host "Getting Blank Managed Disk Info for Rescue Swap"
try {
    $bdRID = (get-azdisk -ResourceGroupName $AVDRGName -Name $BlankDiskName).Id
}
catch {
    Write-Host "Failed to get Blank Managed Disk Info for Rescue Swap"
    exit
}
Write-Host "Using Blank Managed Disk ID: $bdRID"
$aDisk = $null
foreach ($BLK in $BLKeys) {
    Write-Host "Starting work on $($BLK.DeviceName)"
    $aDisk = Swap-Disk-To-Rescue -ResourceGroup $AVDRGName -VMName $BLK.DeviceName -RescueVMName $RescueVMName -BlankDiskID $bdRID
    $s = Invoke-AzVMRunCommand -ResourceGroupName $AVDRGName -VMName $RescueVMName -CommandId 'RunPowerShellScript' -ScriptPath $OperationsScriptPath -Parameter @{BLRecoveryKey = $BLK.RecoveryKey }
    $s.Value[0].Message
    Swap-Disk-From-Rescue -ResourceGroup $AVDRGName -VMName $VMName -aDiskID $aDisk -RescueVMName $RescueVMName
}
#end region main