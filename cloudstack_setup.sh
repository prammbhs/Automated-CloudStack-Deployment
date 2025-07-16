#!/bin/bash
# CloudStack 4.20 Setup Script with KVM on Ubuntu 20.04
# Written by Paramjit Patel

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

# ---------------- NETWORK DETECTION ----------------
IP=$(ip -4 addr show "$INTERFACE" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
GATEWAY=$(ip route | grep default | awk '{print $3}' | head -1)

if [[ -z "$IP" || -z "$GATEWAY" ]]; then
    echo "❌ Failed to detect IP/Gateway."
    exit 1
fi

# ---------------- HELPERS ----------------
check_success() {
    if [ $? -ne 0 ]; then
        echo "❌ Error at line $1: $2"
        echo "$2 FAILED" >> "$STATE_FILE"
        exit 1
    else
        echo "✅ $2 completed"
        echo "$2 DONE" >> "$STATE_FILE"
    fi
}

is_done() {
    grep -q "$1 DONE" "$STATE_FILE" 2>/dev/null
    return $?
}

touch "$STATE_FILE"

# ---------------- START INSTALL ----------------
! is_done "System update" && apt update && check_success $LINENO "System update"
! is_done "Essentials" && apt install -y wget curl expect net-tools bridge-utils openssh-server && check_success $LINENO "Essentials"

# Hostname
! is_done "Hostname set" && {
    hostnamectl set-hostname $HOSTNAME
    grep -q "$IP.*$HOSTNAME" /etc/hosts || echo "$IP   $HOSTNAME" >> /etc/hosts
    check_success $LINENO "Hostname set"
}

# Add CloudStack repo
! is_done "Repo" && {
    echo "deb https://download.cloudstack.org/ubuntu focal 4.20" > /etc/apt/sources.list.d/cloudstack.list
    wget -O - https://download.cloudstack.org/release.asc | apt-key add -
    apt update
    check_success $LINENO "Repo"
}

# Install CloudStack management
! is_done "CloudStack mgmt" && apt install -y cloudstack-management && check_success $LINENO "CloudStack mgmt"

# Install MySQL
! is_done "MySQL" && apt install -y mysql-server && check_success $LINENO "MySQL"

# Configure MySQL
! is_done "MySQL config" && {
cat > /etc/mysql/mysql.conf.d/cloudstack.cnf <<EOF
[mysqld]
max_allowed_packet=32M
log-bin=mysql-bin
binlog-format=ROW
EOF

systemctl enable mysql
systemctl restart mysql
check_success $LINENO "MySQL config"
}

# Set MySQL root password
! is_done "MySQL root password" && {
mysql -uroot -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$MYSQL_PASS'; FLUSH PRIVILEGES;" || mysql -uroot -p$MYSQL_PASS -e "FLUSH PRIVILEGES;"
check_success $LINENO "MySQL root password"
}

# Secure MySQL
! is_done "MySQL secure" && {
expect <<EOF
spawn mysql_secure_installation
expect "Enter password for user root:"
send "$MYSQL_PASS\r"
expect "Press y|Y for Yes"
send "n\r"
expect "Change the password"
send "n\r"
expect "Remove anonymous users?"
send "y\r"
expect "Disallow root login remotely?"
send "y\r"
expect "Remove test database?"
send "y\r"
expect "Reload privilege tables now?"
send "y\r"
expect eof
EOF
check_success $LINENO "MySQL secure"
}

# Setup database
! is_done "DB setup" && cloudstack-setup-databases cloud:$CLOUD_PASS@localhost --deploy-as=root:$MYSQL_PASS && check_success $LINENO "DB setup"

# Setup management
! is_done "Mgmt setup" && cloudstack-setup-management && check_success $LINENO "Mgmt setup"

echo "✅ Setup complete! Access: http://$IP:8080/client"
echo "Username: admin"
echo "Password: password"
