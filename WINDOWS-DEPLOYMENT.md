# Windows Thin Client Deployment Guide

## Overview

This guide covers deploying Windows-based thin clients for AWS WorkSpaces in GovCloud environments with AWS Managed Active Directory integration. Windows provides native AD integration, Group Policy support, and Always-On VPN for pre-login authentication.

## Table of Contents

1. [Architecture](#architecture)
2. [Prerequisites](#prerequisites)
3. [Certificate Generation](#certificate-generation)
4. [AWS Client VPN Configuration](#aws-client-vpn-configuration)
5. [Windows Thin Client Setup](#windows-thin-client-setup)
6. [Group Policy Deployment](#group-policy-deployment)
7. [Testing and Validation](#testing-and-validation)
8. [Troubleshooting](#troubleshooting)
9. [CMMC Compliance](#cmmc-compliance)

---

## Architecture

### Authentication Flow

```
┌─────────────────────────────────────────────────────────────────┐
│ Windows Thin Client Boot Sequence                              │
└─────────────────────────────────────────────────────────────────┘
                           │
                           ▼
              ┌────────────────────────┐
              │ 1. System Boot         │
              │    - Windows loads     │
              └────────────────────────┘
                           │
                           ▼
              ┌────────────────────────────────────────┐
              │ 2. Always-On VPN Connects              │
              │    - Certificate-based authentication  │
              │    - No user interaction required      │
              │    - Establishes tunnel to AWS         │
              └────────────────────────────────────────┘
                           │
                           ▼
              ┌────────────────────────────────────────┐
              │ 3. Network Connectivity Established    │
              │    - DNS points to AD servers          │
              │    - Can reach domain controllers      │
              └────────────────────────────────────────┘
                           │
                           ▼
              ┌────────────────────────────────────────┐
              │ 4. Windows Login Screen Appears        │
              │    - User sees: DOMAIN\username        │
              │    - Ctrl+Alt+Del to login             │
              └────────────────────────────────────────┘
                           │
                           ▼
              ┌────────────────────────────────────────┐
              │ 5. User Authentication                 │
              │    - Username: DOMAIN\user             │
              │    - Password: ********                │
              │    - MFA: 6-digit code                 │
              └────────────────────────────────────────┘
                           │
                           ▼
              ┌────────────────────────────────────────┐
              │ 6. AD Authentication (via VPN)         │
              │    - Credentials sent to AWS Managed AD│
              │    - MFA validated                     │
              │    - User profile loaded               │
              └────────────────────────────────────────┘
                           │
                           ▼
              ┌────────────────────────────────────────┐
              │ 7. Desktop Loads                       │
              │    - Group policies applied            │
              │    - WorkSpaces client auto-launches   │
              └────────────────────────────────────────┘
                           │
                           ▼
              ┌────────────────────────────────────────┐
              │ 8. WorkSpaces SSO                      │
              │    - Uses Windows credentials          │
              │    - No re-authentication required     │
              │    - Auto-connects to workspace        │
              └────────────────────────────────────────┘
```

### Network Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│ Customer Premises (Out of CMMC Scope)                            │
│                                                                  │
│  ┌────────────────────────┐                                     │
│  │ Windows Thin Client    │                                     │
│  │ - Domain joined        │                                     │
│  │ - Always-On VPN        │                                     │
│  │ - WorkSpaces client    │                                     │
│  └────────────┬───────────┘                                     │
│               │                                                  │
│               │ Internet (Port 443)                              │
└───────────────┼──────────────────────────────────────────────────┘
                │
                │ Certificate-based VPN
                │
┌───────────────▼──────────────────────────────────────────────────┐
│ AWS GovCloud (CMMC Scope)                                        │
│                                                                  │
│  ┌──────────────────────────────────────────────────────┐       │
│  │ Client VPN Endpoint                                  │       │
│  │ - Certificate authentication (device)                │       │
│  │ - IP Pool: 100.65.0.0/22                            │       │
│  │ - Associated with VPC subnets                        │       │
│  └──────────────────┬───────────────────────────────────┘       │
│                     │                                            │
│  ┌──────────────────▼───────────────────────────────────┐       │
│  │ VPC (172.31.0.0/16)                                  │       │
│  │                                                       │       │
│  │  ┌────────────────────────────────────────────┐      │       │
│  │  │ AWS Managed Active Directory              │      │       │
│  │  │ - Domain: customer.domain                 │      │       │
│  │  │ - DNS: 172.31.24.176, 172.31.12.32       │      │       │
│  │  │ - MFA enabled                             │      │       │
│  │  └───────────────┬────────────────────────────┘      │       │
│  │                  │                                    │       │
│  │  ┌───────────────▼────────────────────────────┐      │       │
│  │  │ AWS WorkSpaces                             │      │       │
│  │  │ - DCV/WSP protocol                         │      │       │
│  │  │ - AD integrated                            │      │       │
│  │  └────────────────────────────────────────────┘      │       │
│  └──────────────────────────────────────────────────────┘       │
└──────────────────────────────────────────────────────────────────┘
```

---

## Prerequisites

### AWS Requirements

- AWS GovCloud account
- AWS Managed Active Directory configured
- Client VPN endpoint with certificate authentication
- WorkSpaces directory joined to AWS Managed AD
- ACM certificates for VPN server and client authentication

### Windows Requirements

- **OS Version**: Windows 10/11 Pro or Enterprise (Home edition cannot domain join)
- **Hardware**:
  - 4GB RAM minimum (8GB recommended)
  - 64GB storage minimum
  - Network adapter (wired or wireless)
- **Network**: Internet connectivity on port 443
- **Software**:
  - AWS WorkSpaces client for Windows
  - OpenVPN client (if not using Windows native VPN)

### Administrative Access

- Local administrator access to Windows device
- AWS GovCloud credentials with permissions:
  - `ec2:CreateClientVpnEndpoint`
  - `ec2:AuthorizeClientVpnIngress`
  - `acm:ImportCertificate`
  - `workspaces:DescribeWorkspaces`
  - `ds:DescribeDirectories`

---

## Certificate Generation

We use the same certificate infrastructure as Linux deployments. Each customer gets one certificate that can be shared across their 1-2 devices.

### Option 1: Use Existing Certificates

If you already generated certificates for Linux deployment, you can reuse them for Windows.

**Files needed:**
- `ca.crt` - CA certificate
- `issued/customer-device.crt` - Client certificate
- `private/customer-device.key` - Client private key

### Option 2: Generate New Certificates

If this is your first deployment or a new customer:

```bash
# Install easy-rsa (on macOS with Homebrew)
brew install easy-rsa

# Create customer certificate directory
mkdir -p ~/customer-certs/customer-name
cd ~/customer-certs/customer-name

# Initialize PKI
easyrsa init-pki

# Create Certificate Authority
easyrsa build-ca nopass
# When prompted for Common Name, use: customer-name-ca

# Generate server certificate (for AWS Client VPN endpoint)
easyrsa build-server-full server nopass

# Generate client certificate (for Windows thin clients)
easyrsa build-client-full customer-device nopass
```

### Upload Certificates to AWS ACM

```bash
# Set AWS profile for customer's GovCloud account
export AWS_PROFILE=customer-govcloud

# Upload server certificate
aws acm import-certificate \
  --certificate fileb://pki/issued/server.crt \
  --private-key fileb://pki/private/server.key \
  --certificate-chain fileb://pki/ca.crt \
  --region us-gov-west-1

# Upload CA certificate (for client authentication)
aws acm import-certificate \
  --certificate fileb://pki/ca.crt \
  --private-key fileb://pki/private/ca.key \
  --region us-gov-west-1

# Save the ARNs from the output
# Example: arn:aws-us-gov:acm:us-gov-west-1:123456789012:certificate/abc-def-123
```

---

## AWS Client VPN Configuration

### Create Client VPN Endpoint

```bash
# Get VPC and subnet information
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" --query 'Vpcs[0].VpcId' --output text --region us-gov-west-1)
SUBNET_IDS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query 'Subnets[0:2].SubnetId' --output text --region us-gov-west-1)

# Create Client VPN endpoint with certificate authentication
aws ec2 create-client-vpn-endpoint \
  --client-cidr-block "100.65.0.0/22" \
  --server-certificate-arn "arn:aws-us-gov:acm:us-gov-west-1:ACCOUNT:certificate/SERVER_CERT_ID" \
  --authentication-options '[{"Type":"certificate-authentication","MutualAuthentication":{"ClientRootCertificateChainArn":"arn:aws-us-gov:acm:us-gov-west-1:ACCOUNT:certificate/CA_CERT_ID"}}]' \
  --connection-log-options 'Enabled=false' \
  --dns-servers "172.31.24.176" "172.31.12.32" \
  --split-tunnel \
  --region us-gov-west-1

# Save the endpoint ID from output
# Example: cvpn-endpoint-0123456789abcdef0
```

### Associate VPN with VPC Subnets

```bash
# Associate with first subnet
aws ec2 associate-client-vpn-target-network \
  --client-vpn-endpoint-id cvpn-endpoint-XXXXX \
  --subnet-id subnet-XXXXX \
  --region us-gov-west-1

# Associate with second subnet (for high availability)
aws ec2 associate-client-vpn-target-network \
  --client-vpn-endpoint-id cvpn-endpoint-XXXXX \
  --subnet-id subnet-YYYYY \
  --region us-gov-west-1
```

### Authorize VPN Access

```bash
# Get AD DNS servers (for reference)
aws ds describe-directories \
  --directory-ids d-XXXXX \
  --query 'DirectoryDescriptions[0].DnsIpAddrs' \
  --region us-gov-west-1

# Authorize access to VPC CIDR
aws ec2 authorize-client-vpn-ingress \
  --client-vpn-endpoint-id cvpn-endpoint-XXXXX \
  --target-network-cidr "172.31.0.0/16" \
  --authorize-all-groups \
  --region us-gov-west-1

# Authorize internet access (if needed)
aws ec2 authorize-client-vpn-ingress \
  --client-vpn-endpoint-id cvpn-endpoint-XXXXX \
  --target-network-cidr "0.0.0.0/0" \
  --authorize-all-groups \
  --region us-gov-west-1
```

### Download VPN Configuration

```bash
# Download client configuration
aws ec2 export-client-vpn-client-configuration \
  --client-vpn-endpoint-id cvpn-endpoint-XXXXX \
  --output text \
  --region us-gov-west-1 > customer-vpn-base.ovpn
```

### Create Complete VPN Configuration

The downloaded configuration is missing the client certificates. Add them:

```bash
# Create complete configuration file
cat customer-vpn-base.ovpn > customer-vpn.ovpn

# Append CA certificate
echo "" >> customer-vpn.ovpn
echo "<ca>" >> customer-vpn.ovpn
cat pki/ca.crt >> customer-vpn.ovpn
echo "</ca>" >> customer-vpn.ovpn

# Append client certificate
echo "" >> customer-vpn.ovpn
echo "<cert>" >> customer-vpn.ovpn
cat pki/issued/customer-device.crt >> customer-vpn.ovpn
echo "</cert>" >> customer-vpn.ovpn

# Append client private key
echo "" >> customer-vpn.ovpn
echo "<key>" >> customer-vpn.ovpn
cat pki/private/customer-device.key >> customer-vpn.ovpn
echo "</key>" >> customer-vpn.ovpn
```

**Example customer-vpn.ovpn:**

```
client
dev tun
proto udp
remote cvpn-endpoint-XXXXX.prod.clientvpn.us-gov-west-1.amazonaws.com 443
remote-random-hostname
resolv-retry infinite
nobind
remote-cert-tls server
cipher AES-256-GCM
verb 3
dhcp-option DNS 172.31.24.176
dhcp-option DNS 172.31.12.32

<ca>
-----BEGIN CERTIFICATE-----
[CA certificate content]
-----END CERTIFICATE-----
</ca>

<cert>
-----BEGIN CERTIFICATE-----
[Client certificate content]
-----END CERTIFICATE-----
</cert>

<key>
-----BEGIN PRIVATE KEY-----
[Client private key content]
-----END PRIVATE KEY-----
</key>
```

---

## Windows Thin Client Setup

### Automated Setup with PowerShell

We provide a PowerShell script for automated configuration:

```powershell
# Download and run setup script
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/heathhile/aws-workspaces-thinclient/main/Setup-WindowsThinclient.ps1" -OutFile "Setup-WindowsThinclient.ps1"

# Run with administrator privileges
.\Setup-WindowsThinclient.ps1
```

### Manual Setup Steps

If you prefer manual configuration or need to troubleshoot:

#### 1. Install OpenVPN Client

**Download OpenVPN:**
- Visit: https://openvpn.net/community-downloads/
- Download: OpenVPN 2.6.x Windows Installer (64-bit)
- Install with default options
- Reboot when prompted

**Alternative: Use Windows Native VPN**

Windows 10/11 Pro and Enterprise support native IKEv2 VPN, but AWS Client VPN uses OpenVPN protocol, so OpenVPN client is required.

#### 2. Import VPN Configuration

```powershell
# Copy VPN configuration to OpenVPN config directory
Copy-Item -Path "customer-vpn.ovpn" -Destination "C:\Program Files\OpenVPN\config\" -Force

# Restart OpenVPN service
Restart-Service OpenVPNService
```

#### 3. Configure Always-On VPN

**Option A: Via Registry (Automated)**

```powershell
# Enable auto-start VPN on boot
New-ItemProperty -Path "HKLM:\SOFTWARE\OpenVPN" -Name "config_dir" -Value "C:\Program Files\OpenVPN\config" -PropertyType String -Force
New-ItemProperty -Path "HKLM:\SOFTWARE\OpenVPN" -Name "config_ext" -Value "ovpn" -PropertyType String -Force
New-ItemProperty -Path "HKLM:\SOFTWARE\OpenVPN" -Name "auto_connect" -Value "1" -PropertyType DWORD -Force

# Set OpenVPN service to start automatically
Set-Service -Name OpenVPNService -StartupType Automatic
Start-Service OpenVPNService
```

**Option B: Via Task Scheduler**

```powershell
# Create scheduled task to start VPN at boot
$action = New-ScheduledTaskAction -Execute "C:\Program Files\OpenVPN\bin\openvpn-gui.exe" -Argument "--connect customer-vpn.ovpn"
$trigger = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

Register-ScheduledTask -TaskName "AlwaysOn-VPN" -Action $action -Trigger $trigger -Principal $principal -Settings $settings
```

#### 4. Join Windows to Active Directory

```powershell
# First, ensure VPN is connected
# Test connectivity to domain controller
Test-NetConnection -ComputerName "172.31.24.176" -Port 389

# Join domain
$domain = "customer.domain"  # Replace with your domain name
$credential = Get-Credential -Message "Enter domain admin credentials"

Add-Computer -DomainName $domain -Credential $credential -Restart
```

**Manual Domain Join (via GUI):**
1. Open Settings → System → About
2. Click "Rename this PC (advanced)"
3. Click "Change..."
4. Select "Domain" and enter: `customer.domain`
5. Enter domain admin credentials when prompted
6. Reboot when prompted

#### 5. Install AWS WorkSpaces Client

**Automated Installation:**

```powershell
# Download WorkSpaces client
$url = "https://d2td7dqidlhjx7.cloudfront.net/prod/global/windows/Amazon+WorkSpaces.msi"
$output = "$env:TEMP\AmazonWorkSpaces.msi"
Invoke-WebRequest -Uri $url -OutFile $output

# Install silently
Start-Process msiexec.exe -ArgumentList "/i `"$output`" /qn /norestart" -Wait

# Clean up
Remove-Item $output
```

**Manual Installation:**
1. Download from: https://clients.amazonworkspaces.com/
2. Run installer
3. Complete setup wizard

#### 6. Configure WorkSpaces Auto-Launch

```powershell
# Create startup shortcut for WorkSpaces
$WshShell = New-Object -comObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut("$env:ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp\WorkSpaces.lnk")
$Shortcut.TargetPath = "C:\Program Files\Amazon Web Services, Inc\Amazon WorkSpaces\workspaces.exe"
$Shortcut.Save()
```

#### 7. Configure Thin Client Settings

**Disable unnecessary services:**

```powershell
# Disable Windows Update (managed via GPO instead)
Stop-Service wuauserv
Set-Service wuauserv -StartupType Disabled

# Disable Windows Defender (if managed centrally)
Set-MpPreference -DisableRealtimeMonitoring $true

# Configure power settings (never sleep)
powercfg /change standby-timeout-ac 0
powercfg /change standby-timeout-dc 0
powercfg /change monitor-timeout-ac 30
powercfg /change monitor-timeout-dc 30
```

**Optimize for thin client use:**

```powershell
# Disable visual effects
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" -Name "VisualFXSetting" -Value 2

# Disable search indexing
Stop-Service WSearch
Set-Service WSearch -StartupType Disabled

# Remove unnecessary apps (example - adjust as needed)
Get-AppxPackage *Microsoft.XboxApp* | Remove-AppxPackage
Get-AppxPackage *Microsoft.WindowsMaps* | Remove-AppxPackage
```

---

## Group Policy Deployment

For enterprise deployments, use Group Policy to centrally manage thin client configuration.

### Create GPO in AWS Managed AD

#### Option 1: Via PowerShell (Remote Management)

```powershell
# Install RSAT tools if not already installed
Install-WindowsFeature -Name GPMC

# Connect to AWS Managed AD
$domain = "customer.domain"
$credential = Get-Credential -Message "Enter AD admin credentials"

# Create new GPO
New-GPO -Name "WorkSpaces-ThinClient-Policy" -Domain $domain

# Link to domain root
New-GPLink -Name "WorkSpaces-ThinClient-Policy" -Target "dc=$($domain.Replace('.',',dc='))"
```

#### Option 2: Via Windows Management Instance

Launch a Windows management instance in the VPC, join it to the domain, and use Group Policy Management Console.

### GPO Settings for Thin Client

#### Computer Configuration

**Administrative Templates → Network → Network Connections → Windows Firewall**
- Enable: "Windows Firewall: Protect all network connections"
- Configure: Allow WorkSpaces traffic (port 4172/TCP for DCV)

**Administrative Templates → System → Logon**
- Enable: "Always wait for the network at computer startup and logon"
- This ensures VPN is connected before login

**Administrative Templates → System → Power Management**
- Disable: "Allow standby states when sleeping (plugged in)"

**Administrative Templates → Windows Components → Windows Update**
- Configure: "Configure Automatic Updates" → "4 - Auto download and schedule install"

**Preferences → Windows Settings → Registry**

Set auto-connect VPN:
- Key: `HKLM\SOFTWARE\OpenVPN`
- Value name: `auto_connect`
- Value type: `REG_DWORD`
- Value data: `1`

#### User Configuration

**Administrative Templates → System → Ctrl+Alt+Del Options**
- Disable: "Remove Change Password"
- Disable: "Remove Lock Computer"
- Disable: "Remove Task Manager"

**Administrative Templates → Desktop**
- Enable: "Hide and disable all items on the desktop"
- This creates kiosk-like experience

**Preferences → Windows Settings → Shortcuts**

Create WorkSpaces shortcut on desktop:
- Name: "AWS WorkSpaces"
- Target: `C:\Program Files\Amazon Web Services, Inc\Amazon WorkSpaces\workspaces.exe`
- Location: Desktop

**Preferences → Control Panel Settings → Scheduled Tasks**

Auto-launch WorkSpaces on login:
- Action: Create
- General → Run whether user is logged on or not
- Triggers → At log on
- Actions → Start program: `workspaces.exe`

### Apply GPO to Thin Client OUs

```powershell
# Create OU for thin clients
New-ADOrganizationalUnit -Name "ThinClients" -Path "dc=customer,dc=domain"

# Link GPO to OU
New-GPLink -Name "WorkSpaces-ThinClient-Policy" -Target "ou=ThinClients,dc=customer,dc=domain" -LinkEnabled Yes

# Force GPO update on target computer
Invoke-GPUpdate -Computer "THINCLIENT01" -Force
```

### Export GPO for Deployment

```powershell
# Backup GPO for version control
Backup-GPO -Name "WorkSpaces-ThinClient-Policy" -Path "C:\GPO-Backups"

# Import to another domain
Import-GPO -BackupId <GUID> -Path "C:\GPO-Backups" -TargetName "WorkSpaces-ThinClient-Policy" -CreateIfNeeded
```

---

## Testing and Validation

### Pre-Deployment Testing

#### 1. Test VPN Connectivity

```powershell
# Test VPN connection
Test-NetConnection -ComputerName "cvpn-endpoint-XXXXX.prod.clientvpn.us-gov-west-1.amazonaws.com" -Port 443

# Check VPN service status
Get-Service OpenVPNService | Format-List

# View VPN logs
Get-Content "C:\Program Files\OpenVPN\log\customer-vpn.log" -Tail 50
```

**Expected VPN log output:**
```
Initialization Sequence Completed
Data Channel: using negotiated cipher 'AES-256-GCM'
Peer Connection Initiated with [AF_INET]100.65.0.130:443
```

#### 2. Test DNS Resolution

```powershell
# Check DNS configuration
Get-DnsClientServerAddress -InterfaceAlias "OpenVPN*"

# Test DNS resolution to AD
Resolve-DnsName -Name "customer.domain"
Resolve-DnsName -Name "_ldap._tcp.customer.domain" -Type SRV

# Test connectivity to domain controllers
Test-NetConnection -ComputerName "172.31.24.176" -Port 389
Test-NetConnection -ComputerName "172.31.12.32" -Port 389
```

**Expected output:**
```
Server: 172.31.24.176
Address: 172.31.24.176

Name: customer.domain
Address: 172.31.24.176
Address: 172.31.12.32
```

#### 3. Test Domain Join

```powershell
# Verify domain membership
Get-ComputerInfo | Select-Object CsDomain, CsDomainRole

# Test domain authentication
Test-ComputerSecureChannel -Server "customer.domain" -Verbose

# List domain controllers
nltest /dclist:customer.domain
```

#### 4. Test WorkSpaces Connection

```powershell
# Launch WorkSpaces
Start-Process "C:\Program Files\Amazon Web Services, Inc\Amazon WorkSpaces\workspaces.exe"

# Check WorkSpaces registry entries
Get-ItemProperty -Path "HKCU:\Software\Amazon Web Services, Inc\Amazon WorkSpaces"
```

**Manual test:**
1. Launch WorkSpaces client
2. Enter registration code
3. Login with domain credentials: `DOMAIN\username`
4. Verify workspace launches successfully

### Post-Deployment Validation

#### Complete Boot-to-WorkSpace Test

1. **Reboot device:**
   ```powershell
   Restart-Computer -Force
   ```

2. **Verify VPN auto-connects:**
   - Check system tray for OpenVPN icon
   - Should show "Connected" before login screen

3. **Login with domain credentials:**
   - Use format: `DOMAIN\username`
   - Enter password and MFA code

4. **Verify WorkSpaces auto-launches:**
   - WorkSpaces client should start automatically
   - Should connect to workspace without re-authentication (SSO)

5. **Check network connectivity:**
   ```powershell
   # From WorkSpace, verify connectivity
   ipconfig /all
   ping google.com
   Test-NetConnection -ComputerName "s3-fips.us-gov-west-1.amazonaws.com" -Port 443
   ```

#### Troubleshooting Commands

```powershell
# View VPN status
Get-Service OpenVPNService
netsh interface show interface

# View domain membership
systeminfo | findstr /B /C:"Domain"

# Test AD connectivity
nltest /dsgetdc:customer.domain

# View WorkSpaces logs
Get-Content "$env:LOCALAPPDATA\Amazon Web Services\Amazon WorkSpaces\logs\workspaces.log" -Tail 100

# Check GPO application
gpresult /r
gpresult /h C:\GPOReport.html

# Force GPO update
gpupdate /force
```

---

## Troubleshooting

### VPN Issues

#### Problem: VPN doesn't auto-connect on boot

**Symptoms:**
- No VPN connection before login
- Cannot reach domain controllers
- Login shows "domain not available"

**Solutions:**

1. Check OpenVPN service status:
   ```powershell
   Get-Service OpenVPNService | Format-List
   Set-Service OpenVPNService -StartupType Automatic
   Start-Service OpenVPNService
   ```

2. Verify config file location:
   ```powershell
   Test-Path "C:\Program Files\OpenVPN\config\customer-vpn.ovpn"
   ```

3. Check Windows Event Logs:
   ```powershell
   Get-EventLog -LogName Application -Source OpenVPN -Newest 20
   ```

4. Enable OpenVPN logging:
   - Edit `customer-vpn.ovpn`
   - Add: `log "C:\Program Files\OpenVPN\log\customer-vpn.log"`
   - Add: `verb 4` (increase verbosity)

#### Problem: VPN connects but can't reach domain controllers

**Symptoms:**
- VPN shows "Connected"
- Can't ping 172.31.24.176 or 172.31.12.32
- DNS resolution fails

**Solutions:**

1. Check VPN routes:
   ```powershell
   route print
   # Should see route to 172.31.0.0/16 via VPN interface
   ```

2. Verify DNS configuration:
   ```powershell
   ipconfig /all
   # Should show 172.31.24.176 and 172.31.12.32 as DNS servers
   ```

3. Check Client VPN authorization rules (AWS side):
   ```bash
   aws ec2 describe-client-vpn-authorization-rules \
     --client-vpn-endpoint-id cvpn-endpoint-XXXXX \
     --region us-gov-west-1
   ```

4. Verify security groups allow VPN traffic:
   ```bash
   # Check VPC security groups
   aws ec2 describe-security-groups --region us-gov-west-1
   ```

#### Problem: Certificate authentication fails

**Symptoms:**
- VPN shows "AUTH_FAILED"
- Log shows "certificate verify failed"

**Solutions:**

1. Verify certificate in .ovpn file:
   ```powershell
   # Extract and check certificate
   Select-String -Path "customer-vpn.ovpn" -Pattern "<cert>","</cert>" -Context 0,10
   ```

2. Check certificate expiration:
   ```bash
   # On Mac/Linux where cert was generated
   openssl x509 -in pki/issued/customer-device.crt -noout -dates
   ```

3. Verify CA certificate uploaded to AWS ACM:
   ```bash
   aws acm describe-certificate \
     --certificate-arn "arn:aws-us-gov:acm:us-gov-west-1:ACCOUNT:certificate/CERT_ID" \
     --region us-gov-west-1
   ```

### Domain Join Issues

#### Problem: Cannot join domain

**Symptoms:**
- Error: "The specified domain either does not exist or could not be contacted"
- VPN is connected but domain join fails

**Solutions:**

1. Test DNS resolution:
   ```powershell
   nslookup customer.domain
   nslookup -type=SRV _ldap._tcp.customer.domain
   ```

2. Test LDAP connectivity:
   ```powershell
   Test-NetConnection -ComputerName "172.31.24.176" -Port 389
   Test-NetConnection -ComputerName "172.31.24.176" -Port 636  # LDAPS
   ```

3. Verify time synchronization:
   ```powershell
   w32tm /query /status
   # Kerberos requires time within 5 minutes
   ```

4. Check firewall rules:
   ```powershell
   Get-NetFirewallRule -DisplayName "*Domain*" | Format-Table
   ```

5. Use correct domain admin account:
   - AWS Managed AD: Use `Admin` user or delegated admin
   - Not regular user accounts

#### Problem: Domain joined but can't login

**Symptoms:**
- Device shows as joined in AD
- Login fails with "The trust relationship between this workstation and the primary domain failed"

**Solutions:**

1. Reset computer account:
   ```powershell
   Test-ComputerSecureChannel -Repair -Credential (Get-Credential)
   ```

2. Verify device is in correct OU:
   ```powershell
   Get-ADComputer -Identity COMPUTERNAME | Select-Object DistinguishedName
   ```

3. Check GPO application:
   ```powershell
   gpresult /r
   ```

### WorkSpaces Issues

#### Problem: WorkSpaces client doesn't auto-launch

**Symptoms:**
- User logs in successfully
- Desktop appears but WorkSpaces doesn't start

**Solutions:**

1. Check startup shortcut:
   ```powershell
   Test-Path "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp\WorkSpaces.lnk"
   ```

2. Verify WorkSpaces installation:
   ```powershell
   Test-Path "C:\Program Files\Amazon Web Services, Inc\Amazon WorkSpaces\workspaces.exe"
   Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" | Where-Object DisplayName -like "*WorkSpaces*"
   ```

3. Check GPO settings:
   ```powershell
   gpresult /h C:\GPOReport.html
   # Open report and check user configuration
   ```

4. Manual test launch:
   ```powershell
   Start-Process "C:\Program Files\Amazon Web Services, Inc\Amazon WorkSpaces\workspaces.exe"
   ```

#### Problem: WorkSpaces requires re-authentication (no SSO)

**Symptoms:**
- WorkSpaces launches but prompts for credentials
- Should use Windows login automatically

**Solutions:**

1. Verify domain membership:
   ```powershell
   (Get-WmiObject Win32_ComputerSystem).PartOfDomain
   # Should return True
   ```

2. Check WorkSpaces directory configuration (AWS side):
   ```bash
   aws workspaces describe-workspace-directories --region us-gov-west-1
   # Verify EnableWorkDocs is true for SSO
   ```

3. Verify user exists in AD:
   ```powershell
   Get-ADUser -Identity username
   ```

4. Check WorkSpaces registration:
   - WorkSpaces client → Settings → Registration
   - Should show registered with directory

---

## CMMC Compliance

### Authentication Controls

This deployment implements defense-in-depth authentication required for CMMC Level 2:

| Layer | Control | Implementation |
|-------|---------|----------------|
| 1. Device Authentication | AC.L2-3.1.18 | Certificate-based VPN authentication |
| 2. Network Access | AC.L2-3.1.12 | Client VPN with mutual TLS |
| 3. User Authentication | IA.L2-3.5.3 | AWS Managed AD with password policy |
| 4. Multi-Factor | IA.L2-3.5.3 | MFA required for WorkSpaces access |

### Certificate-Based Device Authentication

**Control: AC.L2-3.1.18** - Control connection of mobile devices

**Implementation:**
- Each thin client has unique certificate in device store
- Certificate required to establish VPN tunnel
- No username/password for device authentication
- Certificate rotation every 2 years (configurable)

**Evidence:**
```powershell
# View installed certificates
Get-ChildItem Cert:\LocalMachine\My | Where-Object {$_.Subject -like "*customer-device*"}

# Export for audit
Get-ChildItem Cert:\LocalMachine\My | Export-Certificate -FilePath C:\device-cert.cer
```

### Network Segmentation

**Control: SC.L2-3.13.1** - Boundary protection

**Implementation:**
- Customer network isolated from AWS GovCloud
- VPN tunnel provides encrypted boundary
- Split-tunnel configuration limits scope
- Only WorkSpaces traffic traverses VPN

**Architecture:**
```
Customer Network (Untrusted) <--[VPN Tunnel]--> AWS GovCloud (Trusted)
                                    ↓
                            AWS Managed AD + WorkSpaces
```

### Audit Logging

**Control: AU.L2-3.3.1** - Create and retain audit records

**Implementation:**
- VPN connection logs in CloudWatch
- AD authentication logs in AWS Managed AD
- WorkSpaces access logs in CloudWatch
- Windows Event Logs on thin client

**Enable comprehensive logging:**

```powershell
# Enable Windows audit logging
auditpol /set /category:"Logon/Logoff" /success:enable /failure:enable
auditpol /set /category:"Account Logon" /success:enable /failure:enable

# Configure log forwarding to SIEM (example: CloudWatch)
# Install CloudWatch agent
Invoke-WebRequest -Uri "https://s3.amazonaws.com/amazoncloudwatch-agent/windows/amd64/latest/amazon-cloudwatch-agent.msi" -OutFile "cloudwatch-agent.msi"
Start-Process msiexec.exe -ArgumentList "/i cloudwatch-agent.msi /qn" -Wait

# Configure agent to forward Security logs
# Edit: C:\ProgramData\Amazon\AmazonCloudWatchAgent\amazon-cloudwatch-agent.json
```

**AWS side logging:**

```bash
# Enable VPN connection logging
aws ec2 modify-client-vpn-endpoint \
  --client-vpn-endpoint-id cvpn-endpoint-XXXXX \
  --connection-log-options 'Enabled=true,CloudwatchLogGroup=/aws/vpn/customer-name,CloudwatchLogStream=vpn-connections' \
  --region us-gov-west-1

# Enable WorkSpaces logging
aws workspaces modify-workspace-properties \
  --workspace-id ws-XXXXX \
  --workspace-properties UserVolumeEncryptionEnabled=true,RootVolumeEncryptionEnabled=true \
  --region us-gov-west-1
```

### Data Protection

**Control: SC.L2-3.13.8** - Implement cryptographic mechanisms

**Implementation:**
- VPN tunnel uses AES-256-GCM encryption
- TLS 1.2+ for all connections
- WorkSpaces uses TLS for DCV protocol
- Certificates use RSA 2048-bit keys minimum

**Verify encryption:**

```powershell
# Check VPN cipher
Select-String -Path "C:\Program Files\OpenVPN\log\customer-vpn.log" -Pattern "cipher"
# Should show: AES-256-GCM

# Check TLS version
[System.Net.ServicePointManager]::SecurityProtocol
# Should include: Tls12, Tls13
```

### Configuration Management

**Control: CM.L2-3.4.2** - Establish and enforce security configuration settings

**Implementation:**
- Group Policy enforces security baselines
- VPN configuration managed centrally
- Automatic Windows updates via GPO
- PowerShell DSC for configuration drift detection

**Example DSC configuration:**

```powershell
Configuration ThinClientBaseline {
    Node "THINCLIENT01" {
        Service OpenVPN {
            Name = "OpenVPNService"
            StartupType = "Automatic"
            State = "Running"
        }

        File VPNConfig {
            DestinationPath = "C:\Program Files\OpenVPN\config\customer-vpn.ovpn"
            Ensure = "Present"
            Checksum = "SHA-256"
            ChecksumType = "SHA-256"
        }

        Registry AutoConnect {
            Key = "HKLM:\SOFTWARE\OpenVPN"
            ValueName = "auto_connect"
            ValueData = "1"
            ValueType = "Dword"
        }
    }
}

# Compile and apply
ThinClientBaseline -OutputPath C:\DSC
Start-DscConfiguration -Path C:\DSC -Wait -Verbose
```

### Compliance Documentation

**Artifacts to maintain:**

1. **System Security Plan (SSP) Section:**
   - Architecture diagram (included in this guide)
   - Network flow diagram
   - Authentication flow
   - Certificate lifecycle

2. **Configuration Baselines:**
   - GPO export (`Backup-GPO`)
   - PowerShell DSC configuration
   - VPN configuration template
   - Windows security baseline

3. **Test Results:**
   - Penetration test reports
   - Vulnerability scans
   - Authentication testing
   - Encryption verification

4. **Operational Procedures:**
   - Certificate rotation procedure
   - Incident response plan
   - Device provisioning checklist
   - Device decommissioning procedure

---

## Scaling Considerations

### Multi-Customer Deployment

For 50+ customers with 1-2 devices each:

**Certificate Management:**
- One certificate per customer (not per device)
- Easier rotation and management
- Devices can share certificate via secure distribution

**Automation:**
- Create master image with all base configuration
- Use Intune or SCCM for deployment at scale
- GPO templates for each customer
- PowerShell scripts for certificate injection

**Example provisioning workflow:**

```powershell
# Master provisioning script
param(
    [Parameter(Mandatory=$true)]
    [string]$CustomerName,

    [Parameter(Mandatory=$true)]
    [string]$DomainName,

    [Parameter(Mandatory=$true)]
    [string]$CertificatePath,

    [Parameter(Mandatory=$true)]
    [string]$VPNEndpoint
)

# 1. Copy VPN configuration
Copy-Item -Path "$CertificatePath\$CustomerName-vpn.ovpn" -Destination "C:\Program Files\OpenVPN\config\" -Force

# 2. Configure domain join
$credential = Get-Credential -Message "Enter domain admin for $DomainName"
Add-Computer -DomainName $DomainName -Credential $credential

# 3. Install WorkSpaces
Invoke-WebRequest -Uri "https://d2td7dqidlhjx7.cloudfront.net/prod/global/windows/Amazon+WorkSpaces.msi" -OutFile "$env:TEMP\WorkSpaces.msi"
Start-Process msiexec.exe -ArgumentList "/i `"$env:TEMP\WorkSpaces.msi`" /qn" -Wait

# 4. Configure auto-start
# [Startup configuration here]

# 5. Reboot
Restart-Computer -Force
```

### Centralized Management via Intune

For customers using Microsoft Intune:

```powershell
# Create Intune configuration profile
$vpnProfile = @{
    '@odata.type' = '#microsoft.graph.windows10VpnConfiguration'
    displayName = 'AWS-WorkSpaces-VPN'
    connectionName = 'AWS-VPN'
    servers = @(@{
        description = 'AWS Client VPN'
        address = 'cvpn-endpoint-XXXXX.prod.clientvpn.us-gov-west-1.amazonaws.com'
        isDefaultServer = $true
    })
    connectionType = 'pulseSecure'  # Or appropriate type
    authenticationMethod = 'certificate'
}

# Deploy via Microsoft Graph API
Invoke-RestMethod -Method Post -Uri "https://graph.microsoft.com/v1.0/deviceManagement/deviceConfigurations" -Body ($vpnProfile | ConvertTo-Json) -Headers $headers
```

---

## Summary

This Windows deployment provides:

- ✅ Pre-login VPN with certificate authentication
- ✅ Native Active Directory integration
- ✅ Single Sign-On to AWS WorkSpaces
- ✅ Group Policy central management
- ✅ CMMC Level 2 compliance
- ✅ Scalable to 50+ customers
- ✅ Automated provisioning with PowerShell

**Next Steps:**
1. Generate certificates for test customer
2. Configure Client VPN endpoint in AWS
3. Test on Windows laptop
4. Create customer-specific GPO
5. Document customer onboarding procedure

For Linux deployment, see [DEPLOYMENT-GUIDE.md](DEPLOYMENT-GUIDE.md).
