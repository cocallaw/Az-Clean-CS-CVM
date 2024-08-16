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
#endregion parameters
#region functions
function Move-DiskToRescueVM {
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
    #FUNCTION INFO: Get the OS disk ID, Swap the OS disk with blank disk, Mount the original OS disk as a data disk on the rescue VM, return the original OS disk ID
    $origDiskID = (get-azvm -ResourceGroupName $ResourceGroup -name $VMName).StorageProfile.OsDisk.ManagedDisk.id
    Write-Host "Swapping Disk Blank Disk in for $origDiskID on $VMName"
    $bdName = ($BlankDiskID -replace '.*\/', '')
    Switch-OSDisk -ResourceGroup $ResourceGroup -VMName $VMName -NewDisk $bdName
    Write-Host "Mounting $origDiskID as a data disk on $RescueVMName"
    $aDiskName = ($origDiskID -replace '.*\/', '')
    Mount-OSasDataDisk -ResourceGroup $ResourceGroup -VMName $RescueVMName -NewDataDisk $aDiskName
    Write-Host "Disk $origDiskID is now mounted as a data disk on $RescueVMName"
    return $origDiskID
}
function Move-DiskFromRescuetoOriginal {
    param (
        [Parameter(Mandatory)]
        [string]$ResourceGroup,
        [Parameter(Mandatory)]
        [string]$VMName,
        [Parameter(Mandatory)]
        [string]$OrigDiskID,
        [Parameter(Mandatory)]
        [string]$RescueVMName
    )
    #FUNCTION INFO: Dismount the OS disk from the rescue VM, Swap the OS disk back to the original VM replacing the blank disk
    Dismount-OSasDataDisk -ResourceGroup $ResourceGroup -VMName $RescueVMName -DataDisk $OrigDiskID
    $aDiskName = ($OrigDiskID -replace '.*\/', '')
    Switch-OSDisk -ResourceGroup $ResourceGroup -VMName $VMName -NewDisk $aDiskName
}
function Switch-OSDisk {
    param (
        [Parameter(Mandatory)]
        [string]$ResourceGroup,
        [Parameter(Mandatory)]
        [string]$VMName,
        [Parameter(Mandatory)]
        [string]$NewDisk
    )
    #FUNCTION INFO: Stop the VM, Set the new disk as the OS disk, Update the VM, Start the VM
    $switchVM = Get-AzVM -ResourceGroupName $ResourceGroup -Name $VMName
    Write-Host "Stopping $VMName"
    Stop-AzVM -ResourceGroupName $switchVM.ResourceGroupName -Name $switchVM.Name -Force
    $disk = Get-AzDisk -ResourceGroupName $ResourceGroup -Name $NewDisk
    Write-Host "Setting $NewDisk as the OS disk for $VMName"
    Set-AzVMOSDisk -VM $switchVM -ManagedDiskId $disk.Id -Name $disk.Name
    Write-Host "Updating $VMName with the new OS disk"
    Update-AzVM -ResourceGroupName $ResourceGroup -VM $switchVM
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
function Dismount-OSasDataDisk {
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
function Get-BLRecoveryKeys {
    param (
        [Parameter(Mandatory)]
        [string]$VMListPath
    )
    #FUNCTION INFO: Get BitLocker Recovery Keys for VMs names provided in a txt file, return an array of objects with DeviceName, DeviceId, RecoveryKeyId, and RecoveryKey
    $vmNames = Get-content -Path $VMListPath
    $devices = @()
    foreach ($vmName in $vmNames) {
        $devices += Get-MgDevice -Filter "displayName eq '$vmName'"
    }
    $deviceRecoveryKeys = @()
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
try {
    [array]$BLKeys = Get-BLRecoveryKeys -VMListPath $VMListFilePath
}
catch {
    Write-Host "Failed to get BitLocker keys for VMs in file $VMListFilePath"
    exit
}
Write-Host "Getting Blank Managed Disk Info for Rescue Swap"
try {
    $bdRID = (get-azdisk -ResourceGroupName $AVDRGName -Name $BlankDiskName).Id
    Write-Host "Using Blank Managed Disk ID: $bdRID"
}
catch {
    Write-Host "Failed to get Blank Managed Disk Info for Rescue Swap"
    exit
}
$aDisk = $null
foreach ($BLK in $BLKeys) {
    Write-Host "Starting work on $($BLK.DeviceName)"
    $OriginalDisk = Move-DiskToRescueVM -ResourceGroup $AVDRGName -VMName $BLK.DeviceName -RescueVMName $RescueVMName -BlankDiskID $bdRID
    Invoke-AzVMRunCommand -ResourceGroupName $AVDRGName -VMName $RescueVMName -CommandId 'RunPowerShellScript' -ScriptPath $OperationsScriptPath -Parameter @{BLRecoveryKey = $BLK.RecoveryKey }
    Move-DiskFromRescuetoOriginal -ResourceGroup $AVDRGName -VMName $BLK.DeviceName -OrigDiskID [string]$OriginalDisk -RescueVMName $RescueVMName
}
#end region main