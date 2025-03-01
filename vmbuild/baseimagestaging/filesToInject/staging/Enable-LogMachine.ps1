#Enable-LogMachine.ps1
$fixFlag = "EnableLogMachine.done"
$flagPath = Join-Path $env:USERPROFILE $fixFlag

if (-not (Test-Path $flagPath)) {
    $prg = "C:\tools\LogMachine\LogMachine.exe"
    $ext = '.log'
    & cmd /c "ftype LogMachine.LOG=`"$prg`" %1"
    & cmd /c "assoc $ext=LogMachine.LOG"
    $ext = '.lo_'
    & cmd /c "ftype LogMachine.LOG=`"$prg`" %1"
    & cmd /c "assoc $ext=LogMachine.LOG"
    $ext = '.errlog'
    & cmd /c "ftype LogMachine.LOG=`"$prg`" %1"
    & cmd /c "assoc $ext=LogMachine.LOG"
    "LogMachine Enabled" | Out-File $flagPath -Force
}


$CMInstallDir = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\SMS\Setup" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty "Installation Directory" -ErrorAction SilentlyContinue
if ($CMInstallDir) {
    $CMlogs = (Join-Path $CMInstallDir "Logs")
}

$UIInstallDir = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\SMS\Setup"  -ErrorAction SilentlyContinue | Select-Object -ExpandProperty "UI Installation Directory"  -ErrorAction SilentlyContinue
if ($UIInstallDir) {
    $CMExe = (Join-Path $UIInstallDir "bin")
    $CMexe = (Join-Path $CMexe "Microsoft.ConfigurationManagement.exe")
}

$ControlPanel = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Control Panel\Cpls"  -ErrorAction SilentlyContinue | Select-Object -ExpandProperty "SMSCFGRC"  -ErrorAction SilentlyContinue

$ClientPath = Get-ItemProperty -Path "HKLM:\System\CurrentControlSet\Services\CcmExec"  -ErrorAction SilentlyContinue | Select-Object -ExpandProperty "ImagePath" -ErrorAction SilentlyContinue | split-path -parent  -ErrorAction SilentlyContinue

if ($ClientPath) {
    $ClientlogsPath = (Join-Path $ClientPath "Logs")
}

$desktopPath = [Environment]::GetFolderPath("CommonDesktop")

$fixFlag = "ClientShortcuts.done"
$flagPath = Join-Path $env:USERPROFILE $fixFlag
if (-not (Test-Path $flagPath)) {
    # Define the paths

    $sccmAppletPath = "C:\Windows\System32\control.exe"

    if ($ControlPanel) {
        # Create the MECM Control Panel Applet shortcut
        $shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut("$desktopPath\SCCM Control Panel Applet.lnk")
        $shortcut.TargetPath = $sccmAppletPath
        $shortcut.Arguments = "smscfgrc"
        $shortcut.IconLocation = $ControlPanel
        $shortcut.Save()

    }
    if (($ClientLogsPath -and (Test-Path $ClientlogsPath))) {
        # Create the Logs shortcut
        $shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut("$desktopPath\Client Logs.lnk")
        $shortcut.TargetPath = $ClientlogsPath
        $shortcut.Save()
        "Shortcuts Enabled" | Out-File $flagPath -Force

    }
}

$fixFlag = "ServerShortcuts.done"
$flagPath = Join-Path $env:USERPROFILE $fixFlag
if (-not (Test-Path $flagPath)) {
    # Check if the new path exists
    if (Test-Path $CMlogs) {
        # Create the new shortcut if the path exists
        $shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut("$desktopPath\ConfigMgr Logs.lnk")
        $shortcut.TargetPath = $CMlogs
        $shortcut.Save()
        "Shortcuts Enabled" | Out-File $flagPath -Force
    }
}
$fixFlag = "ServerShortcuts2.done"
$flagPath = Join-Path $env:USERPROFILE $fixFlag
if (-not (Test-Path $flagPath)) {
    # Check if the new path exists
    if (Test-Path $CMexe) {
        # Create the new shortcut if the path exists
        $shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut("$desktopPath\ConfigMgr Console.lnk")
        $shortcut.TargetPath = $CMexe
        $shortcut.Save()

        $shortcut2 = (New-Object -ComObject WScript.Shell).CreateShortcut("$desktopPath\ConfigMgr Powershell.lnk")
        $shortcut2.TargetPath = "powershell"
        $shortcut2.Arguments = "-NoExit -ExecutionPolicy Bypass C:\staging\DSC\Phases\Start-CMPS.ps1"
        $shortcut2.Save()

        $bytes = [System.IO.File]::ReadAllBytes("$desktopPath\ConfigMgr Powershell.lnk")
        # Set byte 21 (0x15) bit 6 (0x20) ON
        $bytes[0x15] = $bytes[0x15] -bor 0x20
        [System.IO.File]::WriteAllBytes("$desktopPath\ConfigMgr Powershell.lnk", $bytes)

        "Shortcuts Enabled" | Out-File $flagPath -Force
    }
}

$fixFlag = "IISShortcuts.done"
$flagPath = Join-Path $env:USERPROFILE $fixFlag
if (-not (Test-Path $flagPath)) {
    # Define the paths
    $IISLogs = "C:\inetpub\logs"
    # Check if the new path exists
    if (Test-Path $IISLogs) {
        # Create the new shortcut if the path exists

        $shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut("$desktopPath\IIS Logs.lnk")
        $shortcut.TargetPath = $IISLogs
        $shortcut.Save()
        "Shortcuts Enabled" | Out-File $flagPath -Force
    }
}

$fixFlag = "WSUSShortcuts.done"
$flagPath = Join-Path $env:USERPROFILE $fixFlag
if (-not (Test-Path $flagPath)) {
    # Define the paths
    $WSUSLogs = "C:\Program Files\Update Services\LogFiles"
    # Check if the new path exists
    if (Test-Path $WSUSLogs) {
        # Create the new shortcut if the path exists

        $shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut("$desktopPath\WSUS Logs.lnk")
        $shortcut.TargetPath = $WSUSLogs
        $shortcut.Save()
        "Shortcuts Enabled" | Out-File $flagPath -Force
    }
}

