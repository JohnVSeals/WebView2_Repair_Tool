# WebView2_Repair_Tool
A PowerShell script that removes registry conflicts, cleans up outdated WebView2 versions, and ensures successful SCCM deployments by terminating and restarting necessary processes—all silently.

## Overview

This script is designed to **resolve issues preventing WebView2 updates** in managed environments where **firewalls, Group Policies (GPOs), and SCCM** restrict automatic updates. 

WebView2 is an **evergreen product**, meaning it should update automatically. However, **SCCM deployments** may fail if a newer version of WebView2 is already installed due to existing registry entries. This script **removes conflicting registry keys, cleans up old WebView2 versions, and ensures that SCCM can successfully deploy newer WebView2 versions**.

Additionally, it **identifies and terminates parent processes running WebView2, removes outdated versions, and restarts the necessary processes**, ensuring everything runs **silently** in the background.

## Features
✅ **Removes registry entries blocking SCCM WebView2 installations**  
✅ **Installs the latest WebView2 version from the script directory**  
✅ **Identifies and terminates parent processes using WebView2**  
✅ **Cleans up older WebView2 versions, keeping only the latest**  
✅ **Restarts terminated parent processes**  
✅ **Runs fully silent—no user prompts or visible command windows**  

## Compatibility

| PowerShell Version  | Supported | Notes |
|----------------------|-----------|-------|
| **PowerShell 7+**   | ✅ Yes | Fully supported. |
| **PowerShell 5.1**  | ✅ Yes | Default for Windows 10 & Windows Server 2016+. |
| **PowerShell 4.0**  | ⚠️ Partial | Requires replacing `Get-CimInstance` with `Get-WmiObject`. |
| **PowerShell 3.0**  | ⚠️ Limited | Script will work with modifications but is not recommended. |
| **PowerShell 2.0**  | ❌ No | `$PSScriptRoot` and `Get-CimInstance` are not available. |

## Requirements
 1. **Latest version of 'WebView2 Standalone installer'**
    a. [Microsoft Developer Page](https://developer.microsoft.com/en-us/microsoft-edge/webview2)

## Usage

1. **Place the script (`WebView2_Repair_Tool.ps1`) and the WebView2 installer (`MicrosoftEdgeWebView2RuntimeInstallerX64.exe`) in the same folder.**
2. **Run the script using PowerShell (as administrator)**
   ```powershell
   .\WebView2_Repair_Tool.ps1