<# 
.SYNOPSIS
Checks Windows Recovery Environment health and optionally replaces WinRE with a known-good image from Windows installation media.

.DESCRIPTION
This script audits the local Windows Recovery Environment (WinRE), then optionally replaces the current Winre.wim with a known-good Winre.wim extracted from a Microsoft Windows ISO.

Preferred source:
  - A Windows ISO on a local path or UNC path that contains sources\install.wim or sources\install.esd.

Alternate source:
  - A direct path to a known-good Winre.wim.

Split WIM/SWM media is intentionally not used by default. If an ISO only contains install.swm, provide a direct Winre.wim instead or rebuild the media with a single install.wim/esd.

.EXAMPLE
.\Repair-WinRE.ps1 -SourceIsoPath "\\server\share\Win11_24H2.iso"

Runs health checks, prompts whether to replace WinRE, extracts Winre.wim from the ISO, replaces local WinRE, and re-enables it.

.EXAMPLE
.\Repair-WinRE.ps1 -SourceIsoPath "\\server\share\Win11_24H2.iso" -ImageIndex 6 -Repair -Force

Runs non-interactively using image index 6 and replaces WinRE without prompting.

.EXAMPLE
.\Repair-WinRE.ps1 -SourceWinReWimPath "\\server\share\known-good\winre.wim" -Repair

Uses a known-good Winre.wim directly instead of extracting from an ISO.

.EXAMPLE
.\Repair-WinRE.ps1 -SourceIsoPath "\\server\share\Win11_24H2.iso" -ImageIndex 6 -ManagePartition -Repair

Reuses or creates a dedicated Windows RE partition, copies Winre.wim to Recovery\WindowsRE, and registers WinRE there.

.EXAMPLE
.\Repair-WinRE.ps1 -SourceIsoPath "\\server\share\Win11_24H2.iso" -ImageIndex 6 -ManagePartition -RecreateRecoveryPartition -Repair -Force

Deletes existing recovery partition(s) on the OS disk, creates a new recovery partition, and repairs WinRE without prompting.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(ParameterSetName = 'Iso')]
    [ValidateNotNullOrEmpty()]
    [string]$SourceIsoPath,

    [Parameter(ParameterSetName = 'WinReWim')]
    [ValidateNotNullOrEmpty()]
    [string]$SourceWinReWimPath,

    [Parameter()]
    [ValidateRange(1, 100)]
    [int]$ImageIndex = 1,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$TargetWinRePath = "$env:SystemRoot\System32\Recovery",

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ScratchPath = "$env:SystemDrive\WinRE-Repair",

    [Parameter()]
    [switch]$ManagePartition,

    [Parameter()]
    [switch]$RecreateRecoveryPartition,

    [Parameter()]
    [ValidateRange(750, 4096)]
    [int]$RecoveryPartitionSizeMB = 1024,

    [Parameter()]
    [ValidateRange(100, 2048)]
    [int]$MinimumRecoveryFreeMB = 250,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$RecoveryPartitionLabel = 'Windows RE tools',

    [Parameter()]
    [switch]$Repair,

    [Parameter()]
    [switch]$Force,

    [Parameter()]
    [switch]$KeepMounted
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$WindowsReGptType = 'de94bba4-06d1-4d40-a16a-bfd50179d6ac'
$WindowsReGptAttributes = '0x8000000000000001'
$WindowsReMbrType = '27'

function Write-Section {
    param([Parameter(Mandatory = $true)][string]$Title)
    Write-Host ''
    Write-Host "=== $Title ===" -ForegroundColor Cyan
}

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Run this script from an elevated PowerShell session.'
    }
}

function Invoke-Native {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [switch]$IgnoreExitCode
    )

    $output = & $FilePath @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    if (($exitCode -ne 0) -and (-not $IgnoreExitCode)) {
        throw "$FilePath $($Arguments -join ' ') failed with exit code $exitCode.`n$($output -join [Environment]::NewLine)"
    }

    [pscustomobject]@{
        ExitCode = $exitCode
        Output   = $output
    }
}

function Get-ReAgentInfo {
    $result = Invoke-Native -FilePath reagentc.exe -Arguments @('/info') -IgnoreExitCode
    $text = $result.Output -join [Environment]::NewLine

    $enabled = $null
    if ($text -match 'Windows RE status:\s*(\w+)') {
        $enabled = $Matches[1]
    }

    $location = $null
    if ($text -match 'Windows RE location:\s*(.+)') {
        $location = $Matches[1].Trim()
    }

    [pscustomobject]@{
        ExitCode = $result.ExitCode
        Raw      = $text
        Status   = $enabled
        Location = $location
    }
}

function Get-LocalWinReImage {
    param([Parameter(Mandatory = $true)][string]$Path)

    $candidate = Join-Path $Path 'Winre.wim'
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        return (Get-Item -LiteralPath $candidate)
    }

    return $null
}

function Test-WimImage {
    param([Parameter(Mandatory = $true)][string]$Path)

    $result = Invoke-Native -FilePath dism.exe -Arguments @('/English', '/Get-WimInfo', "/WimFile:$Path") -IgnoreExitCode
    [pscustomobject]@{
        IsValid  = ($result.ExitCode -eq 0)
        ExitCode = $result.ExitCode
        Output   = ($result.Output -join [Environment]::NewLine)
    }
}

function Mount-SourceIso {
    param([Parameter(Mandatory = $true)][string]$IsoPath)

    if (-not (Test-Path -LiteralPath $IsoPath -PathType Leaf)) {
        throw "ISO not found: $IsoPath"
    }

    $image = Mount-DiskImage -ImagePath $IsoPath -PassThru
    $volume = $image | Get-Volume | Select-Object -First 1
    if (-not $volume -or -not $volume.DriveLetter) {
        throw "Mounted ISO but could not resolve a drive letter for $IsoPath"
    }

    [pscustomobject]@{
        ImagePath   = $IsoPath
        DriveRoot   = "$($volume.DriveLetter):\"
        DiskImage   = $image
        MountedHere = $true
    }
}

function Get-InstallImagePath {
    param([Parameter(Mandatory = $true)][string]$IsoRoot)

    $sources = Join-Path $IsoRoot 'sources'
    $installWim = Join-Path $sources 'install.wim'
    $installEsd = Join-Path $sources 'install.esd'
    $installSwm = Join-Path $sources 'install.swm'

    if (Test-Path -LiteralPath $installWim -PathType Leaf) {
        return $installWim
    }

    if (Test-Path -LiteralPath $installEsd -PathType Leaf) {
        return $installEsd
    }

    if (Test-Path -LiteralPath $installSwm -PathType Leaf) {
        throw "This ISO uses split SWM media ($installSwm). This script intentionally avoids SWM by default. Use an ISO with install.wim/install.esd, or pass -SourceWinReWimPath with a known-good Winre.wim."
    }

    throw "No install.wim or install.esd found under $sources"
}

function Show-InstallImageIndexes {
    param([Parameter(Mandatory = $true)][string]$InstallImagePath)

    Write-Section 'Available install image indexes'
    $info = Invoke-Native -FilePath dism.exe -Arguments @('/English', '/Get-WimInfo', "/WimFile:$InstallImagePath")
    $info.Output | ForEach-Object { Write-Host $_ }
}

function Extract-WinReFromInstallImage {
    param(
        [Parameter(Mandatory = $true)][string]$InstallImagePath,
        [Parameter(Mandatory = $true)][int]$Index,
        [Parameter(Mandatory = $true)][string]$WorkRoot
    )

    $imageToMount = $InstallImagePath
    $indexToMount = $Index
    if ([IO.Path]::GetExtension($InstallImagePath) -ieq '.esd') {
        $exportedWim = Join-Path $WorkRoot 'install.exported.wim'
        Write-Section 'Exporting install.esd image to temporary WIM'
        Invoke-Native -FilePath dism.exe -Arguments @(
            '/Export-Image',
            "/SourceImageFile:$InstallImagePath",
            "/SourceIndex:$Index",
            "/DestinationImageFile:$exportedWim",
            '/DestinationName:WinRE source',
            '/Compress:max',
            '/CheckIntegrity'
        ) | Out-Null

        $imageToMount = $exportedWim
        $indexToMount = 1
    }

    $mountPath = Join-Path $WorkRoot 'mount'
    $extractPath = Join-Path $WorkRoot 'extracted'
    New-Item -ItemType Directory -Path $mountPath, $extractPath -Force | Out-Null

    Write-Section 'Mounting install image'
    Invoke-Native -FilePath dism.exe -Arguments @('/Mount-Image', "/ImageFile:$imageToMount", "/Index:$indexToMount", "/MountDir:$mountPath", '/ReadOnly') | Out-Null

    try {
        $sourceWinRe = Join-Path $mountPath 'Windows\System32\Recovery\Winre.wim'
        if (-not (Test-Path -LiteralPath $sourceWinRe -PathType Leaf)) {
            throw "Mounted image does not contain Windows\System32\Recovery\Winre.wim. Check -ImageIndex."
        }

        $destination = Join-Path $extractPath 'Winre.wim'
        Copy-Item -LiteralPath $sourceWinRe -Destination $destination -Force
        return $destination
    }
    finally {
        if (-not $KeepMounted) {
            Write-Section 'Unmounting install image'
            Invoke-Native -FilePath dism.exe -Arguments @('/Unmount-Image', "/MountDir:$mountPath", '/Discard') -IgnoreExitCode | Out-Null
        }
    }
}

function Confirm-Repair {
    param([Parameter(Mandatory = $true)][string]$ReplacementPath)

    if ($Repair -and $Force) {
        return $true
    }

    Write-Host ''
    Write-Host "Replacement WinRE image: $ReplacementPath" -ForegroundColor Yellow
    if ($ManagePartition) {
        Write-Host "Target WinRE directory:   Managed recovery partition" -ForegroundColor Yellow
        Write-Host "Recovery partition size:  $RecoveryPartitionSizeMB MB" -ForegroundColor Yellow
    }
    else {
        Write-Host "Target WinRE directory:   $TargetWinRePath" -ForegroundColor Yellow
    }
    Write-Host ''
    $answer = Read-Host 'Replace the current WinRE image and re-register Windows Recovery Environment? Type YES to continue'
    return ($answer -eq 'YES')
}

function Backup-ExistingWinRe {
    param(
        [Parameter(Mandatory = $true)][string]$TargetPath,
        [Parameter(Mandatory = $true)][string]$WorkRoot
    )

    $existing = Get-LocalWinReImage -Path $TargetPath
    if (-not $existing) {
        return $null
    }

    $backupRoot = Join-Path $WorkRoot 'backup'
    New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backup = Join-Path $backupRoot "Winre.$stamp.wim"
    Copy-Item -LiteralPath $existing.FullName -Destination $backup -Force
    return $backup
}

function Install-WinReImage {
    param(
        [Parameter(Mandatory = $true)][string]$ReplacementPath,
        [Parameter(Mandatory = $true)][string]$TargetPath,
        [Parameter(Mandatory = $true)][string]$WorkRoot
    )

    $validation = Test-WimImage -Path $ReplacementPath
    if (-not $validation.IsValid) {
        throw "Replacement Winre.wim failed DISM validation.`n$($validation.Output)"
    }

    New-Item -ItemType Directory -Path $TargetPath -Force | Out-Null

    Write-Section 'Disabling Windows RE'
    Invoke-Native -FilePath reagentc.exe -Arguments @('/disable') -IgnoreExitCode | Out-Null

    $backup = Backup-ExistingWinRe -TargetPath $TargetPath -WorkRoot $WorkRoot
    if ($backup) {
        Write-Host "Backed up existing Winre.wim to: $backup"
    }

    $targetFile = Join-Path $TargetPath 'Winre.wim'
    Copy-Item -LiteralPath $ReplacementPath -Destination $targetFile -Force

    Write-Section 'Registering replacement Windows RE image'
    Invoke-Native -FilePath reagentc.exe -Arguments @('/setreimage', "/path", $TargetPath) | Out-Null
    Invoke-Native -FilePath reagentc.exe -Arguments @('/enable') | Out-Null
}

function Get-OsPartition {
    $driveLetter = $env:SystemDrive.TrimEnd(':')
    $partition = Get-Partition -DriveLetter $driveLetter -ErrorAction Stop
    if (-not $partition) {
        throw "Could not resolve OS partition for $env:SystemDrive"
    }

    return $partition
}

function Test-IsRecoveryPartition {
    param([Parameter(Mandatory = $true)]$Partition)

    $gptType = $null
    $mbrType = $null
    $type = $null

    if ($Partition.PSObject.Properties.Name -contains 'GptType') {
        $gptType = [string]$Partition.GptType
    }
    if ($Partition.PSObject.Properties.Name -contains 'MbrType') {
        $mbrType = [string]$Partition.MbrType
    }
    if ($Partition.PSObject.Properties.Name -contains 'Type') {
        $type = [string]$Partition.Type
    }

    return (
        ($gptType -and ($gptType.Trim('{}') -ieq $WindowsReGptType)) -or
        ($mbrType -and ($mbrType -match '27|Recovery')) -or
        ($type -and ($type -match 'Recovery'))
    )
}

function Get-RecoveryPartitionsOnDisk {
    param([Parameter(Mandatory = $true)][int]$DiskNumber)

    Get-Partition -DiskNumber $DiskNumber |
        Where-Object { Test-IsRecoveryPartition -Partition $_ } |
        Sort-Object -Property Offset -Descending
}

function Get-FreeSpaceForPartition {
    param([Parameter(Mandatory = $true)]$Partition)

    if (-not $Partition.DriveLetter) {
        return $null
    }

    $volume = Get-Volume -DriveLetter $Partition.DriveLetter -ErrorAction Stop
    return $volume.SizeRemaining
}

function Get-TemporaryDriveLetter {
    $used = Get-Volume | Where-Object DriveLetter | ForEach-Object { [string]$_.DriveLetter }
    foreach ($letter in @('R', 'T', 'W', 'Y', 'Z', 'S', 'Q', 'P', 'O', 'N', 'M')) {
        if ($used -notcontains $letter) {
            return $letter
        }
    }

    throw 'No temporary drive letter is available for mounting the recovery partition.'
}

function Add-TemporaryPartitionLetter {
    param([Parameter(Mandatory = $true)]$Partition)

    if ($Partition.DriveLetter) {
        $disk = Get-Disk -Number $Partition.DiskNumber -ErrorAction Stop
        return [pscustomobject]@{
            Partition              = $Partition
            DriveLetter            = [string]$Partition.DriveLetter
            AddedTemporaryLetter   = $false
            ShouldFinalizeAsHidden = $false
            PartitionStyle         = [string]$disk.PartitionStyle
        }
    }

    $letter = Get-TemporaryDriveLetter
    Add-PartitionAccessPath -DiskNumber $Partition.DiskNumber -PartitionNumber $Partition.PartitionNumber -AccessPath "$letter`:\" | Out-Null
    $updated = Get-Partition -DiskNumber $Partition.DiskNumber -PartitionNumber $Partition.PartitionNumber
    $disk = Get-Disk -Number $updated.DiskNumber -ErrorAction Stop

    [pscustomobject]@{
        Partition              = $updated
        DriveLetter            = $letter
        AddedTemporaryLetter   = $true
        ShouldFinalizeAsHidden = $true
        PartitionStyle         = [string]$disk.PartitionStyle
    }
}

function Invoke-DiskPartScript {
    param([Parameter(Mandatory = $true)][string[]]$Commands)

    $scriptPath = Join-Path $resolvedScratchPath "diskpart-$([guid]::NewGuid().ToString('N')).txt"
    try {
        Set-Content -LiteralPath $scriptPath -Value $Commands -Encoding ASCII
        $result = Invoke-Native -FilePath diskpart.exe -Arguments @('/s', $scriptPath)
        return $result
    }
    finally {
        Remove-Item -LiteralPath $scriptPath -Force -ErrorAction SilentlyContinue
    }
}

function Set-RecoveryPartitionMetadata {
    param(
        [Parameter(Mandatory = $true)][int]$DiskNumber,
        [Parameter(Mandatory = $true)][int]$PartitionNumber,
        [Parameter(Mandatory = $true)][string]$PartitionStyle
    )

    if ($PartitionStyle -eq 'GPT') {
        Invoke-DiskPartScript -Commands @(
            "select disk $DiskNumber",
            "select partition $PartitionNumber",
            "set id=$WindowsReGptType override",
            "gpt attributes=$WindowsReGptAttributes"
        ) | Out-Null
    }
    elseif ($PartitionStyle -eq 'MBR') {
        Invoke-DiskPartScript -Commands @(
            "select disk $DiskNumber",
            "select partition $PartitionNumber",
            "set id=$WindowsReMbrType override"
        ) | Out-Null
    }
    else {
        throw "Unsupported partition style: $PartitionStyle"
    }
}

function Remove-TemporaryPartitionLetter {
    param([Parameter(Mandatory = $true)]$PartitionTarget)

    if (-not $PartitionTarget.AddedTemporaryLetter) {
        return
    }

    Remove-PartitionAccessPath -DiskNumber $PartitionTarget.Partition.DiskNumber -PartitionNumber $PartitionTarget.Partition.PartitionNumber -AccessPath "$($PartitionTarget.DriveLetter)`:\" -ErrorAction SilentlyContinue
}

function Complete-WinRePartitionTarget {
    param([Parameter(Mandatory = $true)]$PartitionTarget)

    if ($PartitionTarget.ShouldFinalizeAsHidden) {
        Set-RecoveryPartitionMetadata -DiskNumber $PartitionTarget.Partition.DiskNumber -PartitionNumber $PartitionTarget.Partition.PartitionNumber -PartitionStyle $PartitionTarget.PartitionStyle
    }

    Remove-TemporaryPartitionLetter -PartitionTarget $PartitionTarget
}

function New-WinRePartition {
    param(
        [Parameter(Mandatory = $true)]$OsPartition,
        [Parameter(Mandatory = $true)]$Disk,
        [Parameter(Mandatory = $true)][UInt64]$RequiredSizeBytes
    )

    $sizeMB = [math]::Ceiling($RequiredSizeBytes / 1MB)
    Write-Section 'Creating Windows RE partition'
    Write-Host "Shrinking $env:SystemDrive by $sizeMB MB on disk $($OsPartition.DiskNumber)."

    $supportedSize = Get-PartitionSupportedSize -DriveLetter $env:SystemDrive.TrimEnd(':')
    $newOsSize = [UInt64]($OsPartition.Size - $RequiredSizeBytes)
    if ($newOsSize -lt $supportedSize.SizeMin) {
        throw "The OS partition cannot be shrunk enough to create a $sizeMB MB recovery partition. Minimum supported OS partition size is $([math]::Round($supportedSize.SizeMin / 1GB, 2)) GB."
    }

    Resize-Partition -DriveLetter $env:SystemDrive.TrimEnd(':') -Size $newOsSize

    $letter = Get-TemporaryDriveLetter
    $partitionStyle = [string]$Disk.PartitionStyle
    $commands = @(
        "select disk $($OsPartition.DiskNumber)",
        "create partition primary size=$sizeMB",
        'format quick fs=ntfs label="' + $RecoveryPartitionLabel + '"',
        "assign letter=$letter"
    )

    Invoke-DiskPartScript -Commands $commands | Out-Null
    $partition = Get-Partition -DriveLetter $letter -ErrorAction Stop

    [pscustomobject]@{
        Partition              = $partition
        DriveLetter            = $letter
        AddedTemporaryLetter   = $true
        ShouldFinalizeAsHidden = $true
        PartitionStyle         = $partitionStyle
    }
}

function Prepare-WinRePartitionTarget {
    param([Parameter(Mandatory = $true)][string]$ReplacementPath)

    $replacement = Get-Item -LiteralPath $ReplacementPath
    $requiredSizeBytes = [UInt64]([math]::Max($RecoveryPartitionSizeMB * 1MB, $replacement.Length + ($MinimumRecoveryFreeMB * 1MB)))
    $osPartition = Get-OsPartition
    $disk = Get-Disk -Number $osPartition.DiskNumber -ErrorAction Stop

    Write-Section 'Recovery partition layout'
    Write-Host "OS disk number:           $($osPartition.DiskNumber)"
    Write-Host "OS partition number:      $($osPartition.PartitionNumber)"
    Write-Host "Disk partition style:     $($disk.PartitionStyle)"
    Write-Host "Required recovery size:   $([math]::Ceiling($requiredSizeBytes / 1MB)) MB"

    if (($disk.PartitionStyle -ne 'GPT') -and ($disk.PartitionStyle -ne 'MBR')) {
        throw "Unsupported disk partition style: $($disk.PartitionStyle)"
    }

    Write-Section 'Disabling Windows RE before partition changes'
    Invoke-Native -FilePath reagentc.exe -Arguments @('/disable') -IgnoreExitCode | Out-Null

    $existingRecoveryPartitions = @(Get-RecoveryPartitionsOnDisk -DiskNumber $osPartition.DiskNumber)
    if ($existingRecoveryPartitions.Count -gt 0) {
        Write-Host "Found $($existingRecoveryPartitions.Count) recovery partition(s) on OS disk."
    }
    else {
        Write-Host 'No recovery partition found on OS disk.'
    }

    if ($existingRecoveryPartitions.Count -gt 0 -and (-not $RecreateRecoveryPartition)) {
        foreach ($partition in $existingRecoveryPartitions) {
            if ($partition.Size -ge $requiredSizeBytes) {
                Write-Host "Reusing recovery partition $($partition.PartitionNumber), size $([math]::Round($partition.Size / 1MB, 2)) MB."
                $mounted = Add-TemporaryPartitionLetter -Partition $partition
                $freeSpace = Get-FreeSpaceForPartition -Partition (Get-Partition -DriveLetter $mounted.DriveLetter)
                if ($freeSpace -ge ($replacement.Length + ($MinimumRecoveryFreeMB * 1MB))) {
                    return [pscustomobject]@{
                        TargetPath = "$($mounted.DriveLetter):\Recovery\WindowsRE"
                        MountInfo  = $mounted
                    }
                }

                Remove-TemporaryPartitionLetter -PartitionTarget $mounted
                Write-Host "Recovery partition $($partition.PartitionNumber) does not have enough free space after mounting."
            }
        }
    }

    if ($existingRecoveryPartitions.Count -gt 0 -and $RecreateRecoveryPartition) {
        Write-Section 'Removing existing recovery partition(s)'
        foreach ($partition in $existingRecoveryPartitions) {
            Write-Host "Deleting recovery partition $($partition.PartitionNumber) on disk $($partition.DiskNumber)."
            Remove-Partition -DiskNumber $partition.DiskNumber -PartitionNumber $partition.PartitionNumber -Confirm:$false
        }
    }

    $newPartition = New-WinRePartition -OsPartition $osPartition -Disk $disk -RequiredSizeBytes $requiredSizeBytes
    [pscustomobject]@{
        TargetPath = "$($newPartition.DriveLetter):\Recovery\WindowsRE"
        MountInfo  = $newPartition
    }
}

function Show-HealthSummary {
    param(
        [Parameter(Mandatory = $true)][object]$ReAgent,
        [Parameter()][System.IO.FileInfo]$LocalImage
    )

    Write-Section 'WinRE health summary'
    Write-Host "reagentc /info exit code: $($ReAgent.ExitCode)"
    Write-Host "Windows RE status:        $($ReAgent.Status)"
    Write-Host "Windows RE location:      $($ReAgent.Location)"

    if ($LocalImage) {
        Write-Host "Local Winre.wim:          $($LocalImage.FullName)"
        Write-Host "Local Winre.wim size:     $([math]::Round($LocalImage.Length / 1MB, 2)) MB"
        $validation = Test-WimImage -Path $LocalImage.FullName
        Write-Host "Local Winre.wim valid:    $($validation.IsValid)"
        if (-not $validation.IsValid) {
            Write-Host $validation.Output -ForegroundColor Red
        }
    }
    else {
        Write-Host "Local Winre.wim:          Not found at $TargetWinRePath"
    }
}

function Show-RecoveryPartitionSummary {
    Write-Section 'Recovery partition summary'
    $osPartition = Get-OsPartition
    $disk = Get-Disk -Number $osPartition.DiskNumber -ErrorAction Stop
    $recoveryPartitions = @(Get-RecoveryPartitionsOnDisk -DiskNumber $osPartition.DiskNumber)

    Write-Host "OS disk number:           $($osPartition.DiskNumber)"
    Write-Host "OS partition number:      $($osPartition.PartitionNumber)"
    Write-Host "Disk partition style:     $($disk.PartitionStyle)"

    if ($recoveryPartitions.Count -eq 0) {
        Write-Host 'Recovery partition(s):    None found on OS disk'
        return
    }

    foreach ($partition in $recoveryPartitions) {
        $sizeMB = [math]::Round($partition.Size / 1MB, 2)
        $driveLetter = if ($partition.DriveLetter) { "$($partition.DriveLetter):" } else { '(hidden)' }
        Write-Host "Recovery partition:       Disk $($partition.DiskNumber), Partition $($partition.PartitionNumber), $sizeMB MB, $driveLetter"
    }
}

Assert-Administrator

if ($RecreateRecoveryPartition -and (-not $ManagePartition)) {
    throw '-RecreateRecoveryPartition requires -ManagePartition.'
}

$isoMount = $null
$replacementWinRe = $null
$resolvedScratchPath = [IO.Path]::GetFullPath($ScratchPath)
New-Item -ItemType Directory -Path $resolvedScratchPath -Force | Out-Null

try {
    Write-Section 'Current Windows Recovery Environment'
    $reAgent = Get-ReAgentInfo
    Write-Host $reAgent.Raw

    $localImage = Get-LocalWinReImage -Path $TargetWinRePath
    Show-HealthSummary -ReAgent $reAgent -LocalImage $localImage
    Show-RecoveryPartitionSummary

    if ($PSCmdlet.ParameterSetName -eq 'WinReWim') {
        $replacementWinRe = (Resolve-Path -LiteralPath $SourceWinReWimPath).Path
    }
    elseif ($SourceIsoPath) {
        $isoMount = Mount-SourceIso -IsoPath $SourceIsoPath
        $installImagePath = Get-InstallImagePath -IsoRoot $isoMount.DriveRoot
        Show-InstallImageIndexes -InstallImagePath $installImagePath
        $replacementWinRe = Extract-WinReFromInstallImage -InstallImagePath $installImagePath -Index $ImageIndex -WorkRoot $resolvedScratchPath
    }

    if (-not $replacementWinRe) {
        Write-Host ''
        Write-Host 'No replacement source was supplied. Health check complete.' -ForegroundColor Green
        return
    }

    if (-not (Confirm-Repair -ReplacementPath $replacementWinRe)) {
        Write-Host 'Repair skipped. No changes were made.' -ForegroundColor Yellow
        return
    }

    $targetDescription = if ($ManagePartition) { 'managed recovery partition' } else { $TargetWinRePath }
    $partitionTarget = $null

    if ($PSCmdlet.ShouldProcess($targetDescription, 'Replace and re-register Windows RE image')) {
        try {
            $effectiveTargetWinRePath = $TargetWinRePath
            if ($ManagePartition) {
                $partitionTarget = Prepare-WinRePartitionTarget -ReplacementPath $replacementWinRe
                $effectiveTargetWinRePath = $partitionTarget.TargetPath
            }

            Install-WinReImage -ReplacementPath $replacementWinRe -TargetPath $effectiveTargetWinRePath -WorkRoot $resolvedScratchPath
        }
        finally {
            if ($partitionTarget) {
                Complete-WinRePartitionTarget -PartitionTarget $partitionTarget.MountInfo
            }
        }

        Write-Section 'Post-repair Windows Recovery Environment'
        $postReAgent = Get-ReAgentInfo
        Write-Host $postReAgent.Raw
        $postLocalImage = Get-LocalWinReImage -Path $TargetWinRePath
        Show-HealthSummary -ReAgent $postReAgent -LocalImage $postLocalImage
        Show-RecoveryPartitionSummary
    }
}
finally {
    if ($isoMount -and $isoMount.MountedHere -and (-not $KeepMounted)) {
        Write-Section 'Dismounting ISO'
        Dismount-DiskImage -ImagePath $isoMount.ImagePath | Out-Null
    }
}
