#!/bin/bash

################################################################################
# OpenVPN Pre-Login Configuration for AWS WorkSpaces Thin Client
#
# This script configures OpenVPN to connect automatically at boot time
# (before user login) to enable AWS Managed AD authentication
#
# Prerequisites:
# - Run setup-workspaces-thinclient.sh first
# - Have your OpenVPN .ovpn configuration file ready
# - VPN credentials (username/password or certificates)
#
# Usage: sudo ./setup-openvpn-prelogin.sh
################################################################################

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
OVPN_CONFIG_DIR="/etc/openvpn"
OVPN_AUTH_FILE="/etc/openvpn/auth.txt"
OVPN_SERVICE_NAME="openvpn-client@thin-client"

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

check_internet() {
    print_status "Checking internet connectivity..."
    if ! ping -c 1 8.8.8.8 &> /dev/null; then
        print_error "No internet connection detected"
        exit 1
    fi
    print_status "Internet connection verified"
}

################################################################################
# Install OpenVPN
################################################################################

install_openvpn() {
    print_header "Installing OpenVPN"

    apt update
    apt install -y openvpn openvpn-systemd-resolved resolvconf

    print_status "OpenVPN installed"
}

################################################################################
# Configure OpenVPN Client
################################################################################

configure_openvpn() {
    print_header "Configuring OpenVPN Client"

    echo ""
    echo "Please provide your OpenVPN configuration:"
    echo ""
    echo "Option 1: Provide path to existing .ovpn file"
    echo "Option 2: I'll create a template for you to edit"
    echo ""
    read -p "Do you have an .ovpn file ready? (yes/no): " has_ovpn

    if [ "$has_ovpn" = "yes" ]; then
        read -p "Enter full path to your .ovpn file: " ovpn_path

        if [ ! -f "$ovpn_path" ]; then
            print_error "File not found: $ovpn_path"
            exit 1
        fi

        # Copy to OpenVPN config directory
        cp "$ovpn_path" "$OVPN_CONFIG_DIR/thin-client.conf"
        print_status "OpenVPN configuration copied"
    else
        # Create template
        cat > "$OVPN_CONFIG_DIR/thin-client.conf" << 'EOF'
# OpenVPN Client Configuration Template
# Edit this file with your VPN server details

client
dev tun
proto udp
remote YOUR_VPN_SERVER_IP 1194
resolv-retry infinite
nobind
persist-key
persist-tun

# Certificates and Keys
# Option 1: Inline certificates (paste between <ca></ca> tags)
# Option 2: Reference external files
# ca /etc/openvpn/ca.crt
# cert /etc/openvpn/client.crt
# key /etc/openvpn/client.key

# Authentication
auth-user-pass /etc/openvpn/auth.txt

# Compression
comp-lzo

# Security
cipher AES-256-CBC
auth SHA256

# Logging
verb 3

# DNS Configuration (important for AWS Managed AD)
script-security 2
up /etc/openvpn/update-resolv-conf
down /etc/openvpn/update-resolv-conf
EOF

        print_warning "Template created at: $OVPN_CONFIG_DIR/thin-client.conf"
        print_info "You MUST edit this file with your VPN server details before proceeding"

        read -p "Press Enter to open the file in nano for editing..."
        nano "$OVPN_CONFIG_DIR/thin-client.conf"
    fi

    # Set proper permissions
    chmod 600 "$OVPN_CONFIG_DIR/thin-client.conf"
    print_status "OpenVPN configuration secured"
}

################################################################################
# Configure VPN Credentials
################################################################################

configure_credentials() {
    print_header "Configuring VPN Credentials"

    echo ""
    echo "Does your VPN require username/password authentication?"
    echo "(If using certificate-only auth, select 'no')"
    echo ""
    read -p "Require username/password? (yes/no): " need_auth

    if [ "$need_auth" = "yes" ]; then
        echo ""
        print_info "Enter VPN credentials (will be stored securely)"
        read -p "VPN Username: " vpn_user
        read -sp "VPN Password: " vpn_pass
        echo ""

        # Create auth file
        cat > "$OVPN_AUTH_FILE" << EOF
$vpn_user
$vpn_pass
EOF

        # Secure the auth file
        chmod 600 "$OVPN_AUTH_FILE"

        # Ensure auth file is referenced in config
        if ! grep -q "auth-user-pass" "$OVPN_CONFIG_DIR/thin-client.conf"; then
            echo "auth-user-pass $OVPN_AUTH_FILE" >> "$OVPN_CONFIG_DIR/thin-client.conf"
        else
            sed -i "s|auth-user-pass.*|auth-user-pass $OVPN_AUTH_FILE|" "$OVPN_CONFIG_DIR/thin-client.conf"
        fi

        print_status "VPN credentials configured securely"
    else
        print_info "Skipping credential configuration (using certificate-based auth)"
    fi
}

################################################################################
# Configure DNS for AWS Managed AD
################################################################################

configure_dns() {
    print_header "Configuring DNS for AWS Managed AD"

    echo ""
    echo "Enter your AWS Managed AD DNS server IPs"
    echo "These are typically the Domain Controller IPs from AWS Directory Service"
    echo "Example: 10.0.1.100"
    echo ""
    read -p "Primary DNS Server IP: " dns1
    read -p "Secondary DNS Server IP (or press Enter to skip): " dns2

    # Create DNS update script
    cat > /etc/openvpn/update-resolv-conf << 'EOF'
#!/bin/bash
# DNS update script for OpenVPN

case "$script_type" in
    up)
        # Backup original resolv.conf
        cp /etc/resolv.conf /etc/resolv.conf.backup

        # Set VPN DNS servers
        echo "# VPN DNS Configuration" > /etc/resolv.conf
EOF

    echo "        echo \"nameserver $dns1\" >> /etc/resolv.conf" >> /etc/openvpn/update-resolv-conf

    if [ -n "$dns2" ]; then
        echo "        echo \"nameserver $dns2\" >> /etc/resolv.conf" >> /etc/openvpn/update-resolv-conf
    fi

    cat >> /etc/openvpn/update-resolv-conf << 'EOF'
        echo "options timeout:1 attempts:2" >> /etc/resolv.conf
        ;;
    down)
        # Restore original resolv.conf
        if [ -f /etc/resolv.conf.backup ]; then
            mv /etc/resolv.conf.backup /etc/resolv.conf
        fi
        ;;
esac
EOF

    chmod +x /etc/openvpn/update-resolv-conf

    print_status "DNS configuration created"
    print_info "Primary DNS: $dns1"
    [ -n "$dns2" ] && print_info "Secondary DNS: $dns2"
}

################################################################################
# Enable OpenVPN Service
################################################################################

enable_openvpn_service() {
    print_header "Enabling OpenVPN Auto-Start"

    # Enable and start the OpenVPN service
    systemctl enable openvpn-client@thin-client.service

    print_status "OpenVPN configured to start at boot (before login)"
}

################################################################################
# Configure Firewall for VPN
################################################################################

configure_firewall_vpn() {
    print_header "Configuring Firewall for VPN"

    # Allow VPN connection
    ufw allow out 1194/udp comment 'OpenVPN'
    ufw allow out 443/tcp comment 'OpenVPN SSL'

    print_status "Firewall rules added for VPN"
}

################################################################################
# Test VPN Connection
################################################################################

test_vpn_connection() {
    print_header "Testing VPN Connection"

    echo ""
    print_info "Starting OpenVPN service for testing..."

    systemctl start openvpn-client@thin-client.service

    # Wait for connection
    echo "Waiting for VPN to connect (30 seconds)..."
    sleep 30

    # Check status
    if systemctl is-active --quiet openvpn-client@thin-client.service; then
        print_status "OpenVPN service is running"

        # Check for tun interface
        if ip link show tun0 &> /dev/null; then
            print_status "VPN tunnel interface (tun0) is up"

            # Show IP address
            VPN_IP=$(ip addr show tun0 | grep "inet " | awk '{print $2}')
            print_info "VPN IP Address: $VPN_IP"

            print_status "VPN connection successful!"
        else
            print_warning "VPN tunnel interface not found"
            print_info "Check logs: journalctl -u openvpn-client@thin-client -n 50"
        fi
    else
        print_error "OpenVPN service failed to start"
        print_info "Check logs: journalctl -u openvpn-client@thin-client -n 50"

        read -p "View logs now? (yes/no): " view_logs
        if [ "$view_logs" = "yes" ]; then
            journalctl -u openvpn-client@thin-client -n 50
        fi
    fi

    echo ""
    print_info "VPN will automatically connect at boot before user login"
}

################################################################################
# Create Systemd Service Override for Network Wait
################################################################################

configure_network_wait() {
    print_header "Configuring Network Wait"

    # Ensure VPN waits for network to be ready
    mkdir -p /etc/systemd/system/openvpn-client@thin-client.service.d

    cat > /etc/systemd/system/openvpn-client@thin-client.service.d/override.conf << EOF
[Unit]
After=network-online.target
Wants=network-online.target

[Service]
# Restart on failure
Restart=on-failure
RestartSec=10

# Wait for network
ExecStartPre=/bin/sleep 5
EOF

    systemctl daemon-reload

    print_status "Network wait configured"
}

################################################################################
# Create VPN Status Indicator Script
################################################################################

create_vpn_status_indicator() {
    print_header "Creating VPN Status Indicator"

    # Create a simple script to check VPN status
    cat > /usr/local/bin/check-vpn-status << 'EOF'
#!/bin/bash

if systemctl is-active --quiet openvpn-client@thin-client.service; then
    if ip link show tun0 &> /dev/null; then
        VPN_IP=$(ip addr show tun0 | grep "inet " | awk '{print $2}')
        echo "VPN: Connected ($VPN_IP)"
        exit 0
    else
        echo "VPN: Service running but no tunnel"
        exit 1
    fi
else
    echo "VPN: Disconnected"
    exit 1
fi
EOF

    chmod +x /usr/local/bin/check-vpn-status

    print_status "VPN status checker created at /usr/local/bin/check-vpn-status"
}

################################################################################
# Create Documentation
################################################################################

create_vpn_documentation() {
    print_header "Creating VPN Documentation"

    cat > /root/VPN-SETUP-NOTES.txt << EOF
AWS WorkSpaces Thin Client - OpenVPN Pre-Login Setup
=====================================================

Configuration Files:
--------------------
- OpenVPN Config: $OVPN_CONFIG_DIR/thin-client.conf
- Credentials: $OVPN_AUTH_FILE (if using password auth)
- DNS Script: /etc/openvpn/update-resolv-conf

Service Management:
-------------------
# Check VPN status
systemctl status openvpn-client@thin-client.service
check-vpn-status

# View VPN logs
journalctl -u openvpn-client@thin-client -f

# Restart VPN
systemctl restart openvpn-client@thin-client.service

# Stop VPN
systemctl stop openvpn-client@thin-client.service

# Disable auto-start
systemctl disable openvpn-client@thin-client.service

Troubleshooting:
----------------
# Check if tunnel is up
ip addr show tun0

# Test DNS resolution to AD
nslookup yourdomain.com

# Check routes
ip route

# Test connectivity to AD domain controller
ping YOUR_DC_IP

# View detailed logs
journalctl -u openvpn-client@thin-client --no-pager

AWS Managed AD Integration:
----------------------------
Once VPN is connected, the thin client can reach your AWS Managed AD
domain controllers for authentication. Users will be able to log in
with their AD credentials: DOMAIN\username

Network Flow:
-------------
1. System boots
2. Network initializes
3. OpenVPN connects automatically (before login screen)
4. DNS points to AWS Managed AD domain controllers
5. Login screen appears
6. Users authenticate against AWS Managed AD
7. WorkSpaces client launches with AD credentials

Security Notes:
---------------
- VPN credentials are stored securely in $OVPN_AUTH_FILE (600 permissions)
- Only root can read credential files
- OpenVPN service runs as root (required for network configuration)
- VPN connection is established before user login
- All WorkSpaces traffic goes through the VPN tunnel

Configuration was completed on: $(date)
EOF

    print_status "Documentation saved to /root/VPN-SETUP-NOTES.txt"
}

################################################################################
# Display Summary
################################################################################

display_summary() {
    print_header "OpenVPN Pre-Login Setup Complete!"

    echo ""
    echo "VPN Configuration Summary:"
    echo "-------------------------"
    echo "Config File: $OVPN_CONFIG_DIR/thin-client.conf"
    echo "Service: openvpn-client@thin-client.service"
    echo "Auto-Start: Enabled (boots before user login)"
    echo ""
    echo "How It Works:"
    echo "-------------"
    echo "1. System boots up"
    echo "2. OpenVPN connects automatically (before login)"
    echo "3. DNS points to AWS Managed AD"
    echo "4. Users log in with AD credentials (DOMAIN\\username)"
    echo "5. WorkSpaces launches with authenticated session"
    echo ""
    echo "Useful Commands:"
    echo "----------------"
    echo "Check VPN status:  check-vpn-status"
    echo "View VPN logs:     journalctl -u openvpn-client@thin-client -f"
    echo "Restart VPN:       systemctl restart openvpn-client@thin-client"
    echo ""
    echo "Next Steps:"
    echo "-----------"
    echo "1. Review VPN connection status above"
    echo "2. Test AD authentication after reboot"
    echo "3. Configure WorkSpaces for AD user login"
    echo "4. Read documentation: /root/VPN-SETUP-NOTES.txt"
    echo ""
    print_info "IMPORTANT: VPN must be connected for AD authentication to work"
    echo ""

    read -p "Press Enter to continue..."
}

################################################################################
# Main Installation Flow
################################################################################

main() {
    print_header "OpenVPN Pre-Login Setup for AWS WorkSpaces"
    echo "This script configures OpenVPN to connect before user login"
    echo "enabling AWS Managed AD authentication for thin client users"
    echo ""

    check_root
    check_internet

    install_openvpn
    configure_openvpn
    configure_credentials
    configure_dns
    configure_network_wait
    enable_openvpn_service
    configure_firewall_vpn
    create_vpn_status_indicator
    create_vpn_documentation
    test_vpn_connection
    display_summary
}

# Run main function
main "$@"
