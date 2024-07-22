param(
	[Parameter(Mandatory)]
	[string]$BLRecoveryKey
)
#region functions
function Get-Disk-Partitions() {
	$partitionlist = @()
	$disklist = get-wmiobject Win32_diskdrive | Where-Object { $_.model -like 'Microsoft Virtual Disk' } 
	ForEach ($disk in $disklist) {
		$diskID = $disk.index
		$command = @"
		select disk $diskID
		online disk noerr
"@
		$command | diskpart | out-null

		$partitionlist += Get-Partition -DiskNumber $diskID
	}
	return $partitionlist
}
#endregion functions
#region main
#region bitlocker-unlock
$LockedDrive = Get-BitLockerVolume | Where-Object { $_.LockStatus -eq 'Locked' }
Unlock-BitLocker -MountPoint $LockedDrive.MountPoint -RecoveryPassword $BLRecoveryKey
#end region bitlocker-unlock
#region croudstrike
$partitionlist = Get-Disk-Partitions
forEach ( $partition in $partitionlist ) {
	if ($partition.DriveLetter -ne "C") {
		$driveLetter = ($partition.DriveLetter + ":")
		$corruptFiles = "$driveLetter\Windows\System32\drivers\CrowdStrike\C-00000291*.sys"
	
		if (Test-Path -Path $corruptFiles) {
			Write-Host "Found crowdstrike files to cleanup, removing..."
			Remove-Item $corruptFiles
			$actionTaken = $true
		}
	}
}
if ($actionTaken) {
	Write-Host "Successfully cleaned up crowdstrike files"
}
else {
	Write-Host "No bad crowdstrike files found"
}
#end region croudstrike
#region bitlocker-decrypt
Write-Host "Disabling BitLocker on $($LockedDrive.MountPoint)"
Disable-BitLocker -MountPoint $LockedDrive.MountPoint

# TODO - Wait for BitLocker to decrypt

#end region bitlocker-decrypt
#endregion main


