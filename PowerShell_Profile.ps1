#setup prompt
function prompt            
{            
    "PS "+"$env:computername " + $(Get-Date)+ " [$(get-location)]> "            
}

#set up window title
$windowtitle = Read-host "Name your window"
$host.ui.RawUI.WindowTitle = $windowtitle

#transcript maint
$transcriptitems = get-childitem -path "$env:OneDriveCommercial\Documents\ps-transcripts"
$junktranscripts = $transcriptitems | where {$_.length -lt 1000}
$transcriptitemscount = $transcriptitems.count
$junktranscriptcount = $junktranscripts.count
Write-host "There are $transcriptitemscount total transcripts, Approx $junktranscriptcount are junk stored in the variable" '$junktranscripts' 

#start transcript and save in onedrive docs folder 
Start-Transcript -Path "$env:OneDriveCommercial\Documents\ps-transcripts"  
