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
#get all the disks and if offline bring them online
$offlinedisks = get-disk | Where-Object { $_.OperationalStatus -eq 'Offline' }
ForEach ($disk in $offlinedisks) {
	Write-Host "Bringing disk $($disk.Number) online"
	$disk | Set-Disk -IsOffline $false
}
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
$bitlockerStatus = Get-BitLockerVolume -MountPoint $LockedDrive.MountPoint
while ($bitlockerStatus.VolumeStatus -ne "FullyDecrypted") {
	Write-Host "Waiting for BitLocker to decrypt..."
	Start-Sleep -Seconds 10
	$bitlockerStatus = Get-BitLockerVolume -MountPoint $LockedDrive.MountPoint
}
Write-Host "BitLocker has been decrypted"
Write-Host "Bringing Disk $($LockedDrive.DriveLetter) offline"
# Define the drive letter
$driveLetter = $LockedDrive.DriveLetter
# Get the disk number associated with the drive letter
$diskNumber = (Get-Partition | Where-Object DriveLetter -eq $driveLetter.Substring(0,1)).DiskNumber
# Bring the disk offline
Set-Disk -Number $diskNumber -IsOffline $true 

Start-Sleep -Seconds 5

#end region bitlocker-decrypt
#endregion main


