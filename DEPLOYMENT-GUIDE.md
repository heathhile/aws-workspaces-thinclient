# AWS WorkSpaces Thin Client Deployment Guide
## Certificate-Based VPN with Pre-Login Authentication for GovCloud

**Version:** 1.0
**Last Updated:** November 26, 2025
**Target:** Multi-tenant GovCloud deployments with AWS Managed AD

---

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Prerequisites](#prerequisites)
4. [Per-Customer Setup](#per-customer-setup)
5. [Certificate Generation](#certificate-generation)
6. [AWS Configuration](#aws-configuration)
7. [Thin Client Provisioning](#thin-client-provisioning)
8. [Testing & Validation](#testing--validation)
9. [CMMC Compliance](#cmmc-compliance)
10. [Troubleshooting](#troubleshooting)
11. [Scaling to Multiple Customers](#scaling-to-multiple-customers)

---

## Overview

This guide documents the complete process for deploying thin clients that connect to customer-specific AWS GovCloud environments using certificate-based VPN authentication, enabling pre-login VPN connectivity for AWS Managed AD authentication.

### Key Benefits

- **Zero user interaction for VPN** - Connects automatically at boot
- **CMMC compliant** - Certificate-based device authentication + user MFA
- **Customer isolation** - Each customer has dedicated GovCloud account
- **Reduced scope** - Customer's local network stays out of CMMC assessment
- **Scalable** - One certificate per customer, reusable across 1-2 devices

---

## Architecture

### Network Flow

```
┌─────────────────────────────────────────────────────────────┐
│ Customer Site (OUT OF CMMC SCOPE)                           │
│                                                              │
│  ┌──────────────────┐                                       │
│  │  Thin Client     │                                       │
│  │  ─────────────   │                                       │
│  │  Ubuntu 24.04    │                                       │
│  │  WorkSpaces      │                                       │
│  │  Client          │                                       │
│  └────────┬─────────┘                                       │
│           │                                                  │
│           │ 1. Boot                                         │
│           │ 2. Network init                                 │
│           │ 3. OpenVPN auto-start (cert auth)              │
│           │                                                  │
└───────────┼──────────────────────────────────────────────────┘
            │
            │ VPN Tunnel (Certificate Auth)
            │ ─ No username/password
            │ ─ No MFA prompts
            │ ─ Automatic at boot
            │
            ▼
┌─────────────────────────────────────────────────────────────┐
│ Customer's GovCloud Account (IN CMMC SCOPE)                 │
│                                                              │
│  ┌────────────────────────────────────────────┐            │
│  │ AWS Client VPN Endpoint                    │            │
│  │ ─ Certificate-based mutual authentication  │            │
│  │ ─ Customer-specific CA                     │            │
│  └────────────────┬───────────────────────────┘            │
│                   │                                          │
│                   ▼                                          │
│  ┌────────────────────────────────────────────┐            │
│  │ VPC (172.31.0.0/16)                        │            │
│  │                                             │            │
│  │  ┌─────────────────────────────────┐       │            │
│  │  │ AWS Managed AD                  │       │            │
│  │  │ ─ Domain: customer.domain      │       │            │
│  │  │ ─ DNS: 172.31.x.x, 172.31.y.y │       │            │
│  │  └─────────────────────────────────┘       │            │
│  │                                             │            │
│  │  ┌─────────────────────────────────┐       │            │
│  │  │ AWS WorkSpaces                  │       │            │
│  │  │ ─ 1-2 WorkSpaces per customer  │       │            │
│  │  │ ─ Windows Server 2022          │       │            │
│  │  │ ─ DCV/WSP protocol             │       │            │
│  │  │ ─ Encrypted volumes            │       │            │
│  │  └─────────────────────────────────┘       │            │
│  └────────────────────────────────────────────┘            │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

### Authentication Layers

1. **Device Authentication (VPN)**: X.509 certificate (pre-login, automatic)
2. **User Authentication (AD/WorkSpaces)**: Username + Password + MFA

This provides **defense-in-depth** with both device and user authentication.

---

## Prerequisites

### Tools Required

**On your management workstation:**
- AWS CLI configured with GovCloud access
- `easy-rsa` for certificate generation
- `scp`/`ssh` for device provisioning
- Text editor for .ovpn files

**Installation:**
```bash
# macOS
brew install easy-rsa awscli

# Ubuntu/Debian
sudo apt install easy-rsa awscli
```

### AWS Access

- Administrator access to customer's GovCloud account
- Ability to create/modify:
  - Client VPN endpoints
  - ACM certificates
  - VPC resources
  - WorkSpaces
  - AWS Managed AD

### Hardware

- x86_64 device (tested: AWOW AK34 Pro)
- Minimum 2GB RAM, 16GB storage
- Network connectivity (wired recommended)

---

## Per-Customer Setup

### Customer Onboarding Checklist

For each new customer, you'll need:

- [ ] Customer name/identifier (e.g., `acme-corp`)
- [ ] GovCloud account created in your AWS Organization
- [ ] VPC deployed with subnets
- [ ] AWS Managed AD deployed
- [ ] Client VPN endpoint created
- [ ] WorkSpaces provisioned (1-2 per customer)
- [ ] Certificates generated
- [ ] Thin client(s) provisioned

---

## Certificate Generation

### Setup Certificate Infrastructure

Create a dedicated directory for each customer:

```bash
# Create customer directory
mkdir ~/customer-certs/acme-corp
cd ~/customer-certs/acme-corp

# Initialize easy-rsa PKI
easyrsa init-pki

# Build Certificate Authority
easyrsa build-ca nopass
# Common Name: acme-corp-ca

# Generate server certificate (for AWS Client VPN)
easyrsa build-server-full server nopass

# Generate client certificate (for thin clients)
easyrsa build-client-full acme-corp-device nopass
```

**Files created:**
- `pki/ca.crt` - CA certificate (upload to AWS ACM)
- `pki/issued/server.crt` - Server certificate
- `pki/private/server.key` - Server private key
- `pki/issued/acme-corp-device.crt` - Client certificate
- `pki/private/acme-corp-device.key` - Client private key

### Certificate Naming Convention

```
Customer: Acme Corp
├─ CA Name: acme-corp-ca
├─ Server Cert: server (reusable across customers)
└─ Client Cert: acme-corp-device (used by all Acme devices)
```

---

## AWS Configuration

### 1. Upload Certificates to ACM

```bash
# Set your AWS profile and region
export AWS_PROFILE=your-customer-profile
export AWS_REGION=us-gov-west-1

# Upload CA certificate
aws acm import-certificate \
  --certificate fileb://pki/ca.crt \
  --private-key fileb://pki/private/ca.key \
  --tags Key=Name,Value=acme-corp-ca \
  --region $AWS_REGION

# Note the CertificateArn from output
```

### 2. Create Client VPN Endpoint

```bash
# Get VPC details
VPC_ID=$(aws ec2 describe-vpcs --query 'Vpcs[0].VpcId' --output text)
SUBNET_ID=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query 'Subnets[0].SubnetId' --output text)
SECURITY_GROUP=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" --query 'SecurityGroups[0].GroupId' --output text)
SERVER_CERT_ARN="arn:aws-us-gov:acm:REGION:ACCOUNT:certificate/SERVER-CERT-ID"
CA_CERT_ARN="arn:aws-us-gov:acm:REGION:ACCOUNT:certificate/CA-CERT-ID"

# Create Client VPN endpoint
aws ec2 create-client-vpn-endpoint \
  --client-cidr-block "100.64.0.0/22" \
  --server-certificate-arn "$SERVER_CERT_ARN" \
  --authentication-options '[{"Type":"certificate-authentication","MutualAuthentication":{"ClientRootCertificateChainArn":"'$CA_CERT_ARN'"}}]' \
  --connection-log-options '{"Enabled":false}' \
  --description "Acme Corp Thin Client VPN" \
  --vpc-id "$VPC_ID" \
  --security-group-ids "$SECURITY_GROUP" \
  --split-tunnel \
  --region $AWS_REGION

# Note the ClientVpnEndpointId and DnsName from output
```

### 3. Associate VPN with Subnet

```bash
VPN_ENDPOINT_ID="cvpn-endpoint-xxxxx"

aws ec2 associate-client-vpn-target-network \
  --client-vpn-endpoint-id $VPN_ENDPOINT_ID \
  --subnet-id $SUBNET_ID \
  --region $AWS_REGION
```

### 4. Authorize VPN Access

```bash
VPC_CIDR=$(aws ec2 describe-vpcs --vpc-ids $VPC_ID --query 'Vpcs[0].CidrBlock' --output text)

aws ec2 authorize-client-vpn-ingress \
  --client-vpn-endpoint-id $VPN_ENDPOINT_ID \
  --target-network-cidr $VPC_CIDR \
  --authorize-all-groups \
  --region $AWS_REGION
```

### 5. Get AWS Managed AD DNS Servers

```bash
DIRECTORY_ID=$(aws ds describe-directories --query 'DirectoryDescriptions[0].DirectoryId' --output text)

aws ds describe-directories \
  --directory-ids $DIRECTORY_ID \
  --query 'DirectoryDescriptions[0].[Name,DnsIpAddrs]' \
  --output table

# Note the DNS IPs - you'll need these for thin client config
```

---

## Thin Client Provisioning

### 1. Base Thin Client Setup

Install Ubuntu 24.04 LTS on the device and run the base setup:

```bash
# On the thin client
wget https://raw.githubusercontent.com/YOUR-USERNAME/aws-workspaces-thinclient/main/setup-workspaces-thinclient.sh
chmod +x setup-workspaces-thinclient.sh
sudo ./setup-workspaces-thinclient.sh
```

This installs:
- AWS WorkSpaces client
- Auto-login configuration
- Security hardening
- Automatic updates

### 2. Build Customer .ovpn File

On your management workstation:

```bash
cd ~/customer-certs/acme-corp

# Download base VPN configuration from AWS
aws ec2 export-client-vpn-client-configuration \
  --client-vpn-endpoint-id $VPN_ENDPOINT_ID \
  --output text > base-config.ovpn

# Build complete .ovpn with embedded certificates
cat base-config.ovpn > acme-corp.ovpn
echo "" >> acme-corp.ovpn
echo "<ca>" >> acme-corp.ovpn
cat pki/ca.crt >> acme-corp.ovpn
echo "</ca>" >> acme-corp.ovpn
echo "<cert>" >> acme-corp.ovpn
cat pki/issued/acme-corp-device.crt >> acme-corp.ovpn
echo "</cert>" >> acme-corp.ovpn
echo "<key>" >> acme-corp.ovpn
cat pki/private/acme-corp-device.key >> acme-corp.ovpn
echo "</key>" >> acme-corp.ovpn

# Verify file was created
ls -lh acme-corp.ovpn
```

### 3. Deploy to Thin Client

```bash
# Copy .ovpn to thin client
scp acme-corp.ovpn admin@THIN-CLIENT-IP:~/

# SSH to thin client and configure OpenVPN
ssh admin@THIN-CLIENT-IP

# On thin client:
sudo cp ~/acme-corp.ovpn /etc/openvpn/client/thin-client.conf
sudo systemctl enable openvpn-client@thin-client.service
sudo systemctl start openvpn-client@thin-client.service

# Verify VPN connected
sudo systemctl status openvpn-client@thin-client.service
ip addr show tun0
ping 172.31.x.x  # Use your AD DNS IP
```

### 4. Configure DNS for AD

```bash
# On thin client, create DNS update script
sudo tee /etc/openvpn/client/update-dns.sh << 'EOF'
#!/bin/bash
# Update DNS to use AWS Managed AD servers
echo "nameserver 172.31.24.176" > /etc/resolv.conf  # Primary AD DNS
echo "nameserver 172.31.12.32" >> /etc/resolv.conf  # Secondary AD DNS
echo "search customer.domain" >> /etc/resolv.conf   # AD domain
EOF

sudo chmod +x /etc/openvpn/client/update-dns.sh
sudo /etc/openvpn/client/update-dns.sh

# Verify DNS resolution
nslookup customer.domain
```

### 5. Test Complete Flow

```bash
# Reboot to test pre-login VPN
sudo reboot

# After reboot, verify:
# 1. VPN auto-connected (check tun0 interface)
# 2. Can ping AD domain controllers
# 3. DNS resolves domain names
# 4. WorkSpaces client auto-launched
```

---

## Testing & Validation

### Pre-Login VPN Test

```bash
# After reboot, check VPN status
sudo systemctl status openvpn-client@thin-client.service

# Should show:
# - Active: active (running)
# - Status: "Initialization Sequence Completed"
```

### Network Connectivity Test

```bash
# Check VPN interface
ip addr show tun0
# Should show: 100.64.x.x/22

# Test AD connectivity
ping -c 3 172.31.x.x  # AD DNS IP

# Test DNS resolution
nslookup customer.domain
```

### WorkSpaces Connection Test

1. System auto-logs in as `workspaces` user
2. WorkSpaces client launches automatically
3. User enters registration code (first time only)
4. User logs in with AD credentials:
   - Username: `user@customer.domain` or `DOMAIN\user`
   - Password: `<password>`
   - MFA: `<code from authenticator>`

### Validation Checklist

- [ ] VPN connects automatically at boot (before login)
- [ ] No VPN authentication prompts
- [ ] tun0 interface has IP address
- [ ] Can ping AWS Managed AD domain controllers
- [ ] DNS resolves customer domain
- [ ] WorkSpaces client auto-launches
- [ ] User can authenticate with AD credentials + MFA
- [ ] WorkSpace loads successfully
- [ ] No CUI stored on thin client

---

## CMMC Compliance

### Scope Reduction

**Out of CMMC Scope:**
- Customer's local network equipment
- Customer's switches, routers, WiFi
- Customer's firewall (minimal security required)
- Customer's user PCs and laptops
- Customer's printers and peripherals

**In CMMC Scope:**
- AWS GovCloud account (your responsibility)
- AWS WorkSpaces (controlled, encrypted)
- Thin client device (locked-down, no CUI storage)

### Authentication Controls

**AC.L2-3.5.3 - Multi-Factor Authentication:**

✅ **Device Level (VPN):**
- Something you have: X.509 certificate on thin client
- Something it is: Device-specific private key
- Cryptographic proof of authorized device

✅ **User Level (WorkSpaces):**
- Something you know: Password
- Something you have: MFA token/app

**Result:** Two authentication layers with MFA at both device and user level.

### Encryption Controls

**SC.L2-3.13.11 - Encryption of CUI at Rest:**

✅ **WorkSpaces:** EBS volumes encrypted with AWS KMS
✅ **S3 Storage:** Server-side encryption enabled
✅ **VPN Tunnel:** AES-256-GCM cipher
✅ **Thin Client:** No CUI stored locally (stateless)

### Audit Controls

**AU.L2-3.3.1 - Audit Logging:**

✅ **VPN Connections:** CloudWatch logs (optional, can enable)
✅ **WorkSpaces Sessions:** Session recording available
✅ **AD Authentication:** Windows Event Logs in AD
✅ **Certificate Usage:** CloudTrail logs

### System Security Plan Notes

**Device Authentication Rationale:**

> "Thin clients use X.509 certificate-based authentication for AWS Client VPN access. Each customer receives a unique client certificate signed by our certificate authority. The certificate provides cryptographic proof of device identity and cannot be replicated or phished. The private key never leaves the device and is protected by filesystem permissions. This satisfies multi-factor authentication requirements at the device level (something you have + cryptographic proof). Users then authenticate to AWS Managed Active Directory with username, password, and MFA, providing user-level multi-factor authentication. This defense-in-depth approach provides both device and user authentication."

**No CUI on Thin Client:**

> "Thin clients are stateless endpoints that provide remote display only. No CUI is processed, stored, or cached on the thin client device. All CUI resides within AWS WorkSpaces EBS volumes which are encrypted at rest using AWS KMS with customer-managed keys. The thin client merely transmits encrypted display protocol (DCV/WSP) over an encrypted VPN tunnel. If the device is lost or stolen, no CUI is exposed."

---

## Troubleshooting

### VPN Won't Connect

**Check OpenVPN service:**
```bash
sudo systemctl status openvpn-client@thin-client.service
sudo journalctl -u openvpn-client@thin-client -n 50
```

**Common issues:**
- Incorrect certificate path in .ovpn file
- Certificate/key mismatch
- AWS Client VPN endpoint not associated with subnet
- Security group blocking UDP 443

**Resolution:**
```bash
# Verify certificate files
sudo cat /etc/openvpn/client/thin-client.conf | grep -A 5 "<ca>"

# Test VPN manually
sudo openvpn --config /etc/openvpn/client/thin-client.conf
```

### DNS Not Resolving

**Check DNS configuration:**
```bash
cat /etc/resolv.conf
```

**Should show:**
```
nameserver 172.31.x.x  # AD DNS
nameserver 172.31.y.y  # AD DNS
search customer.domain
```

**Resolution:**
```bash
# Manually set DNS
sudo /etc/openvpn/client/update-dns.sh

# Test resolution
nslookup customer.domain
```

### WorkSpaces Won't Launch

**Check WorkSpaces client:**
```bash
which workspacesclient
/usr/bin/workspacesclient --version
```

**Check autostart:**
```bash
cat ~/.config/autostart/workspaces.desktop
```

**Manual launch:**
```bash
/usr/bin/workspacesclient &
```

### Can't Reach AD Domain Controllers

**Verify VPN route:**
```bash
ip route | grep tun0
# Should show: 172.31.0.0/16 via 100.64.x.x dev tun0
```

**Test connectivity:**
```bash
ping 172.31.x.x  # AD DNS IP
telnet 172.31.x.x 389  # LDAP port
```

**Check security groups:**
```bash
aws ec2 describe-security-groups \
  --group-ids $SECURITY_GROUP_ID \
  --query 'SecurityGroups[0].IpPermissions'
```

---

## Scaling to Multiple Customers

### Customer Tracking

Maintain a spreadsheet or database:

| Customer | GovCloud Account | VPN Endpoint | Certificate | Device Serial | Status |
|----------|------------------|--------------|-------------|---------------|--------|
| Acme Corp | 123456789012 | cvpn-endpoint-abc | acme-corp-ca | AK34-00042 | Active |
| Globex Inc | 234567890123 | cvpn-endpoint-def | globex-inc-ca | AK34-00043 | Active |

### Certificate Management

```
~/customer-certs/
├── acme-corp/
│   ├── pki/
│   ├── acme-corp.ovpn
│   └── README.txt (customer notes)
├── globex-inc/
│   ├── pki/
│   ├── globex-inc.ovpn
│   └── README.txt
└── initech-llc/
    ├── pki/
    ├── initech-llc.ovpn
    └── README.txt
```

### Automation Scripts

Create helper scripts:

**onboard-customer.sh:**
```bash
#!/bin/bash
CUSTOMER=$1

mkdir -p ~/customer-certs/$CUSTOMER
cd ~/customer-certs/$CUSTOMER
easyrsa init-pki
easyrsa build-ca nopass  # CN: ${CUSTOMER}-ca
easyrsa build-server-full server nopass
easyrsa build-client-full ${CUSTOMER}-device nopass

echo "Customer $CUSTOMER certificates created"
echo "Upload pki/ca.crt to AWS ACM"
```

**provision-device.sh:**
```bash
#!/bin/bash
CUSTOMER=$1
DEVICE_IP=$2

scp ~/customer-certs/$CUSTOMER/${CUSTOMER}.ovpn admin@$DEVICE_IP:~/
ssh admin@$DEVICE_IP "sudo cp ~/${CUSTOMER}.ovpn /etc/openvpn/client/thin-client.conf"
ssh admin@$DEVICE_IP "sudo systemctl restart openvpn-client@thin-client.service"

echo "Device provisioned for $CUSTOMER"
```

### Golden Image Workflow

1. **Build base image** (once)
   - Ubuntu 24.04 LTS installed
   - WorkSpaces client installed
   - OpenVPN installed
   - Security hardening applied
   - Auto-login configured

2. **Clone for customer** (per device)
   - Clone base image to device
   - Copy customer-specific .ovpn
   - Configure customer DNS servers
   - Test and ship

### Cost per Customer

**Monthly costs (example):**
- Client VPN endpoint: ~$75/month
- WorkSpaces (2 users, PERFORMANCE, ALWAYS_ON): ~$200/month
- AWS Managed AD (Standard): ~$110/month
- Data transfer: ~$10/month
- **Total: ~$395/month per customer**

**One-time costs:**
- Thin client hardware: $150-200/device
- Provisioning labor: 1-2 hours

---

## Appendix

### Required Network Ports

**Thin Client → AWS:**
- UDP 443: Client VPN (OpenVPN)
- TCP 443: WorkSpaces DCV/WSP
- TCP 4172: DCV (optional)
- UDP 4172: DCV (optional)

**Within VPC:**
- UDP 88: Kerberos (AD authentication)
- TCP 135: RPC (AD)
- TCP 389: LDAP (AD)
- TCP 445: SMB (AD)
- TCP 636: LDAPS (AD)
- TCP 3268: Global Catalog (AD)
- TCP 3389: RDP (WorkSpaces backend)

### File Locations

**On Thin Client:**
- OpenVPN config: `/etc/openvpn/client/thin-client.conf`
- OpenVPN service: `openvpn-client@thin-client.service`
- WorkSpaces client: `/usr/bin/workspacesclient`
- Autostart config: `~/.config/autostart/workspaces.desktop`
- DNS update script: `/etc/openvpn/client/update-dns.sh`

**On Management Workstation:**
- Customer certificates: `~/customer-certs/{customer}/`
- Easy-RSA PKI: `~/customer-certs/{customer}/pki/`
- Customer .ovpn files: `~/customer-certs/{customer}/{customer}.ovpn`

### AWS Resources per Customer

**VPC Resources:**
- 1x VPC
- 2x Subnets (multi-AZ)
- 1x Internet Gateway
- 2x Route Tables
- 1-2x Security Groups

**Directory Services:**
- 1x AWS Managed AD (Standard or Enterprise)
- 2x Domain Controllers (AWS managed)

**Client VPN:**
- 1x Client VPN Endpoint
- 1x Target Network Association
- 1x Authorization Rule

**WorkSpaces:**
- 1-2x WorkSpaces per customer
- 1x WorkSpaces Directory Registration

**ACM:**
- 1x CA Certificate
- 1x Server Certificate (can be shared)

---

## Support & Maintenance

### Regular Maintenance Tasks

**Monthly:**
- Review VPN connection logs
- Check WorkSpaces health
- Verify certificate expiration dates
- Update thin client OS packages

**Quarterly:**
- Review security group rules
- Audit user access
- Test disaster recovery procedures
- Update documentation

**Annually:**
- Renew certificates (if needed)
- Review CMMC controls
- Update thin client base image
- Security assessment

### Certificate Renewal

Certificates are valid for 825 days (default easy-rsa). Plan renewal:

```bash
# Check certificate expiration
openssl x509 -in pki/issued/customer-device.crt -noout -dates

# Generate new certificate before expiration
easyrsa build-client-full customer-device-2026 nopass

# Update .ovpn file with new certificate
# Deploy to thin clients during maintenance window
```

### Emergency Procedures

**Certificate Compromised:**
1. Revoke certificate in AWS Client VPN
2. Generate new certificate
3. Update all affected thin clients
4. Monitor for unauthorized access

**Thin Client Lost/Stolen:**
1. No CUI at risk (stateless device)
2. Revoke device certificate (if unique per device)
3. Provision replacement device
4. Update device tracking database

---

**End of Deployment Guide**

For questions or support, refer to the main repository README or contact your deployment team.
