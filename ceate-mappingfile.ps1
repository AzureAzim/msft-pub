#This script creates the mapping file used for the Exchange import service for importing PSTs into mailboxes


    $users = Get-ChildItem -Directory -Exclude "Completed"
    $MappingFileData = New-Object psobject
    $Mappingfile = @()
    $date = (Get-Date -Format "mm-dd-yy" ).ToString()
    foreach ($user in $users){
    $archives = get-ChildItem $user | get-ChildItem
    foreach ($archive in $archives) {
    $archives = get-ChildItem $user - | get-ChildItem
    $Workload = "Exchange"
    #$Filepath = "$user.Name\" #$user | Get-ChildItem | Resolve-Path -Relative #problem, always outs as system.object[] try manual username "$samname\"
    $Name = (($archive).Name).ToString()
    $samname = (($user).Name).ToString()
    $Filepath = "$samname\"
    $Mailbox = "$samname@domain.com"
    $isArchive = "True"
    $TargetRoot = "$Name"

    write-host $filepath
    $MappingFileData = New-Object psobject
    $MappingFileData | add-member -MemberType NoteProperty -Name Workload -Value $Workload 
    $MappingFileData | add-member -MemberType NoteProperty -Name FilePath -Value ($Filepath).ToString()
    $MappingFileData | add-member -MemberType NoteProperty -Name Name -Value $Name
    $MappingFileData | add-member -MemberType NoteProperty -Name Mailbox -Value $Mailbox
    $MappingFileData | add-member -MemberType NoteProperty -Name IsArchive -Value $isArchive
    $MappingFileData | add-member -MemberType NoteProperty -Name TargetRoot -Value $TargetRoot
    $MappingFileData | add-member -MemberType NoteProperty -Name ContentCodePage -Value $null
    $MappingFileData | add-member -MemberType NoteProperty -Name SPFileContainer -Value $null
    $MappingFileData | add-member -MemberType NoteProperty -Name SPManifestContainer -Value $null
    $MappingFileData | add-member -MemberType NoteProperty -Name SPSIteUrl -Value $null
    $MappingFile += $MappingFileData 
        }
    }
    $mappingfile | export-csv  "$date.csv" -NoTypeInformation
