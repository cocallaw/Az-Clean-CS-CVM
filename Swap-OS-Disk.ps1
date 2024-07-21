#Get the Broken VM and verify it is deallocated
$vm = Get-AzVM -ResourceGroupName $ResourceGroup -Name $VMName
Stop-AzVM -ResourceGroupName $vm.ResourceGroupName -Name $vm.Name -Force

# Get the new disk that you want to swap in
$disk = Get-AzDisk -ResourceGroupName myResourceGroup -Name newDisk

# Set the VM configuration to point to the new disk  
Set-AzVMOSDisk -VM $vm -ManagedDiskId $disk.Id -Name $disk.Name

# Update the VM with the new OS disk
Update-AzVM -ResourceGroupName myResourceGroup -VM $vm

# Start the VM
Start-AzVM -Name $vm.Name -ResourceGroupName myResourceGroup

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