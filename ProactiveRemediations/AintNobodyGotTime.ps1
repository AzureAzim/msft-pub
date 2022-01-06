<#
.SYNOPSIS
    This script fixes time issues on endpoints if they are using the local clock and losing time sync. Mostly designed to run on AADJ Only devices that dont get time settings from a DC
.DESCRIPTION
   Import this in Microsoft Endpoint Manager Proactive Remediations, this piece of code should be uploaded into both Detect and Remediate fields.
.NOTES
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#>

$mode = $MyInvocation.MyCommand.Name.Split(".")[0]
$TimeKey= Get-ItemProperty -path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters\"
$Ntpserver = $timekey.ntpserver
$Timetype = $timekey.type
$modechange = $false
$modeerror = @()
$servicestate = get-service  -Name "w32time" 
######DETECT GOES HERE

if($mode -eq "detect") {
    if ($timeType -ne "AllSync") {
        $modeerror += Write-Warning "NTP Type is wrong $Timetype"
        $modechange = $true
    }
    if ($NTPSERVER -ne 'time.windows.com,0x9') {
        $modeerror += Write-Warning "NTP Server is Wrong, $ntpserver"
        $modechange = $true
    }
    if ($servicestate.StartType -eq "Disabled") {
        $modeerror += Write-Warning "Service State is Wrong, $servicestate.StartType"
        $modechange = $true

    }
    if ($modechange -eq $false){exit 0}
    if ($modechange -eq $true){$modeerror; exit 1}
} Elseif($mode -eq "remediate") {  
    #Turn on the w32time service to ensure its enabled
    Set-Service -Name "w32time" -Status running -StartupType automatic
    w32tm /config /manualpeerlist:"time.windows.com,0x9" /syncfromflags:all
    net stop w32time
    net start w32time
    exit 0 }
