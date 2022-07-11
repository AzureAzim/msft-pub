#Requires -Modules Microsoft.graph
#CODE IS IN DRAFT
$ManagedDevices = Get-MgDeviceManagementManagedDevice -All -ErrorAction Stop -ErrorVariable GraphError
$Bitlockerreport = @()
foreach ($device in $ManagedDevices) {
    #var each data point
    $devicename = $device.deviceName
    $deviceid = $device.azureADDeviceId
    $deviceenrollmenttype = $device.deviceenrollmenttype
    $EnrolledDateTime = $device.EnrolledDateTime
    $LastSyncDateTime = $device.LastSyncDateTime
    $JoinType = $device.JoinType
    $IsEncrypted = $device.IsEncrypted
    $UserPrincipalName = $device.UserPrincipalName

    #collect keys and string them as keys are often multi valued
    $filter = "Deviceid eq " + "'" + $deviceid + "'"
    $keys = Get-MgInformationProtectionBitlockerRecoveryKey -Filter $filter
    $KeyInput = ""
        foreach ($key in $keys) {
            $keyid = $key.id
            $keyinput += ("$keyid" + ";")
        }
        $Keyoutput = $KeyInput -join ";"
    #Table each data point

        $DeviceItem = New-Object PSObject 
        $DeviceItem | Add-member -Type NoteProperty -Name 'DeviceName' -Value $devicename
        $DeviceItem | Add-member -Type NoteProperty -Name 'DeviceEnrollmentType' -Value $deviceenrollmenttype
        $DeviceItem | Add-member -Type NoteProperty -Name 'EnrolledDate' -Value $EnrolledDateTime
        $DeviceItem | Add-member -Type NoteProperty -Name 'LastCheckIn' -Value $LastSyncDateTime
        $DeviceItem | Add-member -Type NoteProperty -Name 'JoinType' -Value $JoinType
        $DeviceItem | Add-member -Type NoteProperty -Name 'DeviceID' -Value $deviceid
        $DeviceItem | Add-member -Type NoteProperty -Name 'IsEncrypted' -Value $IsEncrypted
        $DeviceItem | Add-member -Type NoteProperty -Name 'KeyIDs' -Value $Keyoutput
        $DeviceItem | Add-member -Type NoteProperty -Name 'Keys' -Value $keys
    $Bitlockerreport += $Deviceitem

} 
$Bitlockerreport
