<#
.SYNOPSIS
    This function replaces the Log Analytics Workspace locally on the machine by reconfiguring the Agent Locally. This is for devices using the old MMA Agent
.DESCRIPTION
    This will invoke a coommand on a PC remotely to set the Log Analytics Workspace on a machine using PSRemoting/WSMan
.EXAMPLE
    Set-LogAnalyticsAgentWorkspaceC.ps1 -Workspaceid '<WORKSPACE ID GOES HERE>' -WorkspaceKey '<WORKSPACE KEY GOES HERE>' -Computername SERVER1
.PARAMETER Workspaceid
    This is the Workspace ID for the cmdlet
.PARAMETER Workspacekey
    Workspace key for your Workspace
.PARAMETER Computername
    Target Computer
.OUTPUTS
    Output from this cmdlet (if any)
.NOTES
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

#>
Function Set-LogAnalyticsAgentWorkspaceConfiguration {
	[CmdletBinding()]
	param(
        [Parameter(Mandatory)]
        [string]$Workspaceid,
        [string]$Workspacekey,
        [string]$Computername = 'localhost'
        )
    foreach ($name in $Computername) {
            Invoke-Command -ComputerName $name -ScriptBlock {
                $mma = New-Object -ComObject 'AgentConfigManager.MgmtSvcCfg'
                $mma.AddCloudWorkspace($WorkspaceId, $WorkspaceKey)
                $mma.ReloadConfiguration()
            }
        }
}
