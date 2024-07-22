# Az-Clean-CS-CVM

To use these scripts you need:
- Az PowerShell 
- Microsoft Graph PowerShell (with scopes "Device.Read.All", "BitLockerKey.Read.All" )

./Fix-CVM-CS.ps1 -VMListFilePath ./vmlist.txt -AVDRGName RGNAME -RescueVMName RESCUEVMNNAME -BlankDiskName BLANKDISKNAME
