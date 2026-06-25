# WinRE Repair Script

`Repair-WinRE.ps1` checks the health of the local Windows Recovery Environment (WinRE) and can replace the current `Winre.wim` with a known-good copy from Microsoft Windows installation media. It can also optionally manage the recovery partition so the repair is end-to-end for common reset failures.

The preferred source is a Windows ISO available from a local path or UNC path. The ISO should contain `sources\install.wim` or `sources\install.esd`. Split `.swm` media is intentionally avoided.

## What it checks

- Current WinRE registration using `reagentc /info`
- Current WinRE status and configured location
- Whether `Winre.wim` exists under the target recovery path
- Whether the local `Winre.wim` can be read by DISM
- Recovery partition presence, size, and disk layout on the OS disk

## What repair does

When repair is confirmed without partition management, the script:

1. Mounts the supplied Windows ISO.
2. Finds `sources\install.wim` or `sources\install.esd`.
3. Extracts `Windows\System32\Recovery\Winre.wim` from the selected image index.
4. Disables WinRE with `reagentc /disable`.
5. Backs up the existing local `Winre.wim`.
6. Copies in the replacement `Winre.wim`.
7. Re-registers and enables WinRE with `reagentc /setreimage` and `reagentc /enable`.
8. Runs a post-repair WinRE health summary.

When `-ManagePartition` is used, the script also:

1. Detects the OS disk and partition style.
2. Reuses an existing recovery partition if it is large enough.
3. Creates a new recovery partition by shrinking the OS partition if no usable recovery partition exists.
4. Optionally deletes existing recovery partitions first when `-RecreateRecoveryPartition` is supplied.
5. Formats the recovery partition as NTFS.
6. Sets the Windows RE partition type and hidden/no-default-drive-letter metadata.
7. Copies `Winre.wim` to `Recovery\WindowsRE` on the recovery partition.
8. Registers WinRE against that recovery partition.

## Requirements

- Run from an elevated PowerShell session.
- Windows PowerShell 5.1 or newer.
- Local admin rights.
- Access to a Microsoft Windows ISO or direct known-good `Winre.wim`.
- The ISO should match the target OS build, architecture, language, and edition as closely as possible.
- Enough free space on the OS partition if `-ManagePartition` needs to shrink it.
- A verified backup before using `-RecreateRecoveryPartition`.

## Basic usage

Health check only:

```powershell
.\Repair-WinRE.ps1
```

Use a UNC-hosted ISO and prompt before repair:

```powershell
.\Repair-WinRE.ps1 -SourceIsoPath "\\server\share\Win11_24H2.iso" -ImageIndex 1
```

Run repair non-interactively:

```powershell
.\Repair-WinRE.ps1 -SourceIsoPath "\\server\share\Win11_24H2.iso" -ImageIndex 1 -Repair -Force
```

Repair WinRE and create or reuse a dedicated recovery partition:

```powershell
.\Repair-WinRE.ps1 -SourceIsoPath "\\server\share\Win11_24H2.iso" -ImageIndex 1 -ManagePartition -Repair
```

Recreate the recovery partition if the existing one is wrong or too small:

```powershell
.\Repair-WinRE.ps1 -SourceIsoPath "\\server\share\Win11_24H2.iso" -ImageIndex 1 -ManagePartition -RecreateRecoveryPartition -Repair
```

Run partition repair non-interactively:

```powershell
.\Repair-WinRE.ps1 -SourceIsoPath "\\server\share\Win11_24H2.iso" -ImageIndex 1 -ManagePartition -RecreateRecoveryPartition -RecoveryPartitionSizeMB 1024 -Repair -Force
```

Use a direct known-good `Winre.wim`:

```powershell
.\Repair-WinRE.ps1 -SourceWinReWimPath "\\server\share\known-good\Winre.wim" -Repair
```

Use a custom target recovery directory:

```powershell
.\Repair-WinRE.ps1 -SourceIsoPath "\\server\share\Win11_24H2.iso" -TargetWinRePath "C:\Windows\System32\Recovery" -Repair
```

Use a custom scratch directory:

```powershell
.\Repair-WinRE.ps1 -SourceIsoPath "\\server\share\Win11_24H2.iso" -ScratchPath "D:\WinRE-Repair" -Repair
```

## Parameters

| Parameter | Description |
| --- | --- |
| `-SourceIsoPath` | Path to a Windows ISO. Local paths and UNC paths are supported. |
| `-SourceWinReWimPath` | Direct path to a known-good `Winre.wim`. Use this when you do not want to extract from an ISO. |
| `-ImageIndex` | Image index inside `install.wim` or `install.esd`. Defaults to `1`. |
| `-TargetWinRePath` | Directory where the local `Winre.wim` should be installed. Defaults to `C:\Windows\System32\Recovery`. |
| `-ScratchPath` | Working directory for mount, extraction, and backups. Defaults to `C:\WinRE-Repair`. |
| `-ManagePartition` | Reuses or creates a dedicated Windows RE partition on the OS disk and stores `Winre.wim` there. |
| `-RecreateRecoveryPartition` | Deletes existing recovery partition(s) on the OS disk before creating a new one. Use only with `-ManagePartition`. |
| `-RecoveryPartitionSizeMB` | Size for a newly created recovery partition. Defaults to `1024`. |
| `-MinimumRecoveryFreeMB` | Required free space cushion after `Winre.wim` is copied. Defaults to `250`. |
| `-RecoveryPartitionLabel` | Volume label for a newly created recovery partition. Defaults to `Windows RE tools`. |
| `-Repair` | Indicates repair is intended. Without `-Force`, the script still asks for confirmation. |
| `-Force` | Skips the confirmation prompt when used with `-Repair`. |
| `-KeepMounted` | Leaves the mounted install image in place for troubleshooting. |

## Partition management behavior

`-ManagePartition` is intentionally opt-in because it can resize the OS partition.

By default, partition management is conservative:

- If an existing recovery partition on the OS disk is large enough and has enough free space, the script reuses it.
- If no usable recovery partition exists, the script shrinks the OS partition and creates a new recovery partition.
- Existing recovery partitions are not deleted unless `-RecreateRecoveryPartition` is supplied.

For GPT disks, the script sets the Windows RE tools partition GUID:

```text
de94bba4-06d1-4d40-a16a-bfd50179d6ac
```

and GPT attributes:

```text
0x8000000000000001
```

For MBR disks, the script sets partition type:

```text
0x27
```

The recovery partition is temporarily assigned a drive letter while `Winre.wim` is copied and `reagentc` is configured. The temporary drive letter is removed afterward.

## Partition safety notes

Use `-RecreateRecoveryPartition` only when you intend to remove existing recovery partitions on the OS disk. The script does not delete the OS partition, EFI system partition, or Microsoft Reserved partition, but recovery partition deletion is still destructive.

If the OS partition cannot be shrunk enough, the script stops before creating the new partition.

## Choosing the image index

The script prints the available image indexes from the ISO before extracting `Winre.wim`. Pick the index that matches the installed Windows edition.

Example:

```powershell
DISM /Get-WimInfo /WimFile:"D:\sources\install.wim"
```

Common examples are Windows Pro, Enterprise, or Education indexes. The exact index depends on the ISO.

## Notes about ESD and SWM media

If the ISO contains `install.esd`, the script exports the selected image to a temporary WIM first, then mounts that temporary WIM to extract `Winre.wim`.

If the ISO only contains `install.swm`, the script stops. Use an ISO with a single `install.wim` or `install.esd`, or provide a direct known-good `Winre.wim` with `-SourceWinReWimPath`.

## Backup location

Existing WinRE images are backed up under:

```text
C:\WinRE-Repair\backup
```

unless a different `-ScratchPath` is supplied.

## Suggested validation after repair

Run:

```powershell
reagentc /info
reagentc /enable
```

Confirm that `Windows RE status` is `Enabled` and the configured location points to the expected recovery image path.
