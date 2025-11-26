#!/bin/bash

################################################################################
# AWS WorkSpaces Thin Client Restore Script
#
# This script restores a thin client back to a normal Ubuntu desktop system
# by reversing the changes made by the setup scripts
#
# Usage: sudo ./restore-thinclient.sh
################################################################################

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

print_info() {
    echo -e "${BLUE}[i]${NC} $1"
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

confirm_action() {
    local message="$1"
    echo ""
    print_warning "$message"
    read -p "Are you sure you want to continue? (yes/no): " response
    if [ "$response" != "yes" ]; then
        print_info "Restore cancelled by user"
        exit 0
    fi
}

################################################################################
# Detect Configuration
################################################################################

detect_setup_type() {
    print_header "Detecting Thin Client Configuration"

    SETUP_TYPE="unknown"

    # Check for workspaces user (native client)
    if id "workspaces" &>/dev/null; then
        SETUP_TYPE="native"
        THIN_USER="workspaces"
        print_status "Detected: Native WorkSpaces Client setup"
    fi

    # Check for kiosk user (browser kiosk)
    if id "kiosk" &>/dev/null; then
        if [ "$SETUP_TYPE" = "native" ]; then
            SETUP_TYPE="both"
            print_status "Detected: Both Native and Kiosk setups present"
        else
            SETUP_TYPE="kiosk"
            THIN_USER="kiosk"
            print_status "Detected: Browser Kiosk setup"
        fi
    fi

    if [ "$SETUP_TYPE" = "unknown" ]; then
        print_warning "No thin client configuration detected"
        echo "This script is designed to restore systems configured by:"
        echo "  - setup-workspaces-thinclient.sh"
        echo "  - setup-browser-kiosk.sh"
        exit 1
    fi
}

################################################################################
# Disable Auto-Login
################################################################################

disable_autologin() {
    print_header "Disabling Auto-Login"

    # Handle GDM3
    if [ -f /etc/gdm3/custom.conf ]; then
        print_status "Backing up GDM3 configuration..."
        cp /etc/gdm3/custom.conf /etc/gdm3/custom.conf.backup

        # Remove auto-login settings
        sed -i '/AutomaticLoginEnable/d' /etc/gdm3/custom.conf
        sed -i '/AutomaticLogin=/d' /etc/gdm3/custom.conf

        print_status "GDM3 auto-login disabled"
    fi

    # Handle LightDM
    if [ -f /etc/lightdm/lightdm.conf ]; then
        print_status "Backing up LightDM configuration..."
        cp /etc/lightdm/lightdm.conf /etc/lightdm/lightdm.conf.backup

        # Remove auto-login settings
        sed -i '/autologin-user=/d' /etc/lightdm/lightdm.conf
        sed -i '/autologin-user-timeout=/d' /etc/lightdm/lightdm.conf

        print_status "LightDM auto-login disabled"
    fi
}

################################################################################
# Remove Auto-Start Configuration
################################################################################

remove_autostart() {
    print_header "Removing Auto-Start Configuration"

    # Remove for workspaces user
    if [ -d /home/workspaces/.config/autostart ]; then
        rm -f /home/workspaces/.config/autostart/workspaces.desktop
        print_status "Removed WorkSpaces auto-start for workspaces user"
    fi

    # Remove for kiosk user (Openbox autostart)
    if [ -f /home/kiosk/.config/openbox/autostart ]; then
        mv /home/kiosk/.config/openbox/autostart /home/kiosk/.config/openbox/autostart.disabled
        print_status "Disabled Openbox auto-start for kiosk user"
    fi
}

################################################################################
# Restore User Permissions
################################################################################

restore_permissions() {
    print_header "Restoring User Permissions"

    # Re-enable sudo for thin client users
    if id "workspaces" &>/dev/null; then
        usermod -aG sudo workspaces
        print_status "Restored sudo access for workspaces user"
    fi

    if id "kiosk" &>/dev/null; then
        usermod -aG sudo kiosk
        print_status "Restored sudo access for kiosk user"
    fi

    # Unlock root account (optional - user decides)
    print_info "Root account is currently locked for security"
    read -p "Do you want to unlock the root account? (yes/no): " unlock_root
    if [ "$unlock_root" = "yes" ]; then
        passwd -u root
        print_status "Root account unlocked"
    else
        print_info "Root account remains locked"
    fi
}

################################################################################
# Re-enable Services
################################################################################

reenable_services() {
    print_header "Re-enabling System Services"

    services_to_enable=(
        "bluetooth"
        "cups"
        "avahi-daemon"
    )

    for service in "${services_to_enable[@]}"; do
        if systemctl list-unit-files | grep -q "^${service}.service"; then
            systemctl enable "$service" 2>/dev/null || true
            systemctl start "$service" 2>/dev/null || true
            print_status "Re-enabled: $service"
        fi
    done

    # Re-enable TTY switching
    if systemctl is-masked getty@tty2.service &>/dev/null; then
        systemctl unmask getty@tty2.service
        systemctl unmask getty@tty3.service
        systemctl unmask getty@tty4.service
        systemctl unmask getty@tty5.service
        systemctl unmask getty@tty6.service
        print_status "Re-enabled virtual terminal switching"
    fi
}

################################################################################
# Firewall Configuration
################################################################################

configure_firewall() {
    print_header "Configuring Firewall for Desktop Use"

    print_info "Current firewall status:"
    ufw status

    read -p "Do you want to disable the firewall? (yes/no): " disable_fw
    if [ "$disable_fw" = "yes" ]; then
        ufw disable
        print_status "Firewall disabled"
    else
        print_info "Firewall remains enabled with current rules"
        print_info "You may want to adjust rules for desktop use"
    fi
}

################################################################################
# Install Full Desktop Environment
################################################################################

install_full_desktop() {
    print_header "Installing Full Desktop Environment"

    echo ""
    echo "The current system may have a minimal desktop installation."
    echo "Would you like to install a full desktop environment?"
    echo ""
    echo "Options:"
    echo "  1) Install Ubuntu Desktop (full GNOME desktop)"
    echo "  2) Install Ubuntu Desktop Minimal (lighter GNOME)"
    echo "  3) Install XFCE Desktop (lightweight)"
    echo "  4) Skip (keep current desktop)"
    echo ""
    read -p "Enter your choice (1-4): " desktop_choice

    case $desktop_choice in
        1)
            print_status "Installing Ubuntu Desktop (this may take a while)..."
            apt update
            apt install -y ubuntu-desktop
            print_status "Ubuntu Desktop installed"
            ;;
        2)
            print_status "Installing Ubuntu Desktop Minimal..."
            apt update
            apt install -y ubuntu-desktop-minimal
            print_status "Ubuntu Desktop Minimal installed"
            ;;
        3)
            print_status "Installing XFCE Desktop..."
            apt update
            apt install -y xubuntu-desktop
            print_status "XFCE Desktop installed"
            ;;
        4)
            print_info "Skipping desktop installation"
            ;;
        *)
            print_warning "Invalid choice, skipping desktop installation"
            ;;
    esac
}

################################################################################
# Remove WorkSpaces Client
################################################################################

remove_workspaces_client() {
    if dpkg -l | grep -q workspacesclient; then
        print_header "Removing WorkSpaces Client"

        read -p "Do you want to remove the WorkSpaces client? (yes/no): " remove_ws
        if [ "$remove_ws" = "yes" ]; then
            apt remove -y workspacesclient
            apt autoremove -y
            print_status "WorkSpaces client removed"
        else
            print_info "WorkSpaces client kept installed"
        fi
    fi
}

################################################################################
# Clean Up Configuration Files
################################################################################

cleanup_configs() {
    print_header "Cleaning Up Configuration Files"

    # Remove desktop shortcuts
    if [ -f /home/workspaces/Desktop/WorkSpaces.desktop ]; then
        rm -f /home/workspaces/Desktop/WorkSpaces.desktop
        print_status "Removed WorkSpaces desktop shortcut"
    fi

    # Remove recovery files
    if [ -f /home/kiosk/RECOVERY.txt ]; then
        rm -f /home/kiosk/RECOVERY.txt
        print_status "Removed recovery instructions"
    fi

    print_status "Configuration cleanup complete"
}

################################################################################
# Optional: Remove Thin Client Users
################################################################################

remove_users() {
    print_header "Thin Client User Accounts"

    echo ""
    echo "The following thin client user accounts exist:"
    [ -d /home/workspaces ] && echo "  - workspaces"
    [ -d /home/kiosk ] && echo "  - kiosk"
    echo ""
    print_warning "Removing users will DELETE their home directories and all data!"
    read -p "Do you want to remove thin client user accounts? (yes/no): " remove_users

    if [ "$remove_users" = "yes" ]; then
        if id "workspaces" &>/dev/null; then
            userdel -r workspaces 2>/dev/null || true
            print_status "Removed workspaces user and home directory"
        fi

        if id "kiosk" &>/dev/null; then
            userdel -r kiosk 2>/dev/null || true
            print_status "Removed kiosk user and home directory"
        fi
    else
        print_info "Thin client users retained (sudo access restored)"
    fi
}

################################################################################
# Disable Automatic Updates (Optional)
################################################################################

configure_updates() {
    print_header "Automatic Updates Configuration"

    if [ -f /etc/apt/apt.conf.d/50unattended-upgrades ]; then
        print_info "Automatic updates are currently enabled with auto-reboot at 3 AM"
        read -p "Do you want to disable automatic reboots? (yes/no): " disable_reboot

        if [ "$disable_reboot" = "yes" ]; then
            sed -i 's/Unattended-Upgrade::Automatic-Reboot "true"/Unattended-Upgrade::Automatic-Reboot "false"/' \
                /etc/apt/apt.conf.d/50unattended-upgrades
            print_status "Automatic reboots disabled (updates still install)"
        fi
    fi
}

################################################################################
# Create Restore Summary
################################################################################

create_summary() {
    print_header "Restore Summary"

    SUMMARY_FILE="/root/thinclient-restore-summary.txt"

    cat > "$SUMMARY_FILE" << EOF
AWS WorkSpaces Thin Client Restore Summary
==========================================
Date: $(date)
Detected Setup: $SETUP_TYPE

Actions Taken:
--------------
- Auto-login disabled
- Auto-start configuration removed
- User sudo permissions restored
- System services re-enabled
- TTY switching re-enabled
- Desktop environment installed/updated

User Accounts:
--------------
EOF

    if id "workspaces" &>/dev/null; then
        echo "- workspaces: Retained (sudo access restored)" >> "$SUMMARY_FILE"
    else
        echo "- workspaces: Removed" >> "$SUMMARY_FILE"
    fi

    if id "kiosk" &>/dev/null; then
        echo "- kiosk: Retained (sudo access restored)" >> "$SUMMARY_FILE"
    else
        echo "- kiosk: Removed" >> "$SUMMARY_FILE"
    fi

    cat >> "$SUMMARY_FILE" << EOF

Configuration Backups:
----------------------
- GDM3: /etc/gdm3/custom.conf.backup
- LightDM: /etc/lightdm/lightdm.conf.backup
- Kiosk Autostart: /home/kiosk/.config/openbox/autostart.disabled

Next Steps:
-----------
1. Reboot the system: sudo reboot
2. Log in manually (auto-login disabled)
3. Configure desktop environment as needed
4. Review and adjust firewall rules if necessary
5. Set user passwords if needed

Notes:
------
- WorkSpaces client may still be installed (if not removed)
- Automatic security updates are still enabled
- Firewall configuration retained (review as needed)

This summary is saved at: $SUMMARY_FILE
EOF

    print_status "Summary saved to: $SUMMARY_FILE"
}

################################################################################
# Display Final Instructions
################################################################################

display_final_instructions() {
    print_header "Restore Complete!"

    echo ""
    echo "Your system has been restored to a normal desktop configuration."
    echo ""
    echo "Changes Made:"
    echo "-------------"
    echo "✓ Auto-login disabled"
    echo "✓ Auto-start removed"
    echo "✓ User permissions restored"
    echo "✓ System services re-enabled"
    echo ""
    echo "Next Steps:"
    echo "-----------"
    echo "1. REBOOT the system now: sudo reboot"
    echo "2. You will see the login screen (no auto-login)"
    echo "3. Log in with your user account"
    echo "4. Configure your desktop as needed"
    echo ""

    if id "workspaces" &>/dev/null || id "kiosk" &>/dev/null; then
        echo "User Accounts:"
        echo "--------------"
        [ -d /home/workspaces ] && echo "- workspaces user: Retained with sudo access"
        [ -d /home/kiosk ] && echo "- kiosk user: Retained with sudo access"
        echo ""
        echo "You can log in with these accounts or your original admin account."
        echo ""
    fi

    print_info "A detailed summary has been saved to: /root/thinclient-restore-summary.txt"
    echo ""

    read -p "Press Enter to continue..."
}

################################################################################
# Main Restore Flow
################################################################################

main() {
    print_header "AWS WorkSpaces Thin Client Restore Tool"
    echo "This script will restore your thin client to a normal desktop system"
    echo ""

    check_root

    confirm_action "This will reverse the thin client configuration and restore normal desktop functionality."

    detect_setup_type
    disable_autologin
    remove_autostart
    restore_permissions
    reenable_services
    configure_firewall
    install_full_desktop
    remove_workspaces_client
    cleanup_configs
    configure_updates
    remove_users
    create_summary
    display_final_instructions
}

# Run main function
main "$@"
