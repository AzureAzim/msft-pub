#=============================================================================================================================
#
# Script Name:     Detect_LocalAdmin.ps1
# Description:     Detect if the currently logged in user is a local admin
#                  
# Notes:           Run as the user context in MEM. This script is for detecting if users are local admins. 
#                   If you do not want them to be local admins, exit 1 at line 23 and exit 0 at line 35
#                   If you do want tehm to be local admins, exit 0 at line 23 and exit 1 at line 35
#
#=============================================================================================================================

# Define Variables
$localuser = $env:USERNAME
$LocalAdmins = net localgroup administrators
    
    if (("$localadmins" -like "*$localuser*") -eq $true){
        Write-Host "Local user found in Admins Group"
        exit 1
    }
    else{
        #No matching certificates, do not remediate
        Write-Host "User is not local admin"        
        exit 0
    } 
catch{
    $errMsg = $_.Exception.Message
    Write-Error $errMsg
    exit 1
}
