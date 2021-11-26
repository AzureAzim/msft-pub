Hello World


# Here is my Proactive Remediations Script Library. 
## For infromation on PR's see https://docs.microsoft.com/en-us/mem/analytics/proactive-remediations

LocalAdmins is focused around removal or adding Local admins. The sample script removes local admins from machines. This package is designed to allow WIndows 365 Busines cusotmers to remove local admin rights from those machines but can also be used against Azure AD Joined Devices where users have enrolled from the OOBE

Some Scripts will be single scripts that detect the context at runtime, for example detection mode vs remediation mode will dictate which piece of code within teh script to run. I decided to do it this way becasue I dont want to have two files for every Proactive Remediation.
Have fun!



### THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, TITLE AND NON-INFRINGEMENT.
