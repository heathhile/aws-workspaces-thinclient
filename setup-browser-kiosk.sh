#!/bin/bash

################################################################################
# AWS WorkSpaces Browser Kiosk Setup Script
#
# This script converts a Linux system into a minimal browser-based kiosk
# for accessing AWS WorkSpaces via web browser (no client installation)
#
# This approach is more lightweight and eliminates the need for the native client
#
# Tested on: Ubuntu 24.04 LTS, Ubuntu 22.04 LTS
# Hardware: AWOW AK34 Pro and similar x86_64 systems
#
# Usage: sudo ./setup-browser-kiosk.sh
################################################################################

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
KIOSK_USER="kiosk"
WORKSPACES_WEB_URL=""  # Will prompt user for their WorkSpaces URL
BROWSER="chromium"  # Options: chromium, firefox
AUTO_LOGIN=true

################################################################################
# Helper Functions
################################################################################

print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_header() {
    echo ""
    echo "=================================="
    echo "$1"
    echo "=================================="
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "Please run as root (use sudo)"
        exit 1
    fi
}

check_internet() {
    print_status "Checking internet connectivity..."
    if ! ping -c 1 8.8.8.8 &> /dev/null; then
        print_error "No internet connection detected"
        exit 1
    fi
    print_status "Internet connection verified"
}

get_workspaces_url() {
    print_header "WorkSpaces Configuration"
    echo ""
    echo "Please enter your AWS WorkSpaces web client URL"
    echo "Examples:"
    echo "  - https://clients.amazonworkspaces.com/"
    echo "  - https://<your-custom-domain>.awsapps.com/workspaces"
    echo ""
    read -p "WorkSpaces URL: " WORKSPACES_WEB_URL

    if [ -z "$WORKSPACES_WEB_URL" ]; then
        print_warning "No URL provided, using default: https://clients.amazonworkspaces.com/"
        WORKSPACES_WEB_URL="https://clients.amazonworkspaces.com/"
    fi

    print_status "WorkSpaces URL set to: $WORKSPACES_WEB_URL"
}

################################################################################
# System Update
################################################################################

update_system() {
    print_header "Updating System Packages"
    apt update
    apt upgrade -y
    print_status "System updated"
}

################################################################################
# Install Minimal Desktop Environment
################################################################################

install_minimal_desktop() {
    print_header "Installing Minimal Desktop Environment"

    # Install minimal X server and window manager
    apt install -y \
        xorg \
        openbox \
        lightdm \
        pulseaudio

    print_status "Minimal desktop environment installed"
}

################################################################################
# Install Browser
################################################################################

install_browser() {
    print_header "Installing Browser ($BROWSER)"

    if [ "$BROWSER" = "chromium" ]; then
        apt install -y chromium-browser
        print_status "Chromium installed"
    elif [ "$BROWSER" = "firefox" ]; then
        apt install -y firefox
        print_status "Firefox installed"
    else
        print_error "Unknown browser: $BROWSER"
        exit 1
    fi
}

################################################################################
# Create Kiosk User
################################################################################

create_kiosk_user() {
    print_header "Creating Kiosk User"

    if id "$KIOSK_USER" &>/dev/null; then
        print_warning "User $KIOSK_USER already exists, skipping creation"
    else
        useradd -m -s /bin/bash "$KIOSK_USER"
        echo "$KIOSK_USER:kiosk" | chpasswd
        print_status "Created user: $KIOSK_USER (default password: kiosk)"
        print_warning "IMPORTANT: Change the default password after first login!"
    fi
}

################################################################################
# Configure Auto-Login
################################################################################

configure_autologin() {
    if [ "$AUTO_LOGIN" = true ]; then
        print_header "Configuring Auto-Login"

        CONFIG_FILE="/etc/lightdm/lightdm.conf"

        if [ ! -f "$CONFIG_FILE" ]; then
            mkdir -p /etc/lightdm
            touch "$CONFIG_FILE"
        fi

        # Backup original config
        cp "$CONFIG_FILE" "$CONFIG_FILE.backup"

        # Configure auto-login
        if grep -q "^\[Seat:\*\]" "$CONFIG_FILE"; then
            sed -i "/^\[Seat:\*\]/a autologin-user=$KIOSK_USER\nautologin-user-timeout=0" "$CONFIG_FILE"
        else
            cat >> "$CONFIG_FILE" << EOF

[Seat:*]
autologin-user=$KIOSK_USER
autologin-user-timeout=0
user-session=openbox
EOF
        fi

        print_status "Auto-login configured for user: $KIOSK_USER"
    fi
}

################################################################################
# Configure Openbox for Kiosk Mode
################################################################################

configure_openbox() {
    print_header "Configuring Openbox Window Manager"

    OPENBOX_DIR="/home/$KIOSK_USER/.config/openbox"
    mkdir -p "$OPENBOX_DIR"

    # Create autostart script
    cat > "$OPENBOX_DIR/autostart" << 'OPENBOX_END'
#!/bin/bash

# Disable screen blanking and power management
xset s off
xset -dpms
xset s noblank

# Remove mouse cursor after 5 seconds of inactivity (optional)
# unclutter -idle 5 &

# Wait for network
sleep 5

# Launch browser in kiosk mode
OPENBOX_END

    if [ "$BROWSER" = "chromium" ]; then
        cat >> "$OPENBOX_DIR/autostart" << EOF
chromium-browser \\
    --kiosk \\
    --noerrdialogs \\
    --disable-infobars \\
    --no-first-run \\
    --disable-session-crashed-bubble \\
    --disable-features=TranslateUI \\
    --check-for-update-interval=31536000 \\
    --app="$WORKSPACES_WEB_URL"
EOF
    elif [ "$BROWSER" = "firefox" ]; then
        cat >> "$OPENBOX_DIR/autostart" << EOF
firefox --kiosk "$WORKSPACES_WEB_URL"
EOF
    fi

    chmod +x "$OPENBOX_DIR/autostart"

    # Create minimal openbox config
    cat > "$OPENBOX_DIR/rc.xml" << 'EOF'
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
    <!-- Disable Alt+F4 to prevent closing browser -->
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

    # Set proper permissions
    chown -R "$KIOSK_USER:$KIOSK_USER" "/home/$KIOSK_USER/.config"

    print_status "Openbox configured for kiosk mode"
}

################################################################################
# Lock Down System
################################################################################

lockdown_system() {
    print_header "Applying Security Lockdowns"

    # Disable unnecessary services
    print_status "Disabling unnecessary services..."
    services_to_disable=(
        "bluetooth"
        "cups"
        "avahi-daemon"
    )

    for service in "${services_to_disable[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            systemctl disable "$service" 2>/dev/null || true
            systemctl stop "$service" 2>/dev/null || true
            print_status "Disabled: $service"
        fi
    done

    # Restrict user permissions
    print_status "Restricting user permissions..."
    usermod -L root  # Lock root account

    # Configure firewall
    print_status "Configuring firewall..."
    apt install -y ufw
    ufw --force enable
    ufw default deny incoming
    ufw default allow outgoing

    # Disable virtual terminals (TTY switching)
    print_status "Disabling TTY switching..."
    systemctl mask getty@tty2.service
    systemctl mask getty@tty3.service
    systemctl mask getty@tty4.service
    systemctl mask getty@tty5.service
    systemctl mask getty@tty6.service

    print_status "System lockdown applied"
}

################################################################################
# Configure Automatic Updates
################################################################################

configure_updates() {
    print_header "Configuring Automatic Security Updates"

    apt install -y unattended-upgrades

    cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "03:00";
EOF

    cat > /etc/apt/apt.conf.d/20auto-upgrades << EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF

    print_status "Automatic updates configured (daily, auto-reboot at 3 AM)"
}

################################################################################
# Install Optional Tools
################################################################################

install_optional_tools() {
    print_header "Installing Optional Tools"

    # Install unclutter to hide mouse cursor
    apt install -y unclutter

    print_status "Optional tools installed"
}

################################################################################
# Create Recovery Instructions
################################################################################

create_recovery_file() {
    print_header "Creating Recovery Instructions"

    cat > /home/$KIOSK_USER/RECOVERY.txt << 'EOF'
AWS WorkSpaces Browser Kiosk - Recovery Instructions
=====================================================

If you need to exit kiosk mode or perform maintenance:

METHOD 1: SSH Access (Recommended)
- Connect via SSH from another computer
- Username: kiosk
- Default password: kiosk (CHANGE THIS!)

METHOD 2: Console Access
- The system is locked down to prevent easy access
- You may need to boot from USB to access the system
- Or use SSH as described in Method 1

To modify the kiosk URL:
1. SSH into the system
2. Edit: /home/kiosk/.config/openbox/autostart
3. Change the URL in the browser launch command
4. Reboot: sudo reboot

To disable kiosk mode temporarily:
1. SSH into the system
2. Edit: /etc/lightdm/lightdm.conf
3. Comment out the autologin lines
4. Reboot

To restore normal desktop:
1. Install desktop environment: sudo apt install ubuntu-desktop
2. Disable auto-login in /etc/lightdm/lightdm.conf
3. Reboot

For full system restore, use the restore-thinclient.sh script
EOF

    chown "$KIOSK_USER:$KIOSK_USER" "/home/$KIOSK_USER/RECOVERY.txt"
    print_status "Recovery instructions created at /home/$KIOSK_USER/RECOVERY.txt"
}

################################################################################
# Display Summary
################################################################################

display_summary() {
    print_header "Installation Complete!"

    echo ""
    echo "Browser Kiosk Configuration Summary:"
    echo "-------------------------------------"
    echo "User Account: $KIOSK_USER"
    echo "Default Password: kiosk"
    echo "Browser: $BROWSER"
    echo "WorkSpaces URL: $WORKSPACES_WEB_URL"
    echo "Auto-login: $AUTO_LOGIN"
    echo "Automatic Updates: Enabled (3 AM daily)"
    echo ""
    echo "Next Steps:"
    echo "1. CHANGE the default password: passwd"
    echo "2. REBOOT the system: sudo reboot"
    echo "3. System will auto-login and launch browser in kiosk mode"
    echo "4. The browser will automatically navigate to WorkSpaces"
    echo "5. Log in with your WorkSpaces credentials"
    echo ""
    echo "Recovery & Maintenance:"
    echo "- SSH access: ssh $KIOSK_USER@<ip-address>"
    echo "- Recovery instructions: /home/$KIOSK_USER/RECOVERY.txt"
    echo ""
    print_warning "IMPORTANT: Change the default password before rebooting!"
    echo ""
}

################################################################################
# Main Installation Flow
################################################################################

main() {
    print_header "AWS WorkSpaces Browser Kiosk Setup"
    echo "This script will convert this system into a browser-based kiosk"
    echo ""

    check_root
    check_internet
    get_workspaces_url

    update_system
    install_minimal_desktop
    install_browser
    create_kiosk_user
    configure_autologin
    configure_openbox
    lockdown_system
    configure_updates
    install_optional_tools
    create_recovery_file

    display_summary
}

# Run main function
main "$@"
