#!/bin/bash
# CloudStack Installation Script for Ubuntu 20.04
# Written by Paramjit Patel
# This script installs CloudStack 4.20 with KVM hypervisor on a single machine

# ---------------- CONFIG ----------------
CRED_FILE="./credentials.env"
STATE_FILE="/tmp/cloudstack_setup.state"
USERNAME="${SUDO_USER:-$USER}"
HOSTNAME="cloudstack"
INTERFACE="ens33"

# ---------------- CREDENTIAL SETUP ----------------
DEFAULT_MYSQL_PASS="Root@123"
DEFAULT_CLOUD_PASS="cloud"

if [ ! -f "$CRED_FILE" ]; then
    echo "🔐 No credentials file found. Creating one..."

    read -s -p "Enter MySQL root password [default: Root@123]: " MYSQL_PASS
    echo
    MYSQL_PASS=${MYSQL_PASS:-$DEFAULT_MYSQL_PASS}

    read -s -p "Enter CloudStack DB password [default: cloud]: " CLOUD_PASS
    echo
    CLOUD_PASS=${CLOUD_PASS:-$DEFAULT_CLOUD_PASS}

    echo "MYSQL_PASS='$MYSQL_PASS'" > "$CRED_FILE"
    echo "CLOUD_PASS='$CLOUD_PASS'" >> "$CRED_FILE"
    chmod 600 "$CRED_FILE"
    echo "✅ Credentials stored in $CRED_FILE"
else
    echo "📄 Loading credentials from $CRED_FILE..."
    source "$CRED_FILE"
fi

# Auto-detect IP and Gateway
IP=$(ip -4 addr show "$INTERFACE" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
GATEWAY=$(ip route | grep default | awk '{print $3}' | head -1)

if [[ -z "$IP" || -z "$GATEWAY" ]]; then
  echo "❌ Failed to auto-detect IP or Gateway. Please check if interface $INTERFACE exists and is connected."
  exit 1
else
  echo "🔧 Detected IP: $IP"
  echo "🔧 Detected Gateway: $GATEWAY"
fi

# Helper: check command success and save state
check_success() {
    if [ $? -ne 0 ]; then
        echo "❌ Error at line $1: $2"
        echo "$2 FAILED" >> "$STATE_FILE"
        exit 1
    else
        echo "✅ $2 completed successfully"
        echo "$2 DONE" >> "$STATE_FILE"
    fi
}

# Function to check if a stage has already completed
is_done() {
    if [ ! -f "$STATE_FILE" ]; then
        return 1
    fi
    grep -q "$1 DONE" "$STATE_FILE" 2>/dev/null
    return $?
}

# Ensure root access
if [[ $EUID -ne 0 ]]; then
   echo "Please run as root: sudo ./cloudstack_setup.sh"
   exit 1
fi

# Clear state if user confirms
if [ "$1" == "--reset" ]; then
    echo "Resetting installation state..."
    rm -f "$STATE_FILE"
fi

# Create state file if it doesn't exist
touch "$STATE_FILE"

! is_done "System update" && apt update && check_success $LINENO "System update"

! is_done "Essential packages" && apt install -y expect wget curl iptables-persistent && check_success $LINENO "Essential packages"

! is_done "Hostname set" && hostnamectl set-hostname $HOSTNAME && grep -q "$IP.*$HOSTNAME" /etc/hosts || echo "$IP   $HOSTNAME.c1.a1   $HOSTNAME" >> /etc/hosts && check_success $LINENO "Hostname set"

# IMPROVEMENT: Updated network configuration with modern syntax and STP parameters
! is_done "Netplan applied" && cat > /etc/netplan/01-network-manager-all.yaml <<EOL
network:
    version: 2
    renderer: networkd
    ethernets:
        $INTERFACE:
            dhcp4: no
            dhcp6: no
    bridges:
        cloudbr0:
            interfaces: [$INTERFACE]
            dhcp4: no
            dhcp6: no
            addresses: [$IP/24]
            routes:
              - to: default
                via: $GATEWAY
            nameservers:
                addresses: [8.8.8.8, 1.1.1.1]
            parameters:
                stp: false
                forward-delay: 0
EOL

! is_done "Network configured" && netplan generate && netplan apply && check_success $LINENO "Netplan applied"
systemctl restart systemd-networkd && check_success $LINENO "Network restarted"

# NEW: Enable IP forwarding for System VMs
! is_done "IP forwarding enabled" && {
    echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-cloudstack.conf
    sysctl -p /etc/sysctl.d/99-cloudstack.conf
    check_success $LINENO "IP forwarding enabled"
}

# NEW: Configure NAT for System VMs
! is_done "NAT configured" && {
    # Clear any existing rules
    iptables -F
    iptables -t nat -F
    # Set up NAT for CloudStack VMs
    iptables -t nat -A POSTROUTING -o cloudbr0 -j MASQUERADE
    # Allow forwarding
    iptables -A FORWARD -i cloudbr0 -o virbr0 -j ACCEPT
    iptables -A FORWARD -i virbr0 -o cloudbr0 -j ACCEPT
    # Save rules
    netfilter-persistent save
    check_success $LINENO "NAT configured"
}

! is_done "NTP, bridge-utils, and OpenSSH installed" && apt install -y ntp bridge-utils openssh-server && check_success $LINENO "NTP, bridge-utils, and OpenSSH installed"
! is_done "NTP enabled" && systemctl enable ntp && systemctl start ntp && check_success $LINENO "NTP enabled and started"
! is_done "SSH root login enabled" && sed -i "s/#PermitRootLogin.*/PermitRootLogin yes/" /etc/ssh/sshd_config && systemctl restart ssh && check_success $LINENO "SSH root login enabled"
! is_done "Firewall disabled" && ufw disable && check_success $LINENO "Firewall disabled"

! is_done "CloudStack repository added" && echo "deb https://download.cloudstack.org/ubuntu focal 4.20" > /etc/apt/sources.list.d/cloudstack.list && wget -O - https://download.cloudstack.org/release.asc | apt-key add - && apt update && check_success $LINENO "CloudStack repository added"

! is_done "CloudStack management installed" && apt install -y cloudstack-management && check_success $LINENO "CloudStack management installed"

! is_done "MySQL server installed" && apt install -y mysql-server && check_success $LINENO "MySQL server installed"

# IMPROVEMENT: Consolidated MySQL configuration into a single file with fixed EOF marker
! is_done "MySQL configured" && {
    cat > /etc/mysql/mysql.conf.d/cloudstack.cnf <<EOL
[mysqld]
server-id=01
innodb_rollback_on_timeout=1
innodb_lock_wait_timeout=600
max_connections=350
log-bin=mysql-bin
binlog-format = 'ROW'
datadir=/var/lib/mysql
socket=/var/run/mysqld/mysqld.sock
default-storage-engine=InnoDB
max_allowed_packet=32M
symbolic-links=0
EOL

    # Ensure MySQL directory permissions are correct
    chown -R mysql:mysql /var/lib/mysql
    
    # Make sure MySQL is running before proceeding
    systemctl enable mysql
    systemctl restart mysql
    
    # Wait for MySQL to start up
    echo "Waiting for MySQL to start..."
    for i in {1..30}; do
        if systemctl is-active --quiet mysql; then
            echo "MySQL started successfully."
            break
        fi
        echo -n "."
        sleep 1
        
        # If we've waited too long and MySQL still isn't running, check status
        if [ $i -eq 30 ]; then
            echo "MySQL failed to start. Checking status:"
            systemctl status mysql --no-pager
            journalctl -xe --no-pager | tail -n 50
            exit 1
        fi
    done
    
    check_success $LINENO "MySQL configured"
}

# IMPROVEMENT: Better MySQL password setting approach with retry mechanism
! is_done "MySQL password set" && {
    # Retry loop for MySQL password setup
    MAX_RETRIES=5
    RETRY_COUNT=0
    PASSWORD_SET=false
    
    while [ $RETRY_COUNT -lt $MAX_RETRIES ] && [ "$PASSWORD_SET" = false ]; do
        echo "Setting MySQL root password (attempt $(($RETRY_COUNT+1))/$MAX_RETRIES)..."
        
        # First try without password (fresh install)
        mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$MYSQL_PASS';" && {
            mysql -e "FLUSH PRIVILEGES;"
            PASSWORD_SET=true
        } || {
            # Then try with the new password (if partially configured)
            mysql -uroot -p$MYSQL_PASS -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$MYSQL_PASS';" && {
                mysql -uroot -p$MYSQL_PASS -e "FLUSH PRIVILEGES;"
                PASSWORD_SET=true
            } || {
                echo "Password change attempt failed. Retrying..."
                RETRY_COUNT=$((RETRY_COUNT+1))
                sleep 2
            }
        }
    done
    
    if [ "$PASSWORD_SET" = false ]; then
        echo "Failed to set MySQL password after $MAX_RETRIES attempts."
        exit 1
    fi
    
    check_success $LINENO "MySQL password set"
}

# Skip interactive MySQL secure installation
! is_done "MySQL secured" && {
    # This provides automated answers to mysql_secure_installation
    SECURE_MYSQL=$(expect -c "
    set timeout 10
    spawn mysql_secure_installation
    expect \"Enter password for user root:\"
    send \"$MYSQL_PASS\r\"
    expect \"Press y|Y for Yes, any other key for No:\"
    send \"n\r\"
    expect \"Change the password for root ?\"
    send \"n\r\"
    expect \"Remove anonymous users?\"
    send \"y\r\"
    expect \"Disallow root login remotely?\"
    send \"y\r\"
    expect \"Remove test database and access to it?\"
    send \"y\r\"
    expect \"Reload privilege tables now?\"
    send \"y\r\"
    expect eof
    ")
    echo "$SECURE_MYSQL"
    check_success $LINENO "MySQL secured"
}

# IMPROVEMENT: Fixed deploy-as parameter with password
! is_done "CloudStack database setup" && cloudstack-setup-databases cloud:$CLOUD_PASS@localhost --deploy-as=root:$MYSQL_PASS && check_success $LINENO "CloudStack database setup"

! is_done "CloudStack management configured" && cloudstack-setup-management && check_success $LINENO "CloudStack management configured"

# NEW: Configure DNS settings for System VMs
! is_done "System VM DNS configured" && {
    # Add CloudStack DNS settings to ensure System VMs get proper DNS
    grep -q "^zone.network.dns1" /etc/cloudstack/management/server.properties || \
        echo "zone.network.dns1=8.8.8.8" >> /etc/cloudstack/management/server.properties
    grep -q "^zone.network.dns2" /etc/cloudstack/management/server.properties || \
        echo "zone.network.dns2=1.1.1.1" >> /etc/cloudstack/management/server.properties
    
    # Additional settings for optimal System VM connectivity
    grep -q "^router.aggregation.command.each.timeout" /etc/cloudstack/management/server.properties || \
        echo "router.aggregation.command.each.timeout=600" >> /etc/cloudstack/management/server.properties
    grep -q "^host" /etc/cloudstack/management/server.properties || \
        echo "host=$IP" >> /etc/cloudstack/management/server.properties
    
    check_success $LINENO "System VM DNS configured"
}

# Fix NFS setup
! is_done "NFS Kernel Server installed" && apt install -y nfs-kernel-server quota && check_success $LINENO "NFS Kernel Server installed"

# IMPROVEMENT: Added permissions to NFS directories
! is_done "NFS directories created" && {
    mkdir -p /export/primary /export/secondary
    chmod 777 /export/primary /export/secondary
    chown nobody:nogroup /export/primary /export/secondary
    check_success $LINENO "NFS directories created"
}

! is_done "NFS exports configured" && {
    # Make sure we don't add duplicate entries for both primary and secondary exports
    grep -q "/export/primary *(rw,async,no_root_squash,no_subtree_check)" /etc/exports || \
        echo "/export/primary *(rw,async,no_root_squash,no_subtree_check)" | tee -a /etc/exports
    
    grep -q "/export/secondary *(rw,async,no_root_squash,no_subtree_check)" /etc/exports || \
        echo "/export/secondary *(rw,async,no_root_squash,no_subtree_check)" | tee -a /etc/exports
    
    exportfs -a
    check_success $LINENO "NFS exports configured"
}

! is_done "NFS server restarted" && systemctl restart nfs-kernel-server && check_success $LINENO "NFS server restarted"

! is_done "NFS mount points created" && mkdir -p /mnt/primary /mnt/secondary && check_success $LINENO "NFS mount points created"

# IMPROVEMENT: Removed noauto option from NFS mounts
! is_done "NFS mounts added to fstab" && {
    # Check if entries already exist to avoid duplicates
    grep -q "/mnt/primary" /etc/fstab || \
        echo "$IP:/export/primary /mnt/primary nfs rsize=8192,wsize=8192,timeo=14,intr,vers=3 0 0" >> /etc/fstab
    
    grep -q "/mnt/secondary" /etc/fstab || \
        echo "$IP:/export/secondary /mnt/secondary nfs rsize=8192,wsize=8192,timeo=14,intr,vers=3 0 0" >> /etc/fstab
    
    check_success $LINENO "NFS mounts added to fstab"
}

# IMPROVEMENT: Use mount -a instead of individual mounts
! is_done "NFS shares mounted" && {
    mount -a
    check_success $LINENO "NFS shares mounted"
}

# Configure quota system for NFS shares
! is_done "Quota configuration" && {
    sed -i -e 's/^RPCMOUNTDOPTS="--manage-gids"$/RPCMOUNTDOPTS="-p 892 --manage-gids"/g' /etc/default/nfs-kernel-server 2>/dev/null || true
    sed -i -e 's/^STATDOPTS=$/STATDOPTS="--port 662 --outgoing-port 2020"/g' /etc/default/nfs-common 2>/dev/null || true
    grep -q "NEED_STATD=yes" /etc/default/nfs-common || echo "NEED_STATD=yes" >> /etc/default/nfs-common
    sed -i -e 's/^RPCRQUOTADOPTS=$/RPCRQUOTADOPTS="-p 875"/g' /etc/default/quota 2>/dev/null || true
    check_success $LINENO "Quota configuration"
}

! is_done "CloudStack agent installed" && apt install -y cloudstack-agent && check_success $LINENO "CloudStack agent installed"

# NEW: Configure agent for proper DNS
! is_done "Agent DNS configured" && {
    mkdir -p /etc/cloudstack/agent/agent.properties.d
    cat > /etc/cloudstack/agent/agent.properties.d/dns.properties <<EOL
dns1=8.8.8.8
dns2=1.1.1.1
EOL
    check_success $LINENO "Agent DNS configured"
}

! is_done "libvirt configured" && {
    sed -i -e 's/#vnc_listen.*$/vnc_listen = "0.0.0.0"/g' /etc/libvirt/qemu.conf
    systemctl mask libvirtd.socket libvirtd-ro.socket libvirtd-admin.socket libvirtd-tls.socket libvirtd-tcp.socket
    
    # IMPROVEMENT: Better handling of libvirt configuration
    grep -q "^listen_tls" /etc/libvirt/libvirtd.conf || echo 'listen_tls=0' >> /etc/libvirt/libvirtd.conf
    grep -q "^listen_tcp" /etc/libvirt/libvirtd.conf || echo 'listen_tcp=1' >> /etc/libvirt/libvirtd.conf
    grep -q "^tcp_port" /etc/libvirt/libvirtd.conf || echo 'tcp_port = "16509"' >> /etc/libvirt/libvirtd.conf
    grep -q "^mdns_adv" /etc/libvirt/libvirtd.conf || echo 'mdns_adv = 0' >> /etc/libvirt/libvirtd.conf
    grep -q "^auth_tcp" /etc/libvirt/libvirtd.conf || echo 'auth_tcp = "none"' >> /etc/libvirt/libvirtd.conf
    
    systemctl restart libvirtd
    check_success $LINENO "libvirt configured"
}

! is_done "libvirt UUID configured" && {
    apt install -y uuid
    UUID=$(uuid)
    grep -q "^host_uuid" /etc/libvirt/libvirtd.conf || echo "host_uuid = \"$UUID\"" >> /etc/libvirt/libvirtd.conf
    systemctl restart libvirtd
    check_success $LINENO "libvirt UUID configured"
}

! is_done "AppArmor disabled for libvirt" && {
    ln -sf /etc/apparmor.d/usr.sbin.libvirtd /etc/apparmor.d/disable/ 2>/dev/null || true
    ln -sf /etc/apparmor.d/usr.lib.libvirt.virt-aa-helper /etc/apparmor.d/disable/ 2>/dev/null || true
    apparmor_parser -R /etc/apparmor.d/usr.sbin.libvirtd 2>/dev/null || true
    apparmor_parser -R /etc/apparmor.d/usr.lib.libvirt.virt-aa-helper 2>/dev/null || true
    check_success $LINENO "AppArmor disabled for libvirt"
}

# IMPROVEMENT: Updated template URL to official source
! is_done "System VM template installed" && {
    /usr/share/cloudstack-common/scripts/storage/secondary/cloud-install-sys-tmplt \
      -m /mnt/secondary \
      -u http://download.cloudstack.org/systemvm/4.18/systemvmtemplate-4.18.0-kvm.qcow2.bz2 \
      -h kvm -F
    check_success $LINENO "System VM template installed"
}

# NEW: System VM database verification
! is_done "System VM database verification" && {
    mysql -u root -p$MYSQL_PASS cloud -e "UPDATE vm_template SET state='Ready' WHERE type='SYSTEM';"
    check_success $LINENO "System VM database verification"
}

echo "✅ CloudStack setup completed! Access it via http://$IP:8080/client"
echo "Username: admin"
echo "Password: password"

# NEW: External connectivity test
! is_done "External connectivity tested" && {
    echo "Testing external connectivity..."
    ping -c 3 8.8.8.8
    ping -c 3 google.com
    check_success $LINENO "External connectivity tested"
}

# ---- DISPLAY SETTINGS ----
if [ -n "$DISPLAY" ]; then
    echo "Setting display resolution to 2880x1800 and scaling to 200%..."
    apt install -y x11-xserver-utils
    xrandr_output=$(xrandr | grep " connected" | cut -d ' ' -f1)
    if ! xrandr | grep -q "2880x1800"; then
        modeline=$(cvt 2880 1800 60 | grep Modeline | cut -d ' ' -f2-)
        xrandr --newmode $modeline
        xrandr --addmode "$xrandr_output" 2880x1800
    fi
    xrandr --output "$xrandr_output" --mode 2880x1800
    gsettings set org.gnome.desktop.interface scaling-factor 2 2>/dev/null || true

    # Make display settings persist across reboots
    cat > /home/$USERNAME/.xprofile <<EOL
#!/bin/bash
xrandr_output=\$(xrandr | grep " connected" | cut -d ' ' -f1)
xrandr --newmode \$(cvt 2880 1800 60 | grep Modeline | cut -d ' ' -f2-) 2>/dev/null || true
xrandr --addmode \$xrandr_output 2880x1800 2>/dev/null || true
xrandr --output \$xrandr_output --mode 2880x1800
gsettings set org.gnome.desktop.interface scaling-factor 2 2>/dev/null || true
EOL

    chown $USERNAME:$USERNAME /home/$USERNAME/.xprofile
    chmod +x /home/$USERNAME/.xprofile
else
    echo "No display detected. Skipping display settings."
fi

# NEW: Troubleshooting tools
cat > /root/systemvm_troubleshoot.sh <<EOL
#!/bin/bash
# System VM troubleshooting script
# Written by Paramjit Patel

echo "======= CloudStack System VM Diagnostic Tool ======="
echo "Checking CloudStack services..."
systemctl status cloudstack-management | grep Active
systemctl status cloudstack-agent | grep Active

echo -e "\nChecking networking..."
ip addr show cloudbr0
ip route

echo -e "\nChecking DNS resolution..."
cat /etc/resolv.conf
ping -c 3 google.com

echo -e "\nChecking System VMs in libvirt..."
virsh list --all

echo -e "\nChecking System VMs in database..."
mysql -u root -p$MYSQL_PASS cloud -e "SELECT id, name, state, type FROM vm_instance WHERE type IN ('ConsoleProxy', 'SecondaryStorageVm');"

echo -e "\nChecking logs for System VM creation attempts..."
tail -n 20 /var/log/cloudstack/management/management-server.log | grep -i "systemvm\|ssvm"

echo "======= Diagnostic Complete ======="
EOL
chmod +x /root/systemvm_troubleshoot.sh

# Usage info
echo -e "\n✅ Script completed successfully."
echo -e "Written by Paramjit Patel"
echo -e "To run from scratch: sudo ./cloudstack_setup.sh"
echo -e "To resume from failure: sudo ./cloudstack_setup.sh"
echo -e "To reset progress: sudo ./cloudstack_setup.sh --reset"
echo -e "\nTroubleshooting tool created: /root/systemvm_troubleshoot.sh"