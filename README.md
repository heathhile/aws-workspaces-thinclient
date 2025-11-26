# AWS WorkSpaces Thin Client for GovCloud

Convert commodity hardware into a secure, locked-down thin client for AWS WorkSpaces in GovCloud environments. This project provides automated scripts and comprehensive documentation to transform any x86_64 Linux-compatible device into a dedicated WorkSpaces endpoint.

## Overview

AWS WorkSpaces is available in AWS GovCloud (US) with support for DCV/WSP protocols. However, the Amazon WorkSpaces Thin Client hardware device is **not available in GovCloud regions**. This project solves that problem by enabling you to repurpose existing hardware as thin clients.

### Tested Hardware

- **AWOW AK34 Pro** Mini PC (Intel Celeron J3455, 6-8GB RAM)
- Any x86_64 system capable of running Ubuntu 22.04 LTS or newer

### Supported Protocols

- **DCV/WSP (WorkSpaces Streaming Protocol)** - Recommended for GovCloud
- **Web Browser Access** - Alternative lightweight option

## Features

- **Automated Setup** - Single script installation
- **Two Deployment Options**:
  - Native WorkSpaces client with full feature support
  - Browser-based kiosk mode (ultra-lightweight)
- **OpenVPN Pre-Login Support** - Connect to VPN before user login for AWS Managed AD authentication
- **Security Hardening**:
  - Auto-login with locked-down user permissions
  - Firewall configuration (outbound-only)
  - Disabled unnecessary services
  - Automatic security updates
- **Zero-Touch Operation** - Auto-start WorkSpaces on boot
- **GovCloud Compatible** - Designed for AWS GovCloud (US) environments
- **CMMC Compliance Ready** - MFA support, encrypted sessions, audit logging

## Quick Start

### Option 1: Native WorkSpaces Client (Recommended)

For full feature support including USB redirection, multiple monitors, and optimal performance:

```bash
# Download the script
wget https://raw.githubusercontent.com/YOUR-USERNAME/aws-workspaces-thinclient/main/setup-workspaces-thinclient.sh

# Make it executable
chmod +x setup-workspaces-thinclient.sh

# Run as root
sudo ./setup-workspaces-thinclient.sh
```

### Option 2: Browser-Based Kiosk (Lightweight)

For a minimal footprint with web-only access:

```bash
# Download the script
wget https://raw.githubusercontent.com/YOUR-USERNAME/aws-workspaces-thinclient/main/setup-browser-kiosk.sh

# Make it executable
chmod +x setup-browser-kiosk.sh

# Run as root
sudo ./setup-browser-kiosk.sh
```

### Option 3: Add OpenVPN Pre-Login (AWS Managed AD Integration)

For environments using AWS Managed AD authentication, configure OpenVPN to connect before user login:

```bash
# First, run Option 1 (native client setup)
# Then configure OpenVPN for pre-login VPN connection

# Download the OpenVPN setup script
wget https://raw.githubusercontent.com/YOUR-USERNAME/aws-workspaces-thinclient/main/setup-openvpn-prelogin.sh

# Make it executable
chmod +x setup-openvpn-prelogin.sh

# Run as root (have your .ovpn file and credentials ready)
sudo ./setup-openvpn-prelogin.sh
```

This enables:
- VPN connection established at boot (before login screen)
- DNS points to AWS Managed AD domain controllers
- Users authenticate with AD credentials (DOMAIN\username)
- Seamless WorkSpaces login with AD credentials

## Prerequisites

### System Requirements

- **OS**: Ubuntu 24.04 LTS or Ubuntu 22.04 LTS (fresh installation recommended)
- **Architecture**: x86_64
- **RAM**: 2GB minimum, 4GB+ recommended
- **Storage**: 16GB minimum
- **Network**: Stable internet connection during setup

### Before You Begin

1. **Fresh OS Installation** - Start with a clean Ubuntu installation
2. **Internet Connection** - Ensure stable network connectivity
3. **WorkSpaces Information** - Have your WorkSpaces registration code or URL ready
4. **Root Access** - You'll need sudo privileges

### AWS WorkSpaces GovCloud Configuration

Ensure your AWS WorkSpaces environment is configured for GovCloud:

- WorkSpaces must be in AWS GovCloud (US-West or US-East)
- Using DCV/WSP protocol (not PCoIP for web access)
- Registration code or custom URL available

## Installation Guide

### Detailed Installation Steps

#### 1. Prepare Your Hardware

1. Install Ubuntu 24.04 LTS on your device (AWOW AK34 Pro or similar)
2. Complete the basic Ubuntu setup wizard
3. Connect to your network (wired connection recommended)
4. Update the system:
   ```bash
   sudo apt update && sudo apt upgrade -y
   ```

#### 2. Download and Run Setup Script

Choose your preferred method:

**Native Client Method:**
```bash
cd ~
wget https://raw.githubusercontent.com/YOUR-USERNAME/aws-workspaces-thinclient/main/setup-workspaces-thinclient.sh
chmod +x setup-workspaces-thinclient.sh
sudo ./setup-workspaces-thinclient.sh
```

**Browser Kiosk Method:**
```bash
cd ~
wget https://raw.githubusercontent.com/YOUR-USERNAME/aws-workspaces-thinclient/main/setup-browser-kiosk.sh
chmod +x setup-browser-kiosk.sh
sudo ./setup-browser-kiosk.sh
```

#### 3. Post-Installation

1. **Change Default Password** (CRITICAL):
   ```bash
   # For native client setup
   sudo passwd workspaces

   # For browser kiosk setup
   sudo passwd kiosk
   ```

2. **Reboot the System**:
   ```bash
   sudo reboot
   ```

3. **First Login**:
   - System will auto-login
   - WorkSpaces client or browser will launch automatically
   - Enter your WorkSpaces registration code or credentials

## Configuration Details

### Native Client Setup

**What Gets Installed:**
- AWS WorkSpaces client (latest version)
- Minimal desktop environment
- Required dependencies (libusb, libudev, etc.)

**User Account:**
- Username: `workspaces`
- Default Password: `workspaces` (CHANGE THIS!)
- Auto-login: Enabled
- Auto-start: WorkSpaces client launches on boot

**Security Features:**
- Root account locked
- User removed from sudo group
- UFW firewall enabled (outbound-only)
- Bluetooth, CUPS, Avahi disabled
- Automatic security updates enabled

### Browser Kiosk Setup

**What Gets Installed:**
- Minimal X server (Xorg)
- Openbox window manager
- Chromium browser (or Firefox)
- LightDM display manager

**User Account:**
- Username: `kiosk`
- Default Password: `kiosk` (CHANGE THIS!)
- Auto-login: Enabled
- Auto-start: Browser in kiosk mode

**Kiosk Features:**
- Full-screen browser, no toolbars
- Screen blanking disabled
- Virtual terminal switching disabled
- Recovery instructions at `/home/kiosk/RECOVERY.txt`

## Usage

### Daily Operation

1. **Power on** the device
2. System auto-boots and auto-logs in
3. WorkSpaces launches automatically
4. Connect to your WorkSpaces session
5. Work as normal
6. **Power off** when done (or leave running)

### Accessing for Maintenance

**SSH Access (Recommended):**
```bash
# From another computer on the same network
ssh workspaces@<thin-client-ip>
# or
ssh kiosk@<thin-client-ip>
```

**Finding the IP Address:**
```bash
# On the thin client (if you have console access)
hostname -I
```

### Changing WorkSpaces URL (Browser Kiosk)

```bash
# SSH into the device
ssh kiosk@<ip-address>

# Edit the autostart file
nano ~/.config/openbox/autostart

# Update the URL in the browser launch command
# Save and reboot
sudo reboot
```

## Troubleshooting

### WorkSpaces Client Won't Launch

**Check if client is installed:**
```bash
ls -l /opt/workspacesclient/
```

**Manually launch client:**
```bash
/opt/workspacesclient/workspacesclient
```

**Check autostart configuration:**
```bash
cat ~/.config/autostart/workspaces.desktop
```

### Browser Kiosk Not Loading

**Check browser installation:**
```bash
which chromium-browser
```

**Check Openbox autostart:**
```bash
cat ~/.config/openbox/autostart
```

**View Openbox logs:**
```bash
cat ~/.xsession-errors
```

### Network Issues

**Test connectivity:**
```bash
ping 8.8.8.8
ping clients.amazonworkspaces.com
```

**Check firewall:**
```bash
sudo ufw status
```

**Required ports for WorkSpaces:**
- TCP 443 (HTTPS)
- TCP 4172 (DCV)
- UDP 4172 (DCV)

### Can't Access via SSH

**Enable SSH if needed:**
```bash
sudo apt install openssh-server
sudo systemctl enable ssh
sudo systemctl start ssh
```

**Check firewall:**
```bash
sudo ufw allow ssh
```

### Auto-Login Not Working

**Check display manager config:**
```bash
# For GDM
cat /etc/gdm3/custom.conf

# For LightDM
cat /etc/lightdm/lightdm.conf
```

**Manually configure auto-login:**
Edit the appropriate config file and ensure:
```ini
[daemon]
AutomaticLoginEnable=true
AutomaticLogin=workspaces
```

## Recovery & Restore

### Restoring to Normal Desktop

Use the provided restore script:

```bash
sudo ./restore-thinclient.sh
```

This will:
- Remove auto-login configuration
- Re-enable sudo access for the user
- Install a full desktop environment
- Restore normal system services

### Manual Recovery

If the restore script isn't available:

```bash
# Re-enable sudo access
sudo usermod -aG sudo workspaces

# Install full desktop
sudo apt install ubuntu-desktop

# Disable auto-login
sudo nano /etc/gdm3/custom.conf
# Comment out AutomaticLogin lines

# Reboot
sudo reboot
```

## Security Considerations

### Default Configuration

The scripts implement several security hardening measures:

1. **Minimal Attack Surface** - Only essential services running
2. **Locked Root Account** - Root login disabled
3. **Restricted User** - Kiosk user has no sudo access
4. **Firewall** - UFW configured for outbound-only
5. **Automatic Updates** - Daily security patches with auto-reboot at 3 AM

### Additional Hardening (Optional)

For enhanced security in GovCloud environments:

**Disable USB Storage:**
```bash
echo "blacklist usb-storage" | sudo tee /etc/modprobe.d/blacklist-usb-storage.conf
sudo update-initramfs -u
```

**Enable AppArmor:**
```bash
sudo systemctl enable apparmor
sudo systemctl start apparmor
```

**Configure SSH Key-Only Authentication:**
```bash
# Copy your public key
ssh-copy-id workspaces@<ip-address>

# Disable password authentication
sudo nano /etc/ssh/sshd_config
# Set: PasswordAuthentication no
sudo systemctl restart ssh
```

## Comparison: Native Client vs Browser Kiosk

| Feature | Native Client | Browser Kiosk |
|---------|--------------|---------------|
| **Disk Space** | ~2GB | ~800MB |
| **RAM Usage** | ~1GB | ~500MB |
| **USB Redirection** | Yes | No |
| **Multiple Monitors** | Yes | Limited |
| **Performance** | Optimal | Good |
| **Setup Complexity** | Medium | Low |
| **Offline Capability** | Partial | No |
| **Smart Card Support** | Yes | No |
| **Webcam/Audio** | Full Support | Browser-dependent |

## Cost Comparison

| Solution | Hardware Cost | Software Cost | Total |
|----------|--------------|---------------|-------|
| Amazon WorkSpaces Thin Client | $195 | $0 | $195 |
| AWOW AK34 Pro (new) | ~$150 | $0 | $150 |
| Repurposed hardware | $0 | $0 | $0 |

**Note:** Amazon WorkSpaces Thin Client is not available in GovCloud regions.

## Advanced Configuration

### Custom Branding

**Change Login Screen:**
```bash
sudo cp your-logo.png /usr/share/pixmaps/login-logo.png
```

**Custom Wallpaper:**
```bash
gsettings set org.gnome.desktop.background picture-uri file:///path/to/wallpaper.jpg
```

### Multiple WorkSpaces Support

To configure for multiple WorkSpaces environments:

1. Don't configure auto-login
2. Create separate user accounts for each WorkSpaces environment
3. Configure each user's autostart independently

### AWS Managed AD Integration with OpenVPN

For organizations using AWS Managed Active Directory:

**Network Flow:**
1. Thin client boots
2. OpenVPN connects automatically (before login screen)
3. DNS configured to point to AWS Managed AD domain controllers
4. User sees login screen
5. User enters AD credentials: `DOMAIN\username`
6. WorkSpaces client launches with authenticated AD session

**Setup Process:**
```bash
# 1. Set up thin client
sudo ./setup-workspaces-thinclient.sh

# 2. Configure OpenVPN for pre-login
sudo ./setup-openvpn-prelogin.sh
# You'll need:
# - OpenVPN .ovpn configuration file
# - VPN credentials (username/password or certificates)
# - AWS Managed AD DNS server IPs

# 3. Reboot and test
sudo reboot
```

**Check VPN Status:**
```bash
# Simple status check
check-vpn-status

# Detailed service status
systemctl status openvpn-client@thin-client

# View VPN logs
journalctl -u openvpn-client@thin-client -f

# Test AD connectivity
nslookup yourdomain.com
ping YOUR_AD_DOMAIN_CONTROLLER_IP
```

**Troubleshooting AD Authentication:**
- Ensure VPN is connected before login: `check-vpn-status`
- Verify DNS points to AD domain controllers
- Test domain controller connectivity from thin client
- Check WorkSpaces is configured for AD directory in AWS console

### Monitoring and Logging

**Enable system logging:**
```bash
sudo apt install rsyslog
sudo systemctl enable rsyslog
```

**Monitor WorkSpaces client logs:**
```bash
tail -f ~/.workspaces/logs/workspaces_client.log
```

**Monitor VPN logs:**
```bash
tail -f /var/log/syslog | grep ovpn
journalctl -u openvpn-client@thin-client -f
```

## Updating

### Update WorkSpaces Client

The client auto-updates, but you can manually update:

```bash
cd /tmp
wget https://d2td7dqidlhjx7.cloudfront.net/prod/iad/linux/x86_64/WorkSpaces_ubuntu_latest_x86_64.deb
sudo apt install -y ./WorkSpaces_ubuntu_latest_x86_64.deb
rm WorkSpaces_ubuntu_latest_x86_64.deb
```

### Update System Packages

```bash
sudo apt update
sudo apt upgrade -y
```

**Note:** Automatic updates are configured to run daily at 3 AM with auto-reboot.

## Contributing

Contributions welcome! Please submit issues and pull requests on GitHub.

### Development Setup

```bash
git clone https://github.com/YOUR-USERNAME/aws-workspaces-thinclient.git
cd aws-workspaces-thinclient
```

## License

MIT License - See LICENSE file for details

## Support & Resources

### AWS Documentation

- [AWS WorkSpaces in GovCloud](https://docs.aws.amazon.com/govcloud-us/latest/UserGuide/govcloud-workspaces.html)
- [WorkSpaces Networking](https://docs.aws.amazon.com/workspaces/latest/adminguide/amazon-workspaces-networking.html)
- [Amazon DCV Documentation](https://docs.aws.amazon.com/dcv/latest/adminguide/what-is-dcv.html)

### Community

- Report issues on GitHub
- Submit feature requests via GitHub Issues
- Share your deployments and experiences

## Frequently Asked Questions

### Q: Can I use this with commercial AWS (non-GovCloud)?
**A:** Yes! These scripts work with both GovCloud and commercial AWS WorkSpaces.

### Q: Will this work with PCoIP WorkSpaces?
**A:** The native client supports PCoIP, but the browser kiosk does not (PCoIP requires the native client).

### Q: Can I use this on other Linux distributions?
**A:** The scripts are designed for Ubuntu. They may work on Debian-based distributions with modifications.

### Q: How do I add printer support?
**A:** Install CUPS: `sudo apt install cups`. Then configure your printers. WorkSpaces will redirect local printers.

### Q: Can I use a Raspberry Pi?
**A:** The AWS WorkSpaces client is x86_64 only. Use the browser kiosk method instead, but performance may vary.

### Q: How do I enable smart card/CAC support?
**A:** Install required packages: `sudo apt install pcscd pcsc-tools`. The WorkSpaces client supports smart cards natively.

### Q: What about dual monitors?
**A:** The native client fully supports multiple monitors. Browser kiosk support depends on browser capabilities.

### Q: How do I completely remove the thin client setup?
**A:** Use the `restore-thinclient.sh` script or manually reinstall Ubuntu.

## Changelog

### Version 1.0.0 (2025-01-26)
- Initial release
- Native WorkSpaces client setup script
- Browser-based kiosk setup script
- Comprehensive documentation
- AWOW AK34 Pro tested and validated

## Acknowledgments

- AWS WorkSpaces team for DCV/WSP protocol
- Ubuntu community for excellent documentation
- IGEL and other thin client OS providers for inspiration

---

**Made for government agencies and organizations requiring thin client solutions in AWS GovCloud environments.**
