# Manual Installation Guide

This guide provides step-by-step instructions for manually converting your hardware into an AWS WorkSpaces thin client without using the automated scripts. This is useful for understanding the process, customizing the setup, or troubleshooting.

## Table of Contents

1. [Preparation](#preparation)
2. [Method 1: Native WorkSpaces Client](#method-1-native-workspaces-client)
3. [Method 2: Browser-Based Kiosk](#method-2-browser-based-kiosk)
4. [Post-Installation Configuration](#post-installation-configuration)
5. [Verification](#verification)

---

## Preparation

### 1. Install Ubuntu

1. Download Ubuntu 24.04 LTS from [ubuntu.com](https://ubuntu.com/download/desktop)
2. Create a bootable USB drive using:
   - **Rufus** (Windows)
   - **balenaEtcher** (cross-platform)
   - `dd` command (Linux/Mac)
3. Boot your device from the USB drive
4. Follow the Ubuntu installation wizard:
   - Choose "Minimal installation"
   - Enable "Download updates while installing"
   - Enable "Install third-party software"
5. Create a temporary admin user during installation
6. Complete the installation and reboot

### 2. Initial System Setup

Once Ubuntu boots:

```bash
# Update package lists
sudo apt update

# Upgrade existing packages
sudo apt upgrade -y

# Install basic tools
sudo apt install -y wget curl git nano
```

### 3. Check System Requirements

```bash
# Check architecture (should be x86_64)
uname -m

# Check available disk space (should have at least 10GB free)
df -h

# Check available RAM (should have at least 2GB)
free -h

# Test internet connectivity
ping -c 3 8.8.8.8
```

---

## Method 1: Native WorkSpaces Client

### Step 1: Download WorkSpaces Client

```bash
# Navigate to temp directory
cd /tmp

# Download the latest WorkSpaces client for Ubuntu
wget https://d2td7dqidlhjx7.cloudfront.net/prod/iad/linux/x86_64/WorkSpaces_ubuntu_latest_x86_64.deb

# Verify the download
ls -lh WorkSpaces_ubuntu_latest_x86_64.deb
```

### Step 2: Install Dependencies

```bash
# Install required libraries
sudo apt install -y \
    libusb-1.0-0 \
    libudev1 \
    libxcb-xinerama0 \
    ca-certificates \
    gnupg
```

### Step 3: Install WorkSpaces Client

```bash
# Install the .deb package
sudo apt install -y ./WorkSpaces_ubuntu_latest_x86_64.deb

# Verify installation
which workspacesclient
/opt/workspacesclient/workspacesclient --version
```

### Step 4: Create Dedicated User Account

```bash
# Create the workspaces user
sudo useradd -m -s /bin/bash workspaces

# Set a password (use a strong password, not the default!)
sudo passwd workspaces

# Add user to necessary groups
sudo usermod -aG audio,video workspaces
```

### Step 5: Configure Auto-Start

```bash
# Switch to the workspaces user
sudo su - workspaces

# Create autostart directory
mkdir -p ~/.config/autostart

# Create autostart desktop entry
cat > ~/.config/autostart/workspaces.desktop << 'EOF'
[Desktop Entry]
Type=Application
Exec=/opt/workspacesclient/workspacesclient
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
Name=AWS WorkSpaces
Comment=Launch AWS WorkSpaces on startup
EOF

# Exit back to your admin user
exit
```

### Step 6: Create Desktop Shortcut

```bash
# As the workspaces user
sudo su - workspaces

# Create Desktop directory
mkdir -p ~/Desktop

# Create desktop shortcut
cat > ~/Desktop/WorkSpaces.desktop << 'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=AWS WorkSpaces
Comment=Connect to AWS WorkSpaces
Exec=/opt/workspacesclient/workspacesclient
Icon=/opt/workspacesclient/resources/app.asar.unpacked/build/icons/64x64.png
Terminal=false
Categories=Network;RemoteAccess;
EOF

# Make it executable
chmod +x ~/Desktop/WorkSpaces.desktop

# Exit back to admin user
exit
```

### Step 7: Configure Auto-Login

**For GDM3 (GNOME Display Manager):**

```bash
# Edit GDM configuration
sudo nano /etc/gdm3/custom.conf

# Add these lines under [daemon] section:
[daemon]
AutomaticLoginEnable=true
AutomaticLogin=workspaces

# Save and exit (Ctrl+X, Y, Enter)
```

**For LightDM:**

```bash
# Edit LightDM configuration
sudo nano /etc/lightdm/lightdm.conf

# Add these lines under [Seat:*] section:
[Seat:*]
autologin-user=workspaces
autologin-user-timeout=0

# Save and exit
```

### Step 8: Security Hardening (Optional but Recommended)

```bash
# Install and enable firewall
sudo apt install -y ufw
sudo ufw enable
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Allow SSH for remote management
sudo ufw allow ssh

# Disable unnecessary services
sudo systemctl disable bluetooth.service
sudo systemctl disable cups.service
sudo systemctl disable avahi-daemon.service

# Lock root account
sudo passwd -l root

# Remove workspaces user from sudo group (if present)
sudo deluser workspaces sudo
```

### Step 9: Configure Automatic Updates

```bash
# Install unattended-upgrades
sudo apt install -y unattended-upgrades

# Configure automatic updates
sudo dpkg-reconfigure -plow unattended-upgrades

# Edit configuration for automatic reboots
sudo nano /etc/apt/apt.conf.d/50unattended-upgrades

# Find and uncomment/modify these lines:
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "03:00";

# Save and exit
```

### Step 10: Final Steps

```bash
# Reboot to apply all changes
sudo reboot
```

After reboot:
1. System should auto-login as `workspaces` user
2. WorkSpaces client should launch automatically
3. Enter your registration code or WorkSpaces URL
4. Log in to your WorkSpace

---

## Method 2: Browser-Based Kiosk

### Step 1: Install Minimal Desktop Environment

```bash
# Install X server and window manager
sudo apt install -y \
    xorg \
    openbox \
    lightdm \
    pulseaudio \
    network-manager \
    fonts-dejavu
```

### Step 2: Install Browser

**Option A: Chromium (Recommended)**

```bash
sudo apt install -y chromium-browser
```

**Option B: Firefox**

```bash
sudo apt install -y firefox
```

### Step 3: Create Kiosk User

```bash
# Create the kiosk user
sudo useradd -m -s /bin/bash kiosk

# Set password
sudo passwd kiosk

# Add to necessary groups
sudo usermod -aG audio,video kiosk
```

### Step 4: Configure Openbox

```bash
# Switch to kiosk user
sudo su - kiosk

# Create Openbox configuration directory
mkdir -p ~/.config/openbox

# Create autostart script
cat > ~/.config/openbox/autostart << 'EOF'
#!/bin/bash

# Disable screen blanking and power management
xset s off
xset -dpms
xset s noblank

# Wait for network to be ready
sleep 5

# Launch browser in kiosk mode
# Replace YOUR_WORKSPACES_URL with your actual WorkSpaces URL
chromium-browser \
    --kiosk \
    --noerrdialogs \
    --disable-infobars \
    --no-first-run \
    --disable-session-crashed-bubble \
    --disable-features=TranslateUI \
    --check-for-update-interval=31536000 \
    --app="https://clients.amazonworkspaces.com/"
EOF

# Make it executable
chmod +x ~/.config/openbox/autostart

# Create Openbox configuration
cat > ~/.config/openbox/rc.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<openbox_config xmlns="http://openbox.org/3.4/rc">
  <resistance>
    <strength>10</strength>
    <screen_edge_strength>20</screen_edge_strength>
  </resistance>
  <focus>
    <focusNew>yes</focusNew>
    <followMouse>no</followMouse>
  </focus>
  <placement>
    <policy>Smart</policy>
  </placement>
  <theme>
    <name>Clearlooks</name>
    <titleLayout>NLIMC</titleLayout>
  </theme>
  <desktops>
    <number>1</number>
    <firstdesk>1</firstdesk>
  </desktops>
  <keyboard>
    <chainQuitKey>C-g</chainQuitKey>
  </keyboard>
  <applications>
    <application class="*">
      <decor>no</decor>
      <maximized>true</maximized>
    </application>
  </applications>
</openbox_config>
EOF

# Exit back to admin user
exit
```

### Step 5: Configure LightDM for Auto-Login

```bash
# Edit LightDM configuration
sudo nano /etc/lightdm/lightdm.conf

# Add or modify these lines:
[Seat:*]
autologin-user=kiosk
autologin-user-timeout=0
user-session=openbox

# Save and exit
```

### Step 6: Configure Your WorkSpaces URL

```bash
# Edit the autostart file to add your specific URL
sudo nano /home/kiosk/.config/openbox/autostart

# Change this line:
--app="https://clients.amazonworkspaces.com/"

# To your specific WorkSpaces URL:
--app="https://YOUR-WORKSPACE-URL.awsapps.com/workspaces"

# Save and exit
```

### Step 7: Security Hardening

```bash
# Install firewall
sudo apt install -y ufw
sudo ufw enable
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh

# Disable unnecessary services
sudo systemctl disable bluetooth.service
sudo systemctl disable cups.service
sudo systemctl disable avahi-daemon.service

# Disable TTY switching (prevents Ctrl+Alt+F1-F6)
sudo systemctl mask getty@tty2.service
sudo systemctl mask getty@tty3.service
sudo systemctl mask getty@tty4.service
sudo systemctl mask getty@tty5.service
sudo systemctl mask getty@tty6.service

# Lock root account
sudo passwd -l root
```

### Step 8: Install Optional Tools

```bash
# Install unclutter to hide mouse cursor when idle
sudo apt install -y unclutter

# Edit autostart to enable it
sudo nano /home/kiosk/.config/openbox/autostart

# Add this line before the browser launch:
unclutter -idle 5 &

# Save and exit
```

### Step 9: Configure Automatic Updates

```bash
# Install unattended-upgrades
sudo apt install -y unattended-upgrades

# Configure
sudo dpkg-reconfigure -plow unattended-upgrades

# Enable automatic reboots
sudo nano /etc/apt/apt.conf.d/50unattended-upgrades

# Uncomment and set:
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "03:00";

# Save and exit
```

### Step 10: Create Recovery Instructions

```bash
# Create recovery file
sudo su - kiosk

cat > ~/RECOVERY.txt << 'EOF'
AWS WorkSpaces Browser Kiosk - Recovery Instructions
=====================================================

SSH Access:
-----------
ssh kiosk@<ip-address>
Default password: (whatever you set)

Change WorkSpaces URL:
----------------------
1. SSH into device
2. Edit: ~/.config/openbox/autostart
3. Change the --app="URL" line
4. Reboot: sudo reboot

Disable Kiosk Mode:
-------------------
1. SSH into device
2. Edit: /etc/lightdm/lightdm.conf
3. Comment out autologin-user lines
4. Reboot

Exit Kiosk (Emergency):
-----------------------
- Try Ctrl+Alt+Backspace to kill X server
- SSH in from another device
- Boot from USB if necessary
EOF

exit
```

### Step 11: Final Steps

```bash
# Reboot to start kiosk mode
sudo reboot
```

After reboot:
1. System should auto-login as `kiosk` user
2. Openbox starts with no window decorations
3. Browser launches in full-screen kiosk mode
4. WorkSpaces web client loads automatically

---

## Post-Installation Configuration

### Enable SSH for Remote Management

```bash
# Install OpenSSH server
sudo apt install -y openssh-server

# Enable SSH service
sudo systemctl enable ssh
sudo systemctl start ssh

# Allow SSH through firewall
sudo ufw allow ssh

# Find your IP address
hostname -I
```

### Configure Static IP (Optional)

For easier remote management:

```bash
# Identify your network interface
ip link show

# Edit netplan configuration (Ubuntu 24.04)
sudo nano /etc/netplan/01-netcfg.yaml

# Example configuration:
network:
  version: 2
  ethernets:
    eth0:  # Replace with your interface name
      dhcp4: no
      addresses:
        - 192.168.1.100/24
      gateway4: 192.168.1.1
      nameservers:
        addresses: [8.8.8.8, 8.8.4.4]

# Apply the configuration
sudo netplan apply
```

### Customize Appearance

**Change Wallpaper (Native Client):**

```bash
gsettings set org.gnome.desktop.background picture-uri file:///usr/share/backgrounds/your-image.jpg
```

**Custom Login Screen:**

```bash
# Copy your logo
sudo cp your-logo.png /usr/share/pixmaps/login-background.png

# Configure GDM3
sudo nano /etc/gdm3/greeter.dconf-defaults
# Modify background settings
```

---

## Verification

### Test Native Client Setup

1. **Verify auto-login:**
   - Reboot the system
   - Should automatically log in as `workspaces` user

2. **Verify auto-start:**
   - WorkSpaces client should launch automatically
   - Check: `ps aux | grep workspacesclient`

3. **Test WorkSpaces connection:**
   - Enter registration code
   - Connect to a WorkSpace
   - Test keyboard, mouse, audio

4. **Verify security:**
   ```bash
   # Check firewall
   sudo ufw status

   # Check disabled services
   systemctl status bluetooth
   systemctl status cups

   # Verify root is locked
   sudo passwd -S root
   ```

### Test Browser Kiosk Setup

1. **Verify auto-login:**
   - Reboot the system
   - Should automatically log in as `kiosk` user

2. **Verify kiosk mode:**
   - Browser should be full-screen
   - No toolbars or window decorations
   - Should load WorkSpaces URL

3. **Test WorkSpaces web access:**
   - Log in with credentials
   - Test basic functionality

4. **Test recovery access:**
   ```bash
   # From another computer
   ssh kiosk@<ip-address>
   cat ~/RECOVERY.txt
   ```

---

## Common Manual Configuration Issues

### Issue: Auto-login doesn't work

**Solution for GDM3:**
```bash
# Check if GDM3 is running
systemctl status gdm3

# Verify configuration
cat /etc/gdm3/custom.conf

# Restart GDM3
sudo systemctl restart gdm3
```

**Solution for LightDM:**
```bash
# Check configuration
cat /etc/lightdm/lightdm.conf

# Test LightDM
sudo lightdm --test-mode --debug
```

### Issue: WorkSpaces doesn't auto-start

```bash
# Check autostart file exists
ls -la ~/.config/autostart/workspaces.desktop

# Verify it's executable
cat ~/.config/autostart/workspaces.desktop

# Test manually
/opt/workspacesclient/workspacesclient
```

### Issue: Browser kiosk shows errors

```bash
# Check X server errors
cat ~/.xsession-errors

# Check Openbox autostart
cat ~/.config/openbox/autostart

# Test browser manually
chromium-browser --kiosk "https://clients.amazonworkspaces.com/"
```

### Issue: Network not available at boot

```bash
# Add longer delay in autostart
nano ~/.config/openbox/autostart

# Change:
sleep 5
# To:
sleep 15

# Or wait for network:
while ! ping -c 1 8.8.8.8 &> /dev/null; do
    sleep 1
done
```

---

## Next Steps

After completing manual installation:

1. **Change all default passwords**
2. **Test thoroughly before deployment**
3. **Document your specific configuration**
4. **Create a backup/restore plan**
5. **Set up monitoring (optional)**

For easier management, consider using the automated scripts for future deployments.

---

## Additional Resources

- [Ubuntu Server Guide](https://ubuntu.com/server/docs)
- [AWS WorkSpaces Linux Client Documentation](https://docs.aws.amazon.com/workspaces/latest/userguide/amazon-workspaces-linux-client.html)
- [Openbox Documentation](http://openbox.org/wiki/Help:Contents)
- [LightDM Configuration](https://wiki.debian.org/LightDM)
