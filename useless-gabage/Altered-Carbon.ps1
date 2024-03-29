#Requires -RunAsAdministrator
### This script includes code from all over, much of which was forked from Jos Lieben (http://www.lieben.nu)

###Set up Params
    #chocoapps
    $appstoinstall = "powertoys","prusaslicer","firefox","googlechrome","7zip","chrome-remote-desktop-host","vscode","vlc","python3","microsoft-windows-terminal","winscp","git","rsat","steam-client","microsoft-windows-terminal","notepadplusplus","azcopy","obs-studio","obs-virtualcam","obs-ndi","firefox","rufus","vscode-python","vscode-arduino","vscode-powershell","drawio","discord","microsoftazurestorageexplorer"
    #OD4B Redirect
    #$autoRerunMinutes = 10 #If set to 0, only runs at logon, else, runs every X minutes AND at logon, expect random delays of up to 5 minutes due to bandwidth, service availability, local resources etc. I strongly recommend 0 or >60 as input value to avoid being throttled
    #$visibleToUser = $false #if set to true, user will see 
    $tenantId = "72f988bf-86f1-41af-91ab-2d7cd011db47" #you can use https://gitlab.com/Lieben/assortedFunctions/blob/master/get-tenantIdFromLogin.ps1 to get your tenant ID
####folders to redirect
    $listOfLibrariesToAutoMount = @()
    $listOfFoldersToRedirect = @(
    @{"knownFolderInternalName" = "Desktop"; "knownFolderInternalIdentifier" = "Desktop"; "targetPath" = "\Desktop"; "targetLocation" = "onedrive"; "copyExistingFiles" = $True; "setEnvironmentVariable" = $True},
    @{"knownFolderInternalName" = "MyDocuments"; "knownFolderInternalIdentifier" = "Documents"; "targetPath" = "\Documents"; "targetLocation" = "onedrive"; "copyExistingFiles" = $True; "setEnvironmentVariable" = $True},
    @{"knownFolderInternalName" = "MyPictures"; "knownFolderInternalIdentifier" = "Pictures"; "targetPath" = "\Pictures"; "targetLocation" = "onedrive"; "copyExistingFiles" = $True; "setEnvironmentVariable" = $True},#note that the last entry does NOT end with a comma
    #azims adds
    @{"knownFolderInternalName" = "Downloads"; "knownFolderInternalIdentifier" = "Downloads"; "targetPath" = "\Downloads"; "targetLocation" = "onedrive"; "copyExistingFiles" = $True; "setEnvironmentVariable" = $True},#note that the last entry does NOT end with a comma
    @{"knownFolderInternalName" = "Links"; "knownFolderInternalIdentifier" = "Links"; "targetPath" = "\Links"; "targetLocation" = "onedrive"; "copyExistingFiles" = $True; "setEnvironmentVariable" = $True},#note that the last entry does NOT end with a comma
    @{"knownFolderInternalName" = "Favorites"; "knownFolderInternalIdentifier" = "Favorites"; "targetPath" = "\Favorites"; "targetLocation" = "onedrive"; "copyExistingFiles" = $True; "setEnvironmentVariable" = $True},#note that the last entry does NOT end with a comma
    @{"knownFolderInternalName" = "Music"; "knownFolderInternalIdentifier" = "Music"; "targetPath" = "\Music"; "targetLocation" = "onedrive"; "copyExistingFiles" = $True; "setEnvironmentVariable" = $True},#note that the last entry does NOT end with a comma
    @{"knownFolderInternalName" = "SavedGames"; "knownFolderInternalIdentifier" = "SavedGames"; "targetPath" = "\Saved Games"; "targetLocation" = "onedrive"; "copyExistingFiles" = $True; "setEnvironmentVariable" = $True},#note that the last entry does NOT end with a comma
    @{"knownFolderInternalName" = "SavedSearches"; "knownFolderInternalIdentifier" = "SavedSearches"; "targetPath" = "\Saved Searches"; "targetLocation" = "onedrive"; "copyExistingFiles" = $True; "setEnvironmentVariable" = $True},#note that the last entry does NOT end with a comma
    @{"knownFolderInternalName" = "Contacts"; "knownFolderInternalIdentifier" = "Contacts"; "targetPath" = "\Contacts"; "targetLocation" = "onedrive"; "copyExistingFiles" = $True; "setEnvironmentVariable" = $True}#note that the last entry does NOT end with a comma
    @{"knownFolderInternalName" = "SavedGames"; "knownFolderInternalIdentifier" = "SavedGames"; "targetPath" = "\SavedGames"; "targetLocation" = "onedrive"; "copyExistingFiles" = $True; "setEnvironmentVariable" = $True},#note that the last entry does NOT end with a comma
    @{"knownFolderInternalName" = "Videos"; "knownFolderInternalIdentifier" = "Videos"; "targetPath" = "\Videos"; "targetLocation" = "onedrive"; "copyExistingFiles" = $True; "setEnvironmentVariable" = $True},#note that the last entry does NOT end with a comma
    @{"knownFolderInternalName" = "Objects3D"; "knownFolderInternalIdentifier" = "Objects3D"; "targetPath" = "\3D Objects"; "targetLocation" = "onedrive"; "copyExistingFiles" = $True; "setEnvironmentVariable" = $True}#note that the last entry does NOT end with a comma
    )
    $listOfOtherFoldersToRedirect = @(
        @{"originalLocation" = "$($Env:APPDATA)\Skype"; "targetPath" = "\Appdata\Skype"; "targetLocation" = "onedrive"; "hide" = $True; "copyExistingFiles" = $True},
        @{"originalLocation" = "$($Env:USERPROFILE)\3d Objects"; "targetPath" = "\3d"; "targetLocation" = "onedrive"; "hide" = $True; "copyExistingFiles" = $True}
    )
    



###choco install
Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
###install apps from choco
choco install $appstoinstall -y
#for ($i=1;$i -le $appstoinstall.count; $i++) {
 #   foreach ($app in $appstoinstall){
    #Write-Progress -Activity "Installing apps through Choco" -status "installing $app" -PercentComplete (($i / $appstoinstall.count) * 100)
 #   choco install $app -y
  #  $app[$i]
 #       }
  #  }
#add required functions, Modules, and libraries
    Install-Module -Name BurntToast -Force
    import-module -name UEV
    $inboxTemplatesSrc = "$env:ProgramData\Microsoft\UEV\InboxTemplates"
    $systemtemplatespath = test-path "$env:temp\systemtemplates"

    Function Get-AzureBlobItem {
        <#
            .SYNOPSIS
                Returns an array of items and properties from an Azure blog storage URL.
            .DESCRIPTION
                Queries an Azure blog storage URL and returns an array with properties of files in a Container.
                Requires Public access level of anonymous read access to the blob storage container.
                Works with PowerShell Core.
                
            .NOTES
                Author: Aaron Parker
                Twitter: @stealthpuppy
            .PARAMETER Url
                The Azure blob storage container URL. The container must be enabled for anonymous read access.
                The URL must include the List Container request URI. See https://docs.microsoft.com/en-us/rest/api/storageservices/list-containers2 for more information.
            
            .EXAMPLE
                Get-AzureBlobItems -Uri "https://aaronparker.blob.core.windows.net/folder/?comp=list"
                Description:
                Returns the list of files from the supplied URL, with Name, URL, Size and Last Modifed properties for each item.
        #>
        [CmdletBinding(SupportsShouldProcess = $False)]
        [OutputType([System.Management.Automation.PSObject])]
        Param (
            [Parameter(ValueFromPipeline = $True, Mandatory = $True, HelpMessage = "Azure blob storage URL with List Containers request URI '?comp=list'.")]
            [ValidatePattern("^(http|https)://")]
            [System.String] $Uri
        )
    
        # Get response from Azure blog storage; Convert contents into usable XML, removing extraneous leading characters
        try {
            $iwrParams = @{
                Uri             = $Uri
                UseBasicParsing = $True
                ContentType     = "application/xml"
                ErrorAction     = "Stop"
            }
            $list = Invoke-WebRequest @iwrParams
        }
        catch [System.Net.WebException] {
            Write-Warning -Message ([string]::Format("Error : {0}", $_.Exception.Message))
        }
        catch [System.Exception] {
            Write-Warning -Message "$($MyInvocation.MyCommand): failed to download: $Uri."
            Throw $_.Exception.Message
        }
        If ($Null -ne $list) {
            [System.Xml.XmlDocument] $xml = $list.Content.Substring($list.Content.IndexOf("<?xml", 0))
    
            # Build an object with file properties to return on the pipeline
            $fileList = New-Object -TypeName System.Collections.ArrayList
            ForEach ($node in (Select-Xml -XPath "//Blobs/Blob" -Xml $xml).Node) {
                $PSObject = [PSCustomObject] @{
                    Name         = ($node | Select-Object -ExpandProperty Name)
                    Url          = ($node | Select-Object -ExpandProperty Url)
                    Size         = ($node | Select-Object -ExpandProperty Size)
                    LastModified = ($node | Select-Object -ExpandProperty LastModified)
                }
                $fileList.Add($PSObject) | Out-Null
            }
            If ($Null -ne $fileList) {
                Write-Output -InputObject $fileList
            }
        }
    }
    $source=@"
using System;
using System.Runtime.InteropServices;

namespace murrayju
{
    public static class ProcessExtensions
    {
        #region Win32 Constants

        private const int CREATE_UNICODE_ENVIRONMENT = 0x00000400;
        private const int CREATE_NO_WINDOW = 0x08000000;

        private const int CREATE_NEW_CONSOLE = 0x00000010;

        private const uint INVALID_SESSION_ID = 0xFFFFFFFF;
        private static readonly IntPtr WTS_CURRENT_SERVER_HANDLE = IntPtr.Zero;

        #endregion

        #region DllImports

        [DllImport("advapi32.dll", EntryPoint = "CreateProcessAsUser", SetLastError = true, CharSet = CharSet.Ansi, CallingConvention = CallingConvention.StdCall)]
        private static extern bool CreateProcessAsUser(
            IntPtr hToken,
            String lpApplicationName,
            String lpCommandLine,
            IntPtr lpProcessAttributes,
            IntPtr lpThreadAttributes,
            bool bInheritHandle,
            uint dwCreationFlags,
            IntPtr lpEnvironment,
            String lpCurrentDirectory,
            ref STARTUPINFO lpStartupInfo,
            out PROCESS_INFORMATION lpProcessInformation);

        [DllImport("advapi32.dll", EntryPoint = "DuplicateTokenEx")]
        private static extern bool DuplicateTokenEx(
            IntPtr ExistingTokenHandle,
            uint dwDesiredAccess,
            IntPtr lpThreadAttributes,
            int TokenType,
            int ImpersonationLevel,
            ref IntPtr DuplicateTokenHandle);

        [DllImport("userenv.dll", SetLastError = true)]
        private static extern bool CreateEnvironmentBlock(ref IntPtr lpEnvironment, IntPtr hToken, bool bInherit);

        [DllImport("userenv.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool DestroyEnvironmentBlock(IntPtr lpEnvironment);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool CloseHandle(IntPtr hSnapshot);

        [DllImport("kernel32.dll")]
        private static extern uint WTSGetActiveConsoleSessionId();

        [DllImport("Wtsapi32.dll")]
        private static extern uint WTSQueryUserToken(uint SessionId, ref IntPtr phToken);

        [DllImport("wtsapi32.dll", SetLastError = true)]
        private static extern int WTSEnumerateSessions(
            IntPtr hServer,
            int Reserved,
            int Version,
            ref IntPtr ppSessionInfo,
            ref int pCount);

        #endregion

        #region Win32 Structs

        private enum SW
        {
            SW_HIDE = 0,
            SW_SHOWNORMAL = 1,
            SW_NORMAL = 1,
            SW_SHOWMINIMIZED = 2,
            SW_SHOWMAXIMIZED = 3,
            SW_MAXIMIZE = 3,
            SW_SHOWNOACTIVATE = 4,
            SW_SHOW = 5,
            SW_MINIMIZE = 6,
            SW_SHOWMINNOACTIVE = 7,
            SW_SHOWNA = 8,
            SW_RESTORE = 9,
            SW_SHOWDEFAULT = 10,
            SW_MAX = 10
        }

        private enum WTS_CONNECTSTATE_CLASS
        {
            WTSActive,
            WTSConnected,
            WTSConnectQuery,
            WTSShadow,
            WTSDisconnected,
            WTSIdle,
            WTSListen,
            WTSReset,
            WTSDown,
            WTSInit
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct PROCESS_INFORMATION
        {
            public IntPtr hProcess;
            public IntPtr hThread;
            public uint dwProcessId;
            public uint dwThreadId;
        }

        private enum SECURITY_IMPERSONATION_LEVEL
        {
            SecurityAnonymous = 0,
            SecurityIdentification = 1,
            SecurityImpersonation = 2,
            SecurityDelegation = 3,
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct STARTUPINFO
        {
            public int cb;
            public String lpReserved;
            public String lpDesktop;
            public String lpTitle;
            public uint dwX;
            public uint dwY;
            public uint dwXSize;
            public uint dwYSize;
            public uint dwXCountChars;
            public uint dwYCountChars;
            public uint dwFillAttribute;
            public uint dwFlags;
            public short wShowWindow;
            public short cbReserved2;
            public IntPtr lpReserved2;
            public IntPtr hStdInput;
            public IntPtr hStdOutput;
            public IntPtr hStdError;
        }

        private enum TOKEN_TYPE
        {
            TokenPrimary = 1,
            TokenImpersonation = 2
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct WTS_SESSION_INFO
        {
            public readonly UInt32 SessionID;

            [MarshalAs(UnmanagedType.LPStr)]
            public readonly String pWinStationName;

            public readonly WTS_CONNECTSTATE_CLASS State;
        }

        #endregion

        // Gets the user token from the currently active session
        private static bool GetSessionUserToken(ref IntPtr phUserToken, int targetSessionId)
        {
            var bResult = false;
            var hImpersonationToken = IntPtr.Zero;
            var activeSessionId = INVALID_SESSION_ID;
            var pSessionInfo = IntPtr.Zero;
            var sessionCount = 0;

            // Get a handle to the user access token for the current active session.
            if (WTSEnumerateSessions(WTS_CURRENT_SERVER_HANDLE, 0, 1, ref pSessionInfo, ref sessionCount) != 0)
            {
                var arrayElementSize = Marshal.SizeOf(typeof(WTS_SESSION_INFO));
                var current = pSessionInfo;

                for (var i = 0; i < sessionCount; i++)
                {
                    var si = (WTS_SESSION_INFO)Marshal.PtrToStructure((IntPtr)current, typeof(WTS_SESSION_INFO));
                    current += arrayElementSize;

                    if (si.State == WTS_CONNECTSTATE_CLASS.WTSActive && si.SessionID == targetSessionId)
                    {
                        activeSessionId = si.SessionID;
                    }
                }
            }

            // If enumerating did not work, fall back to the old method
            if (activeSessionId == INVALID_SESSION_ID)
            {
                activeSessionId = WTSGetActiveConsoleSessionId();
            }

            if (WTSQueryUserToken(activeSessionId, ref hImpersonationToken) != 0)
            {
                // Convert the impersonation token to a primary token
                bResult = DuplicateTokenEx(hImpersonationToken, 0, IntPtr.Zero,
                    (int)SECURITY_IMPERSONATION_LEVEL.SecurityImpersonation, (int)TOKEN_TYPE.TokenPrimary,
                    ref phUserToken);

                CloseHandle(hImpersonationToken);
            }

            return bResult;
        }

        public static PROCESS_INFORMATION StartProcessAsCurrentUser(int targetSessionId, string appPath, string cmdLine = null, bool visible = true)
        {
            var hUserToken = IntPtr.Zero;
            var startInfo = new STARTUPINFO();
            var procInfo = new PROCESS_INFORMATION();
            var procInfoRes = new PROCESS_INFORMATION();
            var pEnv = IntPtr.Zero;
            int iResultOfCreateProcessAsUser;

            startInfo.cb = Marshal.SizeOf(typeof(STARTUPINFO));

            try
            {
                if (!GetSessionUserToken(ref hUserToken, targetSessionId))
                {
                    throw new Exception("StartProcessAsCurrentUser: GetSessionUserToken for session "+targetSessionId+" failed.");
                }

                uint dwCreationFlags = CREATE_UNICODE_ENVIRONMENT | (uint)(visible ? CREATE_NEW_CONSOLE : CREATE_NO_WINDOW);
                startInfo.wShowWindow = (short)(visible ? SW.SW_SHOW : SW.SW_HIDE);
                startInfo.lpDesktop = "winsta0\\default";

                if (!CreateEnvironmentBlock(ref pEnv, hUserToken, false))
                {
                    throw new Exception("StartProcessAsCurrentUser: CreateEnvironmentBlock failed.");
                }

                if (!CreateProcessAsUser(hUserToken,
                    appPath, // Application Name
                    cmdLine, // Command Line
                    IntPtr.Zero,
                    IntPtr.Zero,
                    false,
                    dwCreationFlags,
                    pEnv,
                    null, // Working directory
                    ref startInfo,
                    out procInfo))
                {
                    iResultOfCreateProcessAsUser = Marshal.GetLastWin32Error();
                    throw new Exception("StartProcessAsCurrentUser: CreateProcessAsUser failed.  Error Code " + iResultOfCreateProcessAsUser);
                }
                procInfoRes = procInfo;
                iResultOfCreateProcessAsUser = Marshal.GetLastWin32Error();
            }
            finally
            {
                
                CloseHandle(hUserToken);
                if (pEnv != IntPtr.Zero)
                {
                    DestroyEnvironmentBlock(pEnv);
                }
                CloseHandle(procInfo.hThread);
                CloseHandle(procInfo.hProcess);
            }

            return procInfoRes;
        }

    }
}
"@
Function Set-KnownFolderPath {
    Param (
            [Parameter(Mandatory = $true)][ValidateSet('AddNewPrograms', 'AdminTools', 'AppUpdates', 'CDBurning', 'ChangeRemovePrograms', 'CommonAdminTools', 'CommonOEMLinks', 'CommonPrograms', `
            'CommonStartMenu', 'CommonStartup', 'CommonTemplates', 'ComputerFolder', 'ConflictFolder', 'ConnectionsFolder', 'Contacts', 'ControlPanelFolder', 'Cookies', `
            'Desktop', 'Documents', 'Downloads', 'Favorites', 'Fonts', 'Games', 'GameTasks', 'History', 'InternetCache', 'InternetFolder', 'Links', 'LocalAppData', `
            'LocalAppDataLow', 'LocalizedResourcesDir', 'Music', 'NetHood', 'NetworkFolder', 'OriginalImages', 'PhotoAlbums', 'Pictures', 'Playlists', 'PrintersFolder', `
            'PrintHood', 'Profile', 'ProgramData', 'ProgramFiles', 'ProgramFilesX64', 'ProgramFilesX86', 'ProgramFilesCommon', 'ProgramFilesCommonX64', 'ProgramFilesCommonX86', `
            'Programs', 'Public', 'PublicDesktop', 'PublicDocuments', 'PublicDownloads', 'PublicGameTasks', 'PublicMusic', 'PublicPictures', 'PublicVideos', 'QuickLaunch', `
            'Recent', 'RecycleBinFolder', 'ResourceDir', 'RoamingAppData', 'SampleMusic', 'SamplePictures', 'SamplePlaylists', 'SampleVideos', 'SavedGames', 'SavedSearches', `
            'SEARCH_CSC', 'SEARCH_MAPI', 'SearchHome', 'SendTo', 'SidebarDefaultParts', 'SidebarParts', 'StartMenu', 'Startup', 'SyncManagerFolder', 'SyncResultsFolder', `
            'SyncSetupFolder', 'System', 'SystemX86', 'Templates', 'TreeProperties', 'UserProfiles', 'UsersFiles', 'Videos', 'Windows', 'Objects3D')]
            [string]$KnownFolder,
            [Parameter(Mandatory = $true)][string]$Path
    )

    # Define known folder GUIDs
    $KnownFolders = @{
        'AddNewPrograms' = 'de61d971-5ebc-4f02-a3a9-6c82895e5c04';'AdminTools' = '724EF170-A42D-4FEF-9F26-B60E846FBA4F';'AppUpdates' = 'a305ce99-f527-492b-8b1a-7e76fa98d6e4'; 'Objects3D' = '31C0DD25-9439-4F12-BF41-7FF4EDA38722';
        'CDBurning' = '9E52AB10-F80D-49DF-ACB8-4330F5687855';'ChangeRemovePrograms' = 'df7266ac-9274-4867-8d55-3bd661de872d';'CommonAdminTools' = 'D0384E7D-BAC3-4797-8F14-CBA229B392B5';
        'CommonOEMLinks' = 'C1BAE2D0-10DF-4334-BEDD-7AA20B227A9D';'CommonPrograms' = '0139D44E-6AFE-49F2-8690-3DAFCAE6FFB8';'CommonStartMenu' = 'A4115719-D62E-491D-AA7C-E74B8BE3B067';
        'CommonStartup' = '82A5EA35-D9CD-47C5-9629-E15D2F714E6E';'CommonTemplates' = 'B94237E7-57AC-4347-9151-B08C6C32D1F7';'ComputerFolder' = '0AC0837C-BBF8-452A-850D-79D08E667CA7';
        'ConflictFolder' = '4bfefb45-347d-4006-a5be-ac0cb0567192';'ConnectionsFolder' = '6F0CD92B-2E97-45D1-88FF-B0D186B8DEDD';'Contacts' = '56784854-C6CB-462b-8169-88E350ACB882';
        'ControlPanelFolder' = '82A74AEB-AEB4-465C-A014-D097EE346D63';'Cookies' = '2B0F765D-C0E9-4171-908E-08A611B84FF6';'Desktop' = @('B4BFCC3A-DB2C-424C-B029-7FE99A87C641');
        'Documents' = @('FDD39AD0-238F-46AF-ADB4-6C85480369C7','f42ee2d3-909f-4907-8871-4c22fc0bf756');'Downloads' = @('374DE290-123F-4565-9164-39C4925E467B','7d83ee9b-2244-4e70-b1f5-5393042af1e4');
        'Favorites' = '1777F761-68AD-4D8A-87BD-30B759FA33DD';'Fonts' = 'FD228CB7-AE11-4AE3-864C-16F3910AB8FE';'Games' = 'CAC52C1A-B53D-4edc-92D7-6B2E8AC19434';
        'GameTasks' = '054FAE61-4DD8-4787-80B6-090220C4B700';'History' = 'D9DC8A3B-B784-432E-A781-5A1130A75963';'InternetCache' = '352481E8-33BE-4251-BA85-6007CAEDCF9D';
        'InternetFolder' = '4D9F7874-4E0C-4904-967B-40B0D20C3E4B';'Links' = 'bfb9d5e0-c6a9-404c-b2b2-ae6db6af4968';'LocalAppData' = 'F1B32785-6FBA-4FCF-9D55-7B8E7F157091';
        'LocalAppDataLow' = 'A520A1A4-1780-4FF6-BD18-167343C5AF16';'LocalizedResourcesDir' = '2A00375E-224C-49DE-B8D1-440DF7EF3DDC';'Music' = @('4BD8D571-6D19-48D3-BE97-422220080E43','a0c69a99-21c8-4671-8703-7934162fcf1d');
        'NetHood' = 'C5ABBF53-E17F-4121-8900-86626FC2C973';'NetworkFolder' = 'D20BEEC4-5CA8-4905-AE3B-BF251EA09B53';'OriginalImages' = '2C36C0AA-5812-4b87-BFD0-4CD0DFB19B39';
        'PhotoAlbums' = '69D2CF90-FC33-4FB7-9A0C-EBB0F0FCB43C';'Pictures' = @('33E28130-4E1E-4676-835A-98395C3BC3BB','0ddd015d-b06c-45d5-8c4c-f59713854639');
        'Playlists' = 'DE92C1C7-837F-4F69-A3BB-86E631204A23';'PrintersFolder' = '76FC4E2D-D6AD-4519-A663-37BD56068185';'PrintHood' = '9274BD8D-CFD1-41C3-B35E-B13F55A758F4';
        'Profile' = '5E6C858F-0E22-4760-9AFE-EA3317B67173';'ProgramData' = '62AB5D82-FDC1-4DC3-A9DD-070D1D495D97';'ProgramFiles' = '905e63b6-c1bf-494e-b29c-65b732d3d21a';
        'ProgramFilesX64' = '6D809377-6AF0-444b-8957-A3773F02200E';'ProgramFilesX86' = '7C5A40EF-A0FB-4BFC-874A-C0F2E0B9FA8E';'ProgramFilesCommon' = 'F7F1ED05-9F6D-47A2-AAAE-29D317C6F066';
        'ProgramFilesCommonX64' = '6365D5A7-0F0D-45E5-87F6-0DA56B6A4F7D';'ProgramFilesCommonX86' = 'DE974D24-D9C6-4D3E-BF91-F4455120B917';'Programs' = 'A77F5D77-2E2B-44C3-A6A2-ABA601054A51';
        'Public' = 'DFDF76A2-C82A-4D63-906A-5644AC457385';'PublicDesktop' = 'C4AA340D-F20F-4863-AFEF-F87EF2E6BA25';'PublicDocuments' = 'ED4824AF-DCE4-45A8-81E2-FC7965083634';
        'PublicDownloads' = '3D644C9B-1FB8-4f30-9B45-F670235F79C0';'PublicGameTasks' = 'DEBF2536-E1A8-4c59-B6A2-414586476AEA';'PublicMusic' = '3214FAB5-9757-4298-BB61-92A9DEAA44FF';
        'PublicPictures' = 'B6EBFB86-6907-413C-9AF7-4FC2ABF07CC5';'PublicVideos' = '2400183A-6185-49FB-A2D8-4A392A602BA3';'QuickLaunch' = '52a4f021-7b75-48a9-9f6b-4b87a210bc8f';
        'Recent' = 'AE50C081-EBD2-438A-8655-8A092E34987A';'RecycleBinFolder' = 'B7534046-3ECB-4C18-BE4E-64CD4CB7D6AC';'ResourceDir' = '8AD10C31-2ADB-4296-A8F7-E4701232C972';
        'RoamingAppData' = '3EB685DB-65F9-4CF6-A03A-E3EF65729F3D';'SampleMusic' = 'B250C668-F57D-4EE1-A63C-290EE7D1AA1F';'SamplePictures' = 'C4900540-2379-4C75-844B-64E6FAF8716B';
        'SamplePlaylists' = '15CA69B3-30EE-49C1-ACE1-6B5EC372AFB5';'SampleVideos' = '859EAD94-2E85-48AD-A71A-0969CB56A6CD';'SavedGames' = '4C5C32FF-BB9D-43b0-B5B4-2D72E54EAAA4';
        'SavedSearches' = '7d1d3a04-debb-4115-95cf-2f29da2920da';'SEARCH_CSC' = 'ee32e446-31ca-4aba-814f-a5ebd2fd6d5e';'SEARCH_MAPI' = '98ec0e18-2098-4d44-8644-66979315a281';
        'SearchHome' = '190337d1-b8ca-4121-a639-6d472d16972a';'SendTo' = '8983036C-27C0-404B-8F08-102D10DCFD74';'SidebarDefaultParts' = '7B396E54-9EC5-4300-BE0A-2482EBAE1A26';
        'SidebarParts' = 'A75D362E-50FC-4fb7-AC2C-A8BEAA314493';'StartMenu' = '625B53C3-AB48-4EC1-BA1F-A1EF4146FC19';'Startup' = 'B97D20BB-F46A-4C97-BA10-5E3608430854';
        'SyncManagerFolder' = '43668BF8-C14E-49B2-97C9-747784D784B7';'SyncResultsFolder' = '289a9a43-be44-4057-a41b-587a76d7e7f9';'SyncSetupFolder' = '0F214138-B1D3-4a90-BBA9-27CBC0C5389A';
        'System' = '1AC14E77-02E7-4E5D-B744-2EB1AE5198B7';'SystemX86' = 'D65231B0-B2F1-4857-A4CE-A8E7C6EA7D27';'Templates' = 'A63293E8-664E-48DB-A079-DF759E0509F7';
        'TreeProperties' = '5b3749ad-b49f-49c1-83eb-15370fbd4882';'UserProfiles' = '0762D272-C50A-4BB0-A382-697DCD729B80';'UsersFiles' = 'f3ce0f7c-4901-4acc-8648-d5d44b04ef8f';
        'Videos' = @('18989B1D-99B5-455B-841C-AB7C74E4DDFC','35286a68-3c57-41a1-bbb1-0eae73d76c95');'Windows' = 'F38BF404-1D43-42F2-9305-67DE0B28FC23';
    }


########################################################################
##END OF CONFIGURATION SECTION, DO NOT CHANGE ANYTHING BELOW THIS LINE##
########################################################################

    $Type = ([System.Management.Automation.PSTypeName]'KnownFolders').Type
    If (-not $Type) {
        $Signature = @'
[DllImport("shell32.dll")]
public extern static int SHSetKnownFolderPath(ref Guid folderId, uint flags, IntPtr token, [MarshalAs(UnmanagedType.LPWStr)] string path);
'@
        $Type = Add-Type -MemberDefinition $Signature -Name 'KnownFolders' -Namespace 'SHSetKnownFolderPath' -PassThru
    }

	If (!(Test-Path $Path -PathType Container)) {
		New-Item -Path $Path -Type Directory -Force -Verbose
    }

    If (Test-Path $Path -PathType Container) {
        ForEach ($guid in $KnownFolders[$KnownFolder]) {
            $result = $Type::SHSetKnownFolderPath([ref]$guid, 0, 0, $Path)
            If ($result -ne 0) {
                $errormsg = "Error redirecting $($KnownFolder). Return code $($result) = $((New-Object System.ComponentModel.Win32Exception($result)).message)"
                Throw `$errormsg
            }
        }
    } Else {
        Throw New-Object System.IO.DirectoryNotFoundException "Could not find part of the path $Path."
    }
    Return $Path
}

Function Get-KnownFolderPath {
    Param (
            [Parameter(Mandatory = $true)]
            [ValidateSet('AdminTools','ApplicationData','CDBurning','CommonAdminTools','CommonApplicationData','CommonDesktopDirectory','CommonDocuments','CommonMusic',`
            'CommonOemLinks','CommonPictures','CommonProgramFiles','CommonProgramFilesX86','CommonPrograms','CommonStartMenu','CommonStartup','CommonTemplates',`
            'CommonVideos','Cookies','Downloads','Desktop','DesktopDirectory','Favorites','Fonts','History','InternetCache','LocalApplicationData','LocalizedResources','MyComputer',`
            'MyDocuments','MyMusic','MyPictures','MyVideos','NetworkShortcuts','Personal','PrinterShortcuts','ProgramFiles','ProgramFilesX86','Programs','Recent',`
            'Resources','SendTo','StartMenu','Startup','System','SystemX86','Templates','UserProfile','Windows', 'Objects3D')]
            [string]$KnownFolder
    )
    if($KnownFolder -eq "Downloads"){
        Return $Null
    }else{
        Return [Environment]::GetFolderPath($KnownFolder)
    }
}

Function Redirect-Folder {
    Param (
        [Parameter(Mandatory = $true)]$GetFolder,
        [Parameter(Mandatory = $true)]$SetFolder,
        [Parameter(Mandatory = $true)]$Target,
		$copyExistingFiles,
        $setEnvironmentVariable
    )

    $Folder = Get-KnownFolderPath -KnownFolder $GetFolder
    If ($Folder -ne $Target) {
        Set-KnownFolderPath -KnownFolder $SetFolder -Path $Target
        if($copyExistingFiles -and $Folder -and (Test-Path $Folder -PathType Container) -and (Test-Path $Target -PathType Container)){
            Get-ChildItem -Path $Folder -ErrorAction Continue | Copy-Item -Destination $Target -Recurse -Container -Force -Confirm:$False -ErrorAction Continue
        }
        Attrib +h $Folder
    }
    if($setEnvironmentVariable){
        [Environment]::SetEnvironmentVariable($GetFolder, $Target, "User")
    }
}

Function Redirect-SpecialFolder {
    Param(
        [Parameter(Mandatory = $true)]$originalLocation,
        [Parameter(Mandatory = $true)]$target,
        $hide,
        $copyExistingFiles
    )

    #create source location folder if needed
    if(!(Test-Path $originalLocation)){
        $copyExistingFiles = $False
        Write-Output "created folder structure to $originalLocation"
        try{New-Item (Split-Path -Path $originalLocation -Parent) -ItemType Directory -Force}catch{$Null}
    }else{
        if((Get-Item $originalLocation).Target -eq $target){
            Write-Output "Hard link already pointing to correct location"
            return $True
        }
    }

    #create target location if needed
    if(!(Test-Path $target)){
        Write-Output "created folder $target"
        New-Item $target -ItemType Directory -Force
    }
    
    #Check if the location we're redirecting from exists and if we need to copy anything. To create a hardlink, this location must not exist
    if((Test-Path $originalLocation)){
        if($copyExistingFiles){
            try{Get-ChildItem -Path $originalLocation -ErrorAction Continue | Copy-Item -Destination $target -Recurse -Container -Force -Confirm:$False -ErrorAction Continue}catch{$Null}
            Write-Output "Original files copied"
        }
        Remove-Item $originalLocation -Recurse -Force -Confirm:$False
    }


    #create a hard link
    invoke-expression "cmd /c mklink /J `"$originalLocation`" `"$target`""
    Write-Output "hard link created or updated"
    if($hide){
        Attrib +h $target
        Write-Output "$target hidden"
    }
}



#enable UEV

#####onedrive account config
$HKLMregistryPath = 'HKLM:\SOFTWARE\Policies\Microsoft\OneDrive'##Path to HKLM keys
$DiskSizeregistryPath = 'HKLM:\SOFTWARE\Policies\Microsoft\OneDrive\DiskSpaceCheckThresholdMB'##Path to max disk size key
$TenantGUID = '72f988bf-86f1-41af-91ab-2d7cd011db47'
if(!(Test-Path $HKLMregistryPath)){New-Item -Path $HKLMregistryPath -Force}
if(!(Test-Path $DiskSizeregistryPath)){New-Item -Path $DiskSizeregistryPath -Force}
New-ItemProperty -Path $HKLMregistryPath -Name 'SilentAccountConfig' -Value '1' -PropertyType DWORD -Force | Out-Null ##Enable silent account configuration
New-ItemProperty -Path $DiskSizeregistryPath -Name $TenantGUID -Value '102400' -PropertyType DWORD -Force | Out-Null ##Set max OneDrive threshold before prompting

####OD4B Redirection
[void] [System.Reflection.Assembly]::LoadWithPartialName("System.Web")

#Wait until Onedrive client is running, and has been running for at least 3 seconds
while($true){
    try{
        $o4bProcessInfo = @(get-process -name "onedrive" -ErrorAction SilentlyContinue)[0]
        if($o4bProcessInfo -and (New-TimeSpan -Start $o4bProcessInfo.StartTime -End (Get-Date)).TotalSeconds -gt 3){
            Write-Output "Detected a running instance of Onedrive"
            break
        }else{
            Write-Output "Onedrive client not yet running..."
            Sleep -s 3
        }
    }catch{
        Write-Output "Onedrive client not yet running..."
    }
}

#wait until Onedrive has been configured properly (ie: linked to user's account)
$odAccount = $Null
$companyName = $Null
$userEmail = $Null
:accounts while($true){
    #check if the Accounts key exists (Onedrive creates this)
    try{
        if(Test-Path HKCU:\Software\Microsoft\OneDrive\Accounts){
            #look for a Business key with our configured tenant ID that is properly filled out
            foreach($account in @(Get-ChildItem HKCU:\Software\Microsoft\OneDrive\Accounts)){
                if($account.GetValue("Business") -eq 1 -and $account.GetValue("ConfiguredTenantId") -eq $tenantId){
                    Write-Output "Detected $($account.GetValue("UserName")), linked to tenant $($account.GetValue("DisplayName")) ($($tenantId))"
                    if(Test-Path $account.GetValue("UserFolder")){
                        $odAccount = $account
                        Write-Output "Folder located in $($odAccount.GetValue("UserFolder"))"
                        $companyName = $account.GetValue("DisplayName").Replace("/"," ")
                        $userEmail = $account.GetValue("UserEmail")
                        break accounts
                    }else{
                        Write-Output "But no user folder detected yet (UserFolder key is empty)"
                    }
                }
            }             
        }
    }catch{$Null}
    Write-Output "Onedrive not yet fully configured for this user..."
    Sleep -s 2
}

#now check for any sharepoint/teams libraries we have to link:
:libraries foreach($library in $listOfLibrariesToAutoMount){
    Write-Progress -Activity "Redirecting to SP Libraries"
    #First check if any non-OD4B libraries are configured already
    $compositeTitle = "$($library.siteTitle) - $($library.listTitle)"
    $expectedPath = "$($odAccount.Name)\Tenants\$companyName".Replace("HKEY_CURRENT_USER","HKCU:")
    if(Test-Path $expectedPath){
        #now check if the current library is already syncing
        foreach($value in (Get-Item $expectedPath -ErrorAction SilentlyContinue).GetValueNames()){
            if($value -like "*$compositeTitle"){
                Write-Output "$compositeTitle is already syncing, skipping :)"
                continue libraries
            }
        }
    }
    
    #no library is syncing yet, or at least not the one we want
    #first, delete any existing content (this can happen if the user has manually deleted the sync relationship
    if(test-path "$($Env:USERPROFILE)\$companyName\$compositeTitle"){
        Write-Output "User has removed sync relationship for $compositeTitle, removing existing content and recreating..."
        Remove-Item  "$($Env:USERPROFILE)\$companyName\$compositeTitle" -Force -Confirm:$False -Recurse
    }else{
        Write-Output "First time syncing $compositeTitle, creating link..."
    }

    #wait for it to start syncing
    $slept = 10
    while($true){
        if(Test-Path "$($Env:USERPROFILE)\$companyName\$compositeTitle"){
            Write-Output "Detected existence of $compositeTitle"
            break
        }else{
            Write-Output "Waiting for $compositeTitle to get connected..."
            if($slept % 10 -eq 0){    
                #send ODOPEN command
                Write-Output "Sending ODOpen command..."
                start "odopen://sync/?$($library.syncUrl)&userEmail=$([uri]::EscapeDataString($userEmail))&webtitle=$([uri]::EscapeDataString($library.siteTitle))&listTitle=$([uri]::EscapeDataString($library.listTitle))"
            }
            Sleep -s 1
            $slept += 1
        }
    }
}

#everything has been mounted, time to process Folder Redirections
foreach($redirection in $listOfFoldersToRedirect){
    Write-Progress -Activity "Redirecting Folders to OneDrive Templates"
    #onedrive redirection vs SpO/Teams libraries
    if($redirection.targetLocation -eq "onedrive"){
        $targetPath = Join-Path -Path $odAccount.GetValue("UserFolder") -ChildPath $redirection.targetPath
    }else{
        $libraryInfo = $listOfLibrariesToAutoMount[$([Int]$redirection.targetLocation)]
        $compositeTitle = "$($libraryInfo.siteTitle) - $($libraryInfo.listTitle)"
        $targetPath = Join-Path -Path (Get-Item "$($Env:USERPROFILE)\$companyName\$compositeTitle").FullName -ChildPath $redirection.targetPath
    }
    Write-Output "Redirecting $($redirection.knownFolderInternalName) to $targetPath"
    try{
        Redirect-Folder -GetFolder $redirection.knownFolderInternalName -SetFolder $redirection.knownFolderInternalIdentifier -Target $targetPath -copyExistingFiles $redirection.copyExistingFiles -setEnvironmentVariable $redirection.setEnvironmentVariable
        Write-Output "Redirected $($redirection.knownFolderInternalName) to $targetPath"
    }catch{
        Write-Output "Failed to redirect $($redirection.knownFolderInternalName) to $targetPath"
    }
}
Redirect-SpecialFolder -originalLocation "$env:USERPROFILE\3d Objects" -target "$env:OneDriveCommercial\3d"
#all normal folder redirection is done, process symbolic links
foreach($symLink in $listOfOtherFoldersToRedirect){
    Write-Progress -Activity "Redirecting Special Folders to OneDrive Templates"
    #onedrive redirection vs SpO/Teams libraries
    if($symLink.targetLocation -eq "onedrive"){
        $targetPath = Join-Path -Path $odAccount.GetValue("UserFolder") -ChildPath $symLink.targetPath   
    }else{
        $libraryInfo = $listOfLibrariesToAutoMount[$([Int]$symLink.targetLocation)]
        $compositeTitle = "$($libraryInfo.siteTitle) - $($libraryInfo.listTitle)"
        $targetPath = Join-Path -Path (Get-Item "$($Env:USERPROFILE)\$companyName\$compositeTitle").FullName -ChildPath $symLink.targetPath
    }
    Write-Output "Redirecting $($symLink.originalLocation) to $targetPath"
    try{
        Redirect-SpecialFolder -originalLocation $symLink.originalLocation -target $targetPath -hide $symLink.hide -copyExistingFiles $symLink.copyExistingFiles
        Write-Output "Redirected $($symLink.originalLocation) to $targetPath"
    }catch{
        Write-Output "Failed to redirect $($symLink.originalLocation) to $targetPath"
    }
}


####Download UEV Templates and enable UEV
$pathexists = Test-path -path "$env:temp\systemtemplates"
if ($pathexists -eq $true) {
    Push-Location "$env:temp\systemtemplates"
    #Push-Location "$inboxTemplatesSrc"
    $srcTemplates = Get-AzureBlobItem -uri "https://azimuevtemplates.blob.core.windows.net/uevtemplates/?comp=list"   
    ForEach ($template in $srcTemplates) {
        Write-Progress -Activity "Enabling UEV Templates"
        # Only download if the file has a .xml extension
        If ($template.Name -like "*.xml") {
            $targetTemplate =  $template.Name
                $iwrParams = @{
                    Uri              = $template.Url
                    OutFile          = "$env:temp\systemtemplates\$targetTemplate"
                    ContentType      = "text/xml"
                   # $UseBasicParsing = $True
                    Headers          = @{ "x-ms-version" = "2017-11-09" }
                }
                Invoke-WebRequest @iwrParams -Method Get -ErrorAction:SilentlyContinue
                Get-childitem Copy-Item -path "$env:temp\systemtemplates\*" | Copy-item -Destination $inboxTemplatesSrc -Force

            }
        }
    }
else {
    write-host "$pathexists is $false"
    mkdir "$env:OneDriveCommercial\uev"
    mkdir "$env:OneDriveCommercial\uev\templates"
    mkdir "$env:OneDriveCommercial\uev\settings"
    mkdir "$env:temp\systemtemplates"
    Push-Location "$env:temp\systemtemplates"
    #Push-Location "$inboxTemplatesSrc"
    $srcTemplates = Get-AzureBlobItem -uri "https://azimuevtemplates.blob.core.windows.net/uevtemplates/?comp=list"   
    ForEach ($template in $srcTemplates) {
        Write-Progress -Activity "Enabling UEV Templates"
        # Only download if the file has a .xml extension
        If ($template.Name -like "*.xml") {
            $targetTemplate =  $template.Name
                $iwrParams = @{
                    Uri              = $template.Url
                    OutFile          = "$env:temp\systemtemplates\$targetTemplate"
                    ContentType      = "text/xml"
                   # $UseBasicParsing = $True
                    Headers          = @{ "x-ms-version" = "2017-11-09" }
                }
                Invoke-WebRequest @iwrParams -Method Get -ErrorAction:SilentlyContinue
                Get-childitem Copy-Item -path "$env:temp\systemtemplates\*" | Copy-item -Destination $inboxTemplatesSrc -Force
            }
        }
}
#####enable uev
Import-Module -name "UEV"
Enable-Uev 
####setup UEV
Write-Verbose -Message "$($MyInvocation.MyCommand): Unregistering existing templates."
Get-UevTemplate | Unregister-UevTemplate -ErrorAction SilentlyContinue
$UEVSettingsStoragePath = "$env:OneDriveCommercial\uev\settings"
$UserTemplates = "$env:OneDriveCommercial\uev\templates"
$inboxTemplatesSrc = "$env:ProgramData\Microsoft\UEV\InboxTemplates"

get-childitem -Path $UserTemplates | Copy-Item -Destination $inboxTemplatesSrc -Force
$templates = Get-ChildItem -path $inboxTemplates
$UEVSettingsStoragePath

ForEach ($template in $Templates) {
    Write-Verbose -Message "$($MyInvocation.MyCommand): Registering template: $template."
    Register-UevTemplate -Path "$inboxTemplatesSrc\$template" -ErrorAction SilentlyContinue
}
$uevParameters = @{
    Computer                            = $True
    DisableSyncProviderPing             = $True
    DisableWaitForSyncOnLogon           = $True
    DisableSyncUnlistedWindows8Apps     = $True
    EnableDontSyncWindows8AppSettings   = $True
    EnableSettingsImportNotify          = $True
    EnableSync                          = $True
    EnableWaitForSyncOnApplicationStart = $True
    SettingsStoragePath                 = $UEVSettingsStoragePath
    SyncMethod                          = "External"
    WaitForSyncTimeoutInMilliseconds    = "2000"
}
Set-UevConfiguration @uevParameters

throw "Altered Carbon Sleeve Download Complete"
