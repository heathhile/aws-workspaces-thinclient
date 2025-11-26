#!/bin/bash

################################################################################
# AWS WorkSpaces Thin Client Setup Script
#
# This script converts a standard Linux installation into a locked-down
# thin client for AWS WorkSpaces (DCV/WSP protocol)
#
# Tested on: Ubuntu 24.04 LTS, Ubuntu 22.04 LTS
# Hardware: AWOW AK34 Pro and similar x86_64 systems
#
# Usage: sudo ./setup-workspaces-thinclient.sh
################################################################################

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
THINCLIENT_USER="workspaces"
WORKSPACES_URL="https://d2td7dqidlhjx7.cloudfront.net/prod/iad/linux/x86_64/WorkSpaces_ubuntu_latest_x86_64.deb"
AUTO_LOGIN=true
LOCK_DOWN_SYSTEM=true

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
# Install Dependencies
################################################################################

install_dependencies() {
    print_header "Installing Dependencies"

    # Install required packages
    apt install -y \
        wget \
        curl \
        ca-certificates \
        gnupg \
        software-properties-common \
        libusb-1.0-0 \
        libudev1 \
        libxcb-xinerama0

    print_status "Dependencies installed"
}

################################################################################
# Create Thin Client User
################################################################################

create_user() {
    print_header "Creating Thin Client User"

    if id "$THINCLIENT_USER" &>/dev/null; then
        print_warning "User $THINCLIENT_USER already exists, skipping creation"
    else
        useradd -m -s /bin/bash "$THINCLIENT_USER"
        echo "$THINCLIENT_USER:workspaces" | chpasswd
        print_status "Created user: $THINCLIENT_USER (default password: workspaces)"
        print_warning "IMPORTANT: Change the default password after first login!"
    fi
}

################################################################################
# Install AWS WorkSpaces Client
################################################################################

install_workspaces_client() {
    print_header "Installing AWS WorkSpaces Client"

    cd /tmp

    # Download WorkSpaces client
    print_status "Downloading WorkSpaces client..."
    wget -O workspaces.deb "$WORKSPACES_URL"

    # Install the client
    print_status "Installing WorkSpaces client..."
    apt install -y ./workspaces.deb

    # Clean up
    rm workspaces.deb

    print_status "WorkSpaces client installed"
}

################################################################################
# Configure Auto-Login
################################################################################

configure_autologin() {
    if [ "$AUTO_LOGIN" = true ]; then
        print_header "Configuring Auto-Login"

        # Detect display manager
        if systemctl is-active --quiet gdm3; then
            DISPLAY_MANAGER="gdm3"
            CONFIG_FILE="/etc/gdm3/custom.conf"
        elif systemctl is-active --quiet gdm; then
            DISPLAY_MANAGER="gdm"
            CONFIG_FILE="/etc/gdm/custom.conf"
        elif systemctl is-active --quiet lightdm; then
            DISPLAY_MANAGER="lightdm"
            CONFIG_FILE="/etc/lightdm/lightdm.conf"
        else
            print_warning "Could not detect display manager, skipping auto-login"
            return
        fi

        print_status "Detected display manager: $DISPLAY_MANAGER"

        # Configure based on display manager
        if [ "$DISPLAY_MANAGER" = "gdm3" ] || [ "$DISPLAY_MANAGER" = "gdm" ]; then
            # Configure GDM
            if [ ! -f "$CONFIG_FILE" ]; then
                touch "$CONFIG_FILE"
            fi

            # Add or update AutomaticLogin settings
            if grep -q "^\[daemon\]" "$CONFIG_FILE"; then
                sed -i "/^\[daemon\]/a AutomaticLoginEnable=true\nAutomaticLogin=$THINCLIENT_USER" "$CONFIG_FILE"
            else
                echo "[daemon]" >> "$CONFIG_FILE"
                echo "AutomaticLoginEnable=true" >> "$CONFIG_FILE"
                echo "AutomaticLogin=$THINCLIENT_USER" >> "$CONFIG_FILE"
            fi
        elif [ "$DISPLAY_MANAGER" = "lightdm" ]; then
            # Configure LightDM
            if [ ! -f "$CONFIG_FILE" ]; then
                touch "$CONFIG_FILE"
            fi

            if grep -q "^\[Seat:\*\]" "$CONFIG_FILE"; then
                sed -i "/^\[Seat:\*\]/a autologin-user=$THINCLIENT_USER" "$CONFIG_FILE"
            else
                echo "[Seat:*]" >> "$CONFIG_FILE"
                echo "autologin-user=$THINCLIENT_USER" >> "$CONFIG_FILE"
            fi
        fi

        print_status "Auto-login configured for user: $THINCLIENT_USER"
    fi
}

################################################################################
# Configure Auto-Start WorkSpaces
################################################################################

configure_autostart() {
    print_header "Configuring WorkSpaces Auto-Start"

    # Create autostart directory
    AUTOSTART_DIR="/home/$THINCLIENT_USER/.config/autostart"
    mkdir -p "$AUTOSTART_DIR"

    # Create autostart desktop entry
    cat > "$AUTOSTART_DIR/workspaces.desktop" << EOF
[Desktop Entry]
Type=Application
Exec=/opt/workspacesclient/workspacesclient
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
Name=AWS WorkSpaces
Comment=Launch AWS WorkSpaces on startup
EOF

    # Set proper permissions
    chown -R "$THINCLIENT_USER:$THINCLIENT_USER" "/home/$THINCLIENT_USER/.config"

    print_status "WorkSpaces will auto-start on login"
}

################################################################################
# Lock Down System
################################################################################

lockdown_system() {
    if [ "$LOCK_DOWN_SYSTEM" = true ]; then
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

        # Remove user from sudo group if present
        if groups "$THINCLIENT_USER" | grep -q sudo; then
            deluser "$THINCLIENT_USER" sudo 2>/dev/null || true
        fi

        # Configure firewall (allow outbound only)
        print_status "Configuring firewall..."
        apt install -y ufw
        ufw --force enable
        ufw default deny incoming
        ufw default allow outgoing

        print_status "System lockdown applied"
    fi
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
# Create Quick Access Desktop Icon
################################################################################

create_desktop_icon() {
    print_header "Creating Desktop Shortcut"

    DESKTOP_DIR="/home/$THINCLIENT_USER/Desktop"
    mkdir -p "$DESKTOP_DIR"

    cat > "$DESKTOP_DIR/WorkSpaces.desktop" << EOF
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

    chmod +x "$DESKTOP_DIR/WorkSpaces.desktop"
    chown -R "$THINCLIENT_USER:$THINCLIENT_USER" "$DESKTOP_DIR"

    print_status "Desktop shortcut created"
}

################################################################################
# Display Summary
################################################################################

display_summary() {
    print_header "Installation Complete!"

    echo ""
    echo "Thin Client Configuration Summary:"
    echo "-----------------------------------"
    echo "User Account: $THINCLIENT_USER"
    echo "Default Password: workspaces"
    echo "Auto-login: $AUTO_LOGIN"
    echo "Auto-start WorkSpaces: Enabled"
    echo "Automatic Updates: Enabled (3 AM daily)"
    echo "Security Lockdown: $LOCK_DOWN_SYSTEM"
    echo ""
    echo "Next Steps:"
    echo "1. REBOOT the system: sudo reboot"
    echo "2. System will auto-login as '$THINCLIENT_USER'"
    echo "3. WorkSpaces client will launch automatically"
    echo "4. CHANGE THE DEFAULT PASSWORD after first login"
    echo "5. Enter your WorkSpaces registration code or server URL"
    echo ""
    print_warning "IMPORTANT: Change the default password immediately!"
    echo ""
}

################################################################################
# Main Installation Flow
################################################################################

main() {
    print_header "AWS WorkSpaces Thin Client Setup"
    echo "This script will convert this system into a WorkSpaces thin client"
    echo ""

    check_root
    check_internet

    update_system
    install_dependencies
    create_user
    install_workspaces_client
    configure_autologin
    configure_autostart
    lockdown_system
    configure_updates
    create_desktop_icon

    display_summary
}

# Run main function
main "$@"
