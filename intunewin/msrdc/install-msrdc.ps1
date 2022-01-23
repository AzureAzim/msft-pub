#THis short script downloads the latest MSRDC client from Microsoft and installs under the device context (for all users). It is meant to be packaged into an Intunewin and deployed to devices where this app is the primary shell


# Source URL for MSRDC
$url = "https://go.microsoft.com/fwlink/?linkid=2068602"
# Destation file
$dest = "$env:temp\msrdc.msi"
# Download the file
Invoke-WebRequest -Uri $url -OutFile $dest

msiexec /i "$dest" /qn ALLUSERS=1

#Setup Insider Ring (Optional, comment out if you dont want insider ring)
New-Item -path "HKLM:\Software\Microsoft\MSRDC\Policies" -Name "ReleaseRing" -Force
set-ItemProperty -path "HKLM:\Software\Microsoft\MSRDC\Policies" -Name "ReleaseRing" -value "Insider"
