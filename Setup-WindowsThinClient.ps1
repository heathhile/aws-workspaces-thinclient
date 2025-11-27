#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Setup Windows thin client for AWS WorkSpaces with pre-login VPN

.DESCRIPTION
    Automates configuration of Windows 10/11 Pro/Enterprise as a thin client for AWS WorkSpaces.
    Includes:
    - OpenVPN client installation
    - VPN certificate configuration
    - Always-On VPN setup
    - Domain join to AWS Managed AD
    - WorkSpaces client installation
    - Auto-launch configuration
    - Thin client optimizations

.PARAMETER CustomerName
    Customer name for identification (e.g., "acme-corp")

.PARAMETER DomainName
    AWS Managed AD domain name (e.g., "customer.domain")

.PARAMETER VPNConfigPath
    Path to the .ovpn configuration file with embedded certificates

.PARAMETER DomainAdmin
    Domain administrator username for joining domain

.PARAMETER SkipDomainJoin
    Skip domain join step (for testing)

.PARAMETER SkipOptimizations
    Skip thin client optimizations

.EXAMPLE
    .\Setup-WindowsThinClient.ps1 -CustomerName "acme-corp" -DomainName "acme.corp" -VPNConfigPath "C:\temp\acme-vpn.ovpn" -DomainAdmin "Admin"

.EXAMPLE
    .\Setup-WindowsThinClient.ps1 -CustomerName "test" -DomainName "brianreich.dev" -VPNConfigPath ".\test-customer-cert.ovpn" -SkipDomainJoin

.NOTES
    Author: AWS WorkSpaces Thin Client Project
    Version: 1.0.0
    Requires: Windows 10/11 Pro or Enterprise, PowerShell 5.1+, Administrator privileges
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$CustomerName,

    [Parameter(Mandatory=$false)]
    [string]$DomainName,

    [Parameter(Mandatory=$false)]
    [string]$VPNConfigPath,

    [Parameter(Mandatory=$false)]
    [string]$DomainAdmin,

    [Parameter(Mandatory=$false)]
    [switch]$SkipDomainJoin,

    [Parameter(Mandatory=$false)]
    [switch]$SkipOptimizations
)

# Script configuration
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# Color output functions
function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Type = "Info"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    switch ($Type) {
        "Header" {
            Write-Host "`n============================================" -ForegroundColor Cyan
            Write-Host " $Message" -ForegroundColor Cyan
            Write-Host "============================================`n" -ForegroundColor Cyan
        }
        "Success" {
            Write-Host "[$timestamp] ✓ $Message" -ForegroundColor Green
        }
        "Error" {
            Write-Host "[$timestamp] ✗ $Message" -ForegroundColor Red
        }
        "Warning" {
            Write-Host "[$timestamp] ⚠ $Message" -ForegroundColor Yellow
        }
        "Info" {
            Write-Host "[$timestamp] ℹ $Message" -ForegroundColor White
        }
        "Status" {
            Write-Host "[$timestamp] → $Message" -ForegroundColor Gray
        }
    }
}

function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-WindowsEdition {
    $edition = (Get-WindowsEdition -Online).Edition
    Write-ColorOutput "Detected Windows edition: $edition" -Type "Info"

    if ($edition -notmatch "Professional|Enterprise|Education") {
        Write-ColorOutput "Windows Pro, Enterprise, or Education edition required for domain join" -Type "Error"
        Write-ColorOutput "Current edition: $edition" -Type "Error"
        return $false
    }
    return $true
}

function Get-UserInput {
    Write-ColorOutput "Windows Thin Client Setup - Interactive Configuration" -Type "Header"

    if (-not $CustomerName) {
        $CustomerName = Read-Host "Enter customer name (e.g., acme-corp)"
    }

    if (-not $VPNConfigPath) {
        $VPNConfigPath = Read-Host "Enter path to VPN configuration file (.ovpn)"
    }

    if (-not $SkipDomainJoin) {
        if (-not $DomainName) {
            $DomainName = Read-Host "Enter domain name (e.g., customer.domain)"
        }

        if (-not $DomainAdmin) {
            $DomainAdmin = Read-Host "Enter domain admin username (e.g., Admin)"
        }
    }

    # Validate VPN config exists
    if (-not (Test-Path $VPNConfigPath)) {
        Write-ColorOutput "VPN configuration file not found: $VPNConfigPath" -Type "Error"
        exit 1
    }

    # Display configuration
    Write-Host "`nConfiguration Summary:" -ForegroundColor Cyan
    Write-Host "  Customer Name: $CustomerName" -ForegroundColor White
    Write-Host "  VPN Config: $VPNConfigPath" -ForegroundColor White
    if (-not $SkipDomainJoin) {
        Write-Host "  Domain: $DomainName" -ForegroundColor White
        Write-Host "  Domain Admin: $DomainAdmin" -ForegroundColor White
    } else {
        Write-Host "  Domain Join: SKIPPED" -ForegroundColor Yellow
    }
    Write-Host ""

    $confirm = Read-Host "Continue with this configuration? (yes/no)"
    if ($confirm -ne "yes") {
        Write-ColorOutput "Setup cancelled by user" -Type "Warning"
        exit 0
    }
}

function Install-OpenVPN {
    Write-ColorOutput "Installing OpenVPN Client" -Type "Header"

    # Check if already installed
    $installed = Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*" |
        Where-Object { $_.DisplayName -like "*OpenVPN*" }

    if ($installed) {
        Write-ColorOutput "OpenVPN already installed: $($installed.DisplayName) $($installed.DisplayVersion)" -Type "Success"
        return
    }

    Write-ColorOutput "Downloading OpenVPN installer..." -Type "Status"

    # Download latest OpenVPN
    $downloadUrl = "https://swupdate.openvpn.org/community/releases/OpenVPN-2.6.12-I001-amd64.msi"
    $installerPath = "$env:TEMP\OpenVPN-Installer.msi"

    try {
        Invoke-WebRequest -Uri $downloadUrl -OutFile $installerPath -UseBasicParsing
        Write-ColorOutput "Download complete" -Type "Success"
    }
    catch {
        Write-ColorOutput "Failed to download OpenVPN: $_" -Type "Error"
        exit 1
    }

    Write-ColorOutput "Installing OpenVPN (this may take a few minutes)..." -Type "Status"

    # Install silently
    $arguments = "/i `"$installerPath`" /qn /norestart"
    $process = Start-Process msiexec.exe -ArgumentList $arguments -Wait -PassThru

    if ($process.ExitCode -eq 0) {
        Write-ColorOutput "OpenVPN installed successfully" -Type "Success"
    }
    else {
        Write-ColorOutput "OpenVPN installation failed with exit code: $($process.ExitCode)" -Type "Error"
        exit 1
    }

    # Cleanup
    Remove-Item $installerPath -Force -ErrorAction SilentlyContinue

    # Wait for service to be created
    Write-ColorOutput "Waiting for OpenVPN service..." -Type "Status"
    Start-Sleep -Seconds 5
}

function Configure-VPN {
    param([string]$ConfigPath)

    Write-ColorOutput "Configuring VPN Connection" -Type "Header"

    $configDir = "C:\Program Files\OpenVPN\config"

    # Create config directory if it doesn't exist
    if (-not (Test-Path $configDir)) {
        New-Item -Path $configDir -ItemType Directory -Force | Out-Null
    }

    # Copy VPN configuration
    $destPath = Join-Path $configDir "thin-client.ovpn"
    Copy-Item -Path $ConfigPath -Destination $destPath -Force

    Write-ColorOutput "VPN configuration copied to: $destPath" -Type "Success"

    # Set proper permissions (only SYSTEM and Administrators)
    $acl = Get-Acl $destPath
    $acl.SetAccessRuleProtection($true, $false)  # Disable inheritance

    # Remove all existing rules
    $acl.Access | ForEach-Object { $acl.RemoveAccessRule($_) | Out-Null }

    # Add SYSTEM full control
    $systemRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        "SYSTEM", "FullControl", "Allow"
    )
    $acl.AddAccessRule($systemRule)

    # Add Administrators full control
    $adminRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        "Administrators", "FullControl", "Allow"
    )
    $acl.AddAccessRule($adminRule)

    Set-Acl -Path $destPath -AclObject $acl

    Write-ColorOutput "VPN configuration secured" -Type "Success"
}

function Enable-AlwaysOnVPN {
    Write-ColorOutput "Configuring Always-On VPN" -Type "Header"

    # Configure OpenVPN service
    Write-ColorOutput "Configuring OpenVPN service..." -Type "Status"

    Set-Service -Name "OpenVPNService" -StartupType Automatic
    Start-Service -Name "OpenVPNService"

    Write-ColorOutput "OpenVPN service configured for automatic start" -Type "Success"

    # Create scheduled task for auto-connect
    Write-ColorOutput "Creating VPN auto-connect task..." -Type "Status"

    $taskName = "AlwaysOn-VPN"

    # Remove existing task if present
    $existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($existingTask) {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    }

    # Task action - start OpenVPN GUI connected
    $action = New-ScheduledTaskAction -Execute "C:\Program Files\OpenVPN\bin\openvpn-gui.exe" -Argument "--connect thin-client.ovpn --silent_connection 1"

    # Task trigger - at startup
    $trigger = New-ScheduledTaskTrigger -AtStartup

    # Task principal - run as SYSTEM
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

    # Task settings
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

    # Register task
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings | Out-Null

    Write-ColorOutput "VPN auto-connect task created" -Type "Success"

    # Alternative: Registry-based auto-connect
    Write-ColorOutput "Configuring registry settings..." -Type "Status"

    $regPath = "HKLM:\SOFTWARE\OpenVPN"
    if (-not (Test-Path $regPath)) {
        New-Item -Path $regPath -Force | Out-Null
    }

    New-ItemProperty -Path $regPath -Name "config_dir" -Value "C:\Program Files\OpenVPN\config" -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $regPath -Name "config_ext" -Value "ovpn" -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $regPath -Name "auto_connect" -Value 1 -PropertyType DWORD -Force | Out-Null

    Write-ColorOutput "Registry settings configured" -Type "Success"
}

function Test-VPNConnectivity {
    Write-ColorOutput "Testing VPN Connectivity" -Type "Header"

    Write-ColorOutput "Waiting for VPN connection (30 seconds)..." -Type "Status"
    Start-Sleep -Seconds 30

    # Check for tun interface
    $vpnInterface = Get-NetAdapter | Where-Object { $_.InterfaceDescription -like "*TAP-Windows*" -or $_.InterfaceDescription -like "*OpenVPN*" }

    if ($vpnInterface) {
        Write-ColorOutput "VPN interface detected: $($vpnInterface.Name)" -Type "Success"

        # Get IP configuration
        $ipConfig = Get-NetIPAddress -InterfaceIndex $vpnInterface.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue

        if ($ipConfig) {
            Write-ColorOutput "VPN IP address: $($ipConfig.IPAddress)" -Type "Success"
        }
    }
    else {
        Write-ColorOutput "VPN interface not detected - may need manual verification" -Type "Warning"
    }

    # Check VPN log
    $logPath = "C:\Program Files\OpenVPN\log\thin-client.log"
    if (Test-Path $logPath) {
        $logContent = Get-Content $logPath -Tail 20
        if ($logContent -match "Initialization Sequence Completed") {
            Write-ColorOutput "VPN connection successful!" -Type "Success"
        }
        else {
            Write-ColorOutput "VPN may not be fully connected - check logs" -Type "Warning"
        }
    }
}

function Join-Domain {
    param(
        [string]$Domain,
        [string]$AdminUser
    )

    Write-ColorOutput "Joining Domain: $Domain" -Type "Header"

    # Check if already domain joined
    $computerSystem = Get-WmiObject Win32_ComputerSystem
    if ($computerSystem.PartOfDomain -and $computerSystem.Domain -eq $Domain) {
        Write-ColorOutput "Already joined to domain: $Domain" -Type "Success"
        return
    }

    # Test domain connectivity first
    Write-ColorOutput "Testing domain connectivity..." -Type "Status"

    try {
        $domainTest = Test-NetConnection -ComputerName $Domain -Port 389 -WarningAction SilentlyContinue
        if ($domainTest.TcpTestSucceeded) {
            Write-ColorOutput "Domain controller reachable" -Type "Success"
        }
        else {
            Write-ColorOutput "Cannot reach domain controller - ensure VPN is connected" -Type "Warning"
        }
    }
    catch {
        Write-ColorOutput "Domain connectivity test failed: $_" -Type "Warning"
    }

    # Test DNS resolution
    try {
        $dnsTest = Resolve-DnsName -Name $Domain -ErrorAction SilentlyContinue
        if ($dnsTest) {
            Write-ColorOutput "DNS resolution successful: $($dnsTest[0].IPAddress)" -Type "Success"
        }
    }
    catch {
        Write-ColorOutput "DNS resolution failed - check VPN DNS settings" -Type "Warning"
    }

    # Prompt for credentials
    Write-Host "`nEnter credentials for domain admin: $AdminUser@$Domain" -ForegroundColor Cyan
    $credential = Get-Credential -UserName $AdminUser -Message "Enter domain admin password"

    # Attempt domain join
    Write-ColorOutput "Joining domain (this may take a minute)..." -Type "Status"

    try {
        Add-Computer -DomainName $Domain -Credential $credential -Restart:$false -Force
        Write-ColorOutput "Successfully joined domain: $Domain" -Type "Success"
        Write-ColorOutput "Reboot required to complete domain join" -Type "Warning"
    }
    catch {
        Write-ColorOutput "Domain join failed: $_" -Type "Error"
        Write-ColorOutput "Ensure VPN is connected and credentials are correct" -Type "Info"
        throw
    }
}

function Install-WorkSpaces {
    Write-ColorOutput "Installing AWS WorkSpaces Client" -Type "Header"

    # Check if already installed
    $installed = Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*" |
        Where-Object { $_.DisplayName -like "*WorkSpaces*" }

    if ($installed) {
        Write-ColorOutput "WorkSpaces already installed: $($installed.DisplayName) $($installed.DisplayVersion)" -Type "Success"
        return
    }

    Write-ColorOutput "Downloading WorkSpaces installer..." -Type "Status"

    $downloadUrl = "https://d2td7dqidlhjx7.cloudfront.net/prod/global/windows/Amazon+WorkSpaces.msi"
    $installerPath = "$env:TEMP\AmazonWorkSpaces.msi"

    try {
        Invoke-WebRequest -Uri $downloadUrl -OutFile $installerPath -UseBasicParsing
        Write-ColorOutput "Download complete" -Type "Success"
    }
    catch {
        Write-ColorOutput "Failed to download WorkSpaces: $_" -Type "Error"
        exit 1
    }

    Write-ColorOutput "Installing WorkSpaces (this may take a few minutes)..." -Type "Status"

    # Install silently
    $arguments = "/i `"$installerPath`" /qn /norestart"
    $process = Start-Process msiexec.exe -ArgumentList $arguments -Wait -PassThru

    if ($process.ExitCode -eq 0) {
        Write-ColorOutput "WorkSpaces installed successfully" -Type "Success"
    }
    else {
        Write-ColorOutput "WorkSpaces installation failed with exit code: $($process.ExitCode)" -Type "Error"
        exit 1
    }

    # Cleanup
    Remove-Item $installerPath -Force -ErrorAction SilentlyContinue
}

function Configure-WorkSpacesAutoStart {
    Write-ColorOutput "Configuring WorkSpaces Auto-Start" -Type "Header"

    # Find WorkSpaces executable
    $workspacesPath = "C:\Program Files\Amazon Web Services, Inc\Amazon WorkSpaces\workspaces.exe"

    if (-not (Test-Path $workspacesPath)) {
        # Try alternate path
        $workspacesPath = "C:\Program Files (x86)\Amazon Web Services, Inc\Amazon WorkSpaces\workspaces.exe"
    }

    if (-not (Test-Path $workspacesPath)) {
        Write-ColorOutput "WorkSpaces executable not found" -Type "Error"
        return
    }

    Write-ColorOutput "WorkSpaces path: $workspacesPath" -Type "Info"

    # Create startup shortcut for all users
    $startupPath = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp"

    $WshShell = New-Object -ComObject WScript.Shell
    $shortcutPath = Join-Path $startupPath "AWS-WorkSpaces.lnk"
    $shortcut = $WshShell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $workspacesPath
    $shortcut.Description = "AWS WorkSpaces Client"
    $shortcut.Save()

    Write-ColorOutput "Startup shortcut created: $shortcutPath" -Type "Success"

    # Create desktop shortcut
    $desktopPath = "$env:Public\Desktop"
    $desktopShortcut = Join-Path $desktopPath "AWS-WorkSpaces.lnk"
    $shortcut2 = $WshShell.CreateShortcut($desktopShortcut)
    $shortcut2.TargetPath = $workspacesPath
    $shortcut2.Description = "AWS WorkSpaces Client"
    $shortcut2.Save()

    Write-ColorOutput "Desktop shortcut created: $desktopShortcut" -Type "Success"

    [System.Runtime.Interopservices.Marshal]::ReleaseComObject($WshShell) | Out-Null
}

function Optimize-ThinClient {
    Write-ColorOutput "Applying Thin Client Optimizations" -Type "Header"

    # Disable unnecessary services
    Write-ColorOutput "Disabling unnecessary services..." -Type "Status"

    $servicesToDisable = @(
        "WSearch",          # Windows Search
        "SysMain",          # Superfetch
        "DiagTrack",        # Diagnostics Tracking
        "WMPNetworkSvc",    # Windows Media Player Network Sharing
        "XblAuthManager",   # Xbox Live Auth Manager
        "XblGameSave",      # Xbox Live Game Save
        "XboxNetApiSvc"     # Xbox Live Networking Service
    )

    foreach ($service in $servicesToDisable) {
        try {
            $svc = Get-Service -Name $service -ErrorAction SilentlyContinue
            if ($svc -and $svc.StartType -ne "Disabled") {
                Stop-Service -Name $service -Force -ErrorAction SilentlyContinue
                Set-Service -Name $service -StartupType Disabled
                Write-ColorOutput "Disabled service: $service" -Type "Success"
            }
        }
        catch {
            # Ignore errors - service may not exist
        }
    }

    # Configure power settings
    Write-ColorOutput "Configuring power settings..." -Type "Status"

    # Never sleep when plugged in
    powercfg /change standby-timeout-ac 0 | Out-Null
    powercfg /change standby-timeout-dc 0 | Out-Null

    # Turn off monitor after 30 minutes
    powercfg /change monitor-timeout-ac 30 | Out-Null
    powercfg /change monitor-timeout-dc 30 | Out-Null

    Write-ColorOutput "Power settings configured" -Type "Success"

    # Disable visual effects for performance
    Write-ColorOutput "Optimizing visual effects..." -Type "Status"

    $regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"
    if (-not (Test-Path $regPath)) {
        New-Item -Path $regPath -Force | Out-Null
    }
    New-ItemProperty -Path $regPath -Name "VisualFXSetting" -Value 2 -PropertyType DWORD -Force | Out-Null

    Write-ColorOutput "Visual effects optimized" -Type "Success"

    # Remove unnecessary inbox apps
    Write-ColorOutput "Removing unnecessary apps..." -Type "Status"

    $appsToRemove = @(
        "*Microsoft.XboxApp*",
        "*Microsoft.WindowsMaps*",
        "*Microsoft.BingNews*",
        "*Microsoft.BingWeather*",
        "*Microsoft.GetHelp*",
        "*Microsoft.Getstarted*",
        "*Microsoft.Microsoft3DViewer*",
        "*Microsoft.MixedReality.Portal*"
    )

    foreach ($app in $appsToRemove) {
        try {
            Get-AppxPackage $app | Remove-AppxPackage -ErrorAction SilentlyContinue
        }
        catch {
            # Ignore errors
        }
    }

    Write-ColorOutput "App cleanup complete" -Type "Success"

    # Configure automatic logon for thin client user (optional - will prompt)
    Write-Host "`nOptional: Configure automatic logon? (not recommended for shared devices)" -ForegroundColor Yellow
    $autoLogon = Read-Host "Enable auto-logon? (yes/no)"

    if ($autoLogon -eq "yes") {
        $username = Read-Host "Enter username for auto-logon"
        $password = Read-Host "Enter password" -AsSecureString
        $plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [Runtime.InteropServices.Marshal]::SecureStringToBSTR($password)
        )

        $regPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
        New-ItemProperty -Path $regPath -Name "AutoAdminLogon" -Value "1" -PropertyType String -Force | Out-Null
        New-ItemProperty -Path $regPath -Name "DefaultUsername" -Value $username -PropertyType String -Force | Out-Null
        New-ItemProperty -Path $regPath -Name "DefaultPassword" -Value $plainPassword -PropertyType String -Force | Out-Null

        Write-ColorOutput "Auto-logon configured for: $username" -Type "Success"
    }
}

function Show-CompletionSummary {
    Write-ColorOutput "Setup Complete!" -Type "Header"

    Write-Host "`nInstallation Summary:" -ForegroundColor Cyan
    Write-Host "  ✓ OpenVPN installed and configured" -ForegroundColor Green
    Write-Host "  ✓ VPN set to auto-connect on boot" -ForegroundColor Green

    if (-not $SkipDomainJoin) {
        Write-Host "  ✓ Domain join configured" -ForegroundColor Green
    }

    Write-Host "  ✓ WorkSpaces client installed" -ForegroundColor Green
    Write-Host "  ✓ WorkSpaces auto-start configured" -ForegroundColor Green

    if (-not $SkipOptimizations) {
        Write-Host "  ✓ Thin client optimizations applied" -ForegroundColor Green
    }

    Write-Host "`nNext Steps:" -ForegroundColor Cyan

    if (-not $SkipDomainJoin) {
        Write-Host "  1. Reboot the computer to complete domain join" -ForegroundColor White
        Write-Host "  2. After reboot, VPN will auto-connect" -ForegroundColor White
        Write-Host "  3. Login with domain credentials: $DomainName\username" -ForegroundColor White
        Write-Host "  4. WorkSpaces will auto-launch" -ForegroundColor White
        Write-Host "  5. Enter WorkSpaces registration code when prompted" -ForegroundColor White

        Write-Host "`nReboot now? (yes/no)" -ForegroundColor Yellow
        $reboot = Read-Host

        if ($reboot -eq "yes") {
            Write-ColorOutput "Rebooting in 10 seconds..." -Type "Warning"
            Start-Sleep -Seconds 10
            Restart-Computer -Force
        }
    }
    else {
        Write-Host "  1. VPN will auto-connect on next boot" -ForegroundColor White
        Write-Host "  2. Manually join domain if needed" -ForegroundColor White
        Write-Host "  3. WorkSpaces will auto-launch after login" -ForegroundColor White
    }

    Write-Host "`nConfiguration Files:" -ForegroundColor Cyan
    Write-Host "  VPN Config: C:\Program Files\OpenVPN\config\thin-client.ovpn" -ForegroundColor White
    Write-Host "  VPN Logs: C:\Program Files\OpenVPN\log\thin-client.log" -ForegroundColor White
    Write-Host "  WorkSpaces: $env:LOCALAPPDATA\Amazon Web Services\Amazon WorkSpaces\logs" -ForegroundColor White

    Write-Host "`nTroubleshooting Commands:" -ForegroundColor Cyan
    Write-Host "  Check VPN status: Get-Service OpenVPNService" -ForegroundColor Gray
    Write-Host "  Check domain join: Test-ComputerSecureChannel -Verbose" -ForegroundColor Gray
    Write-Host "  View VPN log: Get-Content 'C:\Program Files\OpenVPN\log\thin-client.log' -Tail 50" -ForegroundColor Gray

    Write-Host ""
}

# Main execution
function Main {
    Write-ColorOutput "AWS WorkSpaces Windows Thin Client Setup" -Type "Header"
    Write-ColorOutput "Version 1.0.0" -Type "Info"
    Write-Host ""

    # Pre-flight checks
    if (-not (Test-Administrator)) {
        Write-ColorOutput "This script must be run as Administrator" -Type "Error"
        Write-ColorOutput "Right-click PowerShell and select 'Run as Administrator'" -Type "Info"
        exit 1
    }

    if (-not (Test-WindowsEdition)) {
        exit 1
    }

    # Get user input if not provided via parameters
    Get-UserInput

    try {
        # Installation steps
        Install-OpenVPN
        Configure-VPN -ConfigPath $VPNConfigPath
        Enable-AlwaysOnVPN
        Test-VPNConnectivity

        if (-not $SkipDomainJoin) {
            Join-Domain -Domain $DomainName -AdminUser $DomainAdmin
        }

        Install-WorkSpaces
        Configure-WorkSpacesAutoStart

        if (-not $SkipOptimizations) {
            Optimize-ThinClient
        }

        # Show completion summary
        Show-CompletionSummary
    }
    catch {
        Write-ColorOutput "Setup failed: $_" -Type "Error"
        Write-ColorOutput "Check logs and try again" -Type "Info"
        exit 1
    }
}

# Run main function
Main
