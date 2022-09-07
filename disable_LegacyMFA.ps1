#THIS WILL DISABLE LEGACY MFA FOR ALL USERS IN THE TENANT, THIS IS VERY IMPACTFUL AND POTENTIALLY A RESUME GENERATING EVENT IF YOU RUN THIS WITHOUT PROPER AUTHORIZATION OR UNDERSTANDING TO THE IMPACT

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, TITLE AND NON-INFRINGEMENT.


$users = get-msoluser -all

foreach ($user in $users) {
#format upn

$upn = $user.UserPrincipalName


# Get StrongAuthenticationRequirments configure on a user
(Get-MsolUser -UserPrincipalName $upn).StrongAuthenticationRequirements
 
# Clear StrongAuthenticationRequirements from a user
$mfa = @()
Set-MsolUser -UserPrincipalName $upn -StrongAuthenticationRequirements $mfa
 
# Verify StrongAuthenticationRequirements are cleared from the user
(Get-MsolUser -UserPrincipalName $upn).StrongAuthenticationRequirements

}
