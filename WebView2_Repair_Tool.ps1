###########################################################################################################################################################
#.SYNOPSIS
#    This script removes any issues preventing a newer version of WebView2 from installing.
#.DESCRIPTION
#   In an environment where firewalls, GPOs, and SCCM prevent certain Microsoft products, like WebView2, from updating regularly, this script aims  
#   to perform minor repairs that allow these applications to be updated via SCCM rather than their automated update process.
#
#   WebView2 is an evergreen product, meaning it should automatically update on its own. However, due to policies blocking updates, an alternative 
#   method is needed to ensure WebView2 is updated properly. Since WebView2 usually replaces itself during the normal update process, deploying a 
#   newer version via SCCM will often fail because it detects that WebView2 is already installed. To work around this, we must install WebView2 side by side.
#
#   This script removes image file execution option (IFEO) 'debugger' value and removes any registry entries pointing to the older version of WebView2, allowing 
#   the newer version to be installed. It then installs the latest version from the script directory, terminates any parent process running WebView2, 
#   cleans up the older version, and restarts the terminated parent processes. This process is entirely silent.
#.NOTES
#    File Name      : WebView2_Repair_Tool.ps1
#    Author         : John Seals
#    Prerequisite   : PowerShell 5.1 or later
#    GNU GENERAL PUBLIC LICENSE (2025) - John Seals (SealsTech)
#.LINK
#   
###########################################################################################################################################################

# Step 1: Remove IFEO "Debugger" stubs that silently block Edge/WebView2 installers
#   Targets: msedge.exe, msedgewebview2.exe, MicrosoftEdgeUpdate.exe
#   Behavior: remove only if the Debugger is a known blocker (e.g., systray.exe).
#             To override and remove any Debugger, set $Env:WV2_FORCE_IFEO_FIX=1 before running.
$ifeoBase   = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options'
$targets    = @('msedge.exe','msedgewebview2.exe','MicrosoftEdgeUpdate.exe')
$blockList  = @([IO.Path]::Combine($env:SystemRoot,'System32','systray.exe'))  # canonical path
$force      = ($env:WV2_FORCE_IFEO_FIX -eq '1')

# helper to normalize a Debugger string to its first executable path (expand env vars; strip quotes/args)
function _Normalize-DebuggerPath([string]$s) {
    if ([string]::IsNullOrWhiteSpace($s)) { return $null }
    $m = [regex]::Match($s, '^"([^"]+)"|^(\S+)')
    $raw = if ($m.Groups[1].Success) { $m.Groups[1].Value } else { $m.Groups[2].Value }
    $expanded = [Environment]::ExpandEnvironmentVariables($raw)
    try { (Resolve-Path -LiteralPath $expanded -ErrorAction Stop).Path } catch { $expanded }
}

foreach ($name in $targets) {
    $key = Join-Path -Path $ifeoBase -ChildPath $name
    if (Test-Path -LiteralPath $key) {
        try {
            $val = Get-ItemProperty -LiteralPath $key -Name 'Debugger' -ErrorAction SilentlyContinue
            if ($null -ne $val) {
                $dbgPath = _Normalize-DebuggerPath ($val.Debugger)
                if ($force -or ($dbgPath -ne $null -and ($blockList -contains $dbgPath))) {
                    Remove-ItemProperty -LiteralPath $key -Name 'Debugger' -ErrorAction SilentlyContinue
                }
                # else: leave legitimate debuggers (windbg, vsjitdebugger, etc.) untouched
            }
        } catch {
            # intentional no-op; script remains fully silent
        }
    }
}

# Step 2: Uninstall WebView2 by removing its registry keys
Get-ItemProperty -Path hklm:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\* | 
    Where-Object { $_.name -like "*WebView2*" } | Remove-Item -ErrorAction SilentlyContinue

# Step 3: Determine the script's directory (compatible with all PowerShell versions)
$scriptPath = $PSScriptRoot
if (-not $scriptPath) {
    $scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
}

# Step 4: Define the path for the WebView2 installer (in the same folder as this script)
$installerPath = Join-Path -Path $scriptPath -ChildPath "MicrosoftEdgeWebView2RuntimeInstallerX64.exe"

# Step 5: Reinstall WebView2 using the installer if it exists
if (Test-Path $installerPath) {
    Start-Process -FilePath $installerPath -ArgumentList "/silent /install" -NoNewWindow -Wait
}

# Step 6: Find all running WebView2 processes
$webviewProcesses = Get-CimInstance Win32_Process | Where-Object { $_.Name -match "msedgewebview2" } -ErrorAction SilentlyContinue

# Initialize an array to store parent processes before killing WebView2
$parentProcesses = @()

# Define a list of critical system processes that should not be killed
$excludedParents = @("explorer.exe", "svchost.exe", "services.exe", "wininit.exe", "winlogon.exe")

foreach ($process in $webviewProcesses) {
    # Get the parent process of each WebView2 instance
    $parentProcess = Get-CimInstance Win32_Process | Where-Object { $_.ProcessId -eq $process.ParentProcessId } -ErrorAction SilentlyContinue

    # Store parent process details if it's not in the exclusion list
    if ($parentProcess -and ($parentProcess.Name -notin $excludedParents)) {
        $parentProcesses += [PSCustomObject]@{
            Name        = $parentProcess.Name
            ProcessId   = $parentProcess.ProcessId
            CommandLine = $parentProcess.CommandLine  # Store the original command line to restart it later
        }

        # Kill the WebView2 process
        Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
    }
}

# Step 7: Kill Parent Processes (only if they are not in the excluded list)
foreach ($parent in $parentProcesses) {
    Stop-Process -Id $parent.ProcessId -Force -ErrorAction SilentlyContinue
}

# Step 8: Cleanup older versions of WebView2
# Get all folders in the WebView2 installation directory that follow a version number pattern
$items = Get-Item -Path "${env:ProgramFiles(x86)}\Microsoft\EdgeWebView\Application\*" -ErrorAction SilentlyContinue | 
    Where-Object { $_.Name -match '^\d+(\.\d+)+$' }  # Match version number folders

# Find the highest version number (latest version)
$latestVersion = ($items | Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1)

# Remove all WebView2 versions except the latest
$items | Where-Object { $_.FullName -ne $latestVersion.FullName } | ForEach-Object {
    Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
}

# Step 9: Restart Parent Processes AFTER Cleanup (No CMD Window)
foreach ($parent in $parentProcesses) {
    if ($parent.CommandLine) {
        # Restart the parent process using its original command line, hidden from the user
        Start-Process -FilePath "powershell.exe" -ArgumentList "-Command Start-Process -FilePath 'cmd.exe' -ArgumentList '/c $($parent.CommandLine)' -WindowStyle Hidden" -WindowStyle Hidden -ErrorAction SilentlyContinue
    }
}
