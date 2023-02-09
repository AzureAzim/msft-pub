##CHECK Script Running Context (ie detection or remediation mode)
#THIS IS A FORK OF DONNAS SCRIPTS: https://github.com/microsoft/Windows365-PSScripts/tree/main/RDP%20Shortpath%20Proactive%20Remediation
<#
.COPYRIGHT
Copyright (c) Microsoft Corporation. All rights reserved. Licensed under the MIT license.
See LICENSE in the project root for license information.
#>

# Version 1.0
#
# This script is the detection script for a Proactive Remediation solution to enable RDP
# Shortpath for Windows 365 Cloud PCs. 
#
#####################################
$mode = $MyInvocation.MyCommand.Name.Split(".")[0]
$modechange = $false
if ($env:COMPUTERNAME -notlike "CPC-*") {
    write-host "This is not a cloud pc. No remdiation required."
    Exit 0
}
##detection mode
if($mode -eq "detect") {

    try {
        if (((Get-ItemProperty -ErrorAction Stop -Path "Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations" -name ICEControl).ICEControl) -eq 2) {
            write-host "Registry key is properly configured for RDP Shortpath."
            Exit 0
        }
        else {
            write-host "Registry key is not set correctly RDP Shortpath."
            Exit 1
        }
    }
    catch {
        write-host "Registry key likely not present."
        Exit 1
    }


}

Elseif($mode -eq "remediate") {
    $state = 0

    #Determine if the key needs to be updated or created
    try {
        if (((Get-ItemProperty -ErrorAction Stop -Path "Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations" -name ICEControl).ICEControl) -ne 2) {
            write-host "Registry key present - needs updating"
            $state = 1
        }
    }
    catch {
        write-host "Registry key is not present - needs creating"
        $state = 2
    }
    
    #Set the registry key, fail on error
    if ($state -eq 1) {
        try {
            write-host "Updating the registry key..."
            Set-ItemProperty -Path  "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations" -Name ICEControl -Value 2 -ErrorAction stop
        }
        catch {
            Exit 1
        }
    }
    
    #Create the key, fail on error
    if ($state -eq 2) {
        try {
            write-host "Creating the registry key..."
            New-ItemProperty -Path  "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations" -Name ICEControl -PropertyType DWORD -Value 2 -ErrorAction stop
        }
        catch {
            Exit 1
        }
    }
    
    #check if update/create was succesful
    try {
        if (((Get-ItemProperty -ErrorAction Stop -Path "Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations" -name ICEControl).ICEControl) -eq 2) {
            write-host "Key updated successfully"
            Exit 0
        }
        else {
            write-host "Failed to update registry key"
            Exit 1
        }
    
    }
    catch {
        write-host "An error occured in validating the registry key remediation. Failing."
        Exit 1
    }
    
##THIS IS WHERE YOUR REMEDIATION CODE GOES

exit 0
}
