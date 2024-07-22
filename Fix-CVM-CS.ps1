#region parameters
param(
    [Parameter(Mandatory)]
    [string]$VMListFilePath

)
#end region parameters
#region functions
function Swap-OS-Disk {
    param (
        [string]$ResourceGroup,
        [string]$VMName,
        [string]$NewDisk
    )
    $vm = Get-AzVM -ResourceGroupName $ResourceGroup -Name $VMName
    Stop-AzVM -ResourceGroupName $vm.ResourceGroupName -Name $vm.Name -Force
    $disk = Get-AzDisk -ResourceGroupName $ResourceGroup -Name $NewDisk
    Set-AzVMOSDisk -VM $vm -ManagedDiskId $disk.Id -Name $disk.Name
    Update-AzVM -ResourceGroupName myResourceGroup -VM $vm
}
function Get-BLKeys {
    param {
        [Parameter(Mandatory)]
        [string]$VMLPath
    }
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
Connect-MgGraph -Scopes "Device.Read.All", "BitLockerKey.Read.All"
Write-Host "Getting BitLocker keys for VMs in file $VMListFilePath"
[array]$BLKeys = Get-BLKeys VMLPath $VMListFilePath


$s = Invoke-AzVMRunCommand -ResourceGroupName <RGNAME> -VMName <VMNAME> -CommandId 'RunPowerShellScript' -ScriptPath $OperationsScriptPath -Parameter @{BLRecoveryKey = $Token }
$s.Value[0].Message

#end region main