
#Set TenantID to the TenantID and the subjectID is the ObjectID of the group/user in the tenant you are providng access to
$tenantid = ""
$subjectid = ""


Install-module AzureADPreview
$AzureAdCred = Get-Credential  
Connect-AzureAD -Credential $AzureAdCred

$roles = Get-AzureADMSPrivilegedRoleDefinition -ProviderId aadRoles -ResourceId $tenantid


foreach ($role in $roles){
    #pick a time range in seconds for time variance
    $time = get-random -minimum 20 -maximum 60
    $RoleDefinitionId = $role.Id

    Open-AzureADMSPrivilegedRoleAssignmentRequest -ProviderId 'aadRoles' -ResourceId $tenantid -RoleDefinitionId $RoleDefinitionId -SubjectId $subjectid -Type 'adminAdd' -AssignmentState 'Eligible' -schedule $schedule -reason "PIM Project"

}
