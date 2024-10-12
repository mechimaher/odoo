#!/bin/bash

# Odoo 16 Installation Script for Ubuntu 22.04 LTS
# This script automates the installation of Odoo 16 with improved error handling.
# ASCII Art Banner
echo '
 _____ ____    ___   ___   _____   _  __
|  _  |  _  \ /   | /   | |  _  \ | |/ /
| | | | | | |/ /| |/ /| | | | | | | ` /
| |_| | |_| / /_| / /_| | | |_| | | . \
|_____|____/_____|_____|_|_____/ |_|\_\
'
echo "Odoo 16 Installation Script for Ubuntu 22.04 LTS"
echo "Created by Maher Mechi"
echo "======================================================"

# Exit immediately if a command exits with a non-zero status
set -e

# Function to log messages
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Update and upgrade the system
log "Updating and upgrading the system..."
sudo apt update && sudo DEBIAN_FRONTEND=noninteractive apt upgrade -y

# Install dependencies
log "Installing dependencies..."
sudo apt install -y git wget nodejs npm python3 build-essential libzip-dev python3-dev libxslt1-dev python3-pip libldap2-dev python3-wheel libsasl2-dev python3-venv python3-setuptools node-less libjpeg-dev xfonts-75dpi xfonts-base libpq-dev libffi-dev fontconfig

# Install rtlcss
if ! command_exists rtlcss; then
    log "Installing rtlcss..."
    sudo npm install -g rtlcss
else
    log "rtlcss is already installed."
fi

# Install wkhtmltopdf
if ! command_exists wkhtmltopdf; then
    log "Installing wkhtmltopdf..."
    wget https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-2/wkhtmltox_0.12.6.1-2.jammy_amd64.deb
    sudo dpkg -i wkhtmltox_0.12.6.1-2.jammy_amd64.deb
    rm wkhtmltox_0.12.6.1-2.jammy_amd64.deb
else
    log "wkhtmltopdf is already installed."
fi

# Create Odoo user
if ! id "odoo" &>/dev/null; then
    log "Creating Odoo user..."
    sudo adduser --system --group --home=/opt/odoo --shell=/bin/bash odoo
else
    log "Odoo user already exists."
fi

# Install and configure PostgreSQL
if ! command_exists psql; then
    log "Installing PostgreSQL..."
    sudo apt install postgresql -y
else
    log "PostgreSQL is already installed."
fi

log "Ensuring PostgreSQL is started..."
sudo systemctl start postgresql

log "Configuring PostgreSQL..."
if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='odoo'" | grep -q 1; then
    sudo -u postgres createuser -s odoo
else
    log "PostgreSQL user 'odoo' already exists."
fi

# Install Odoo 16
if [ ! -d "/opt/odoo/odoo-server" ]; then
    log "Installing Odoo 16..."
    sudo git clone https://github.com/odoo/odoo.git --depth 1 --branch 16.0 --single-branch /opt/odoo/odoo-server
    sudo chown -R odoo:odoo /opt/odoo/odoo-server
else
    log "Odoo 16 is already installed. Updating..."
    sudo -H -u odoo git -C /opt/odoo/odoo-server pull
fi

# Set up Python virtual environment and install requirements
log "Setting up Python virtual environment and installing requirements..."
if [ ! -d "/opt/odoo/odoo-server/venv" ]; then
    sudo -H -u odoo bash -c "python3 -m venv /opt/odoo/odoo-server/venv"
fi
sudo -H -u odoo bash -c "/opt/odoo/odoo-server/venv/bin/pip3 install --upgrade pip wheel"
sudo -H -u odoo bash -c "/opt/odoo/odoo-server/venv/bin/pip3 install -r /opt/odoo/odoo-server/requirements.txt"

# Configure Odoo
log "Configuring Odoo..."
sudo mkdir -p /var/log/odoo
sudo chown odoo:odoo /var/log/odoo
sudo chmod 777 /var/log/odoo

# Generate a random password for the Odoo admin if not already set
if [ ! -f "/etc/odoo-server.conf" ]; then
    ODOO_ADMIN_PASSWD=$(openssl rand -base64 12)
    
    # Create Odoo configuration file
    sudo tee /etc/odoo-server.conf > /dev/null <<EOF
[options]
admin_passwd = $ODOO_ADMIN_PASSWD
db_host = False
db_port = False
db_user = odoo
db_password = False
addons_path = /opt/odoo/odoo-server/addons
logfile = /var/log/odoo/odoo-server.log
log_level = info
EOF

    sudo chown odoo:odoo /etc/odoo-server.conf
else
    log "Odoo configuration file already exists."
    ODOO_ADMIN_PASSWD=$(sudo grep admin_passwd /etc/odoo-server.conf | awk '{print $3}')
fi

# Create Odoo systemd service file
if [ ! -f "/etc/systemd/system/odoo.service" ]; then
    log "Creating Odoo systemd service..."
    sudo tee /etc/systemd/system/odoo.service > /dev/null <<EOF
[Unit]
Description=Odoo 16.0 Service
Requires=postgresql.service
After=network.target postgresql.service

[Service]
Type=simple
SyslogIdentifier=odoo
PermissionsStartOnly=true
User=odoo
Group=odoo
ExecStart=/opt/odoo/odoo-server/venv/bin/python3 /opt/odoo/odoo-server/odoo-bin -c /etc/odoo-server.conf
StandardOutput=journal+console

[Install]
WantedBy=multi-user.target
EOF
else
    log "Odoo systemd service file already exists."
fi

# Start Odoo service
log "Reloading systemd and starting Odoo service..."
sudo systemctl daemon-reload
sudo systemctl enable --now odoo.service

# Get the server's IP address
SERVER_IP=$(hostname -I | awk '{print $1}')

# Installation complete
log "Odoo 16 installation complete!"
log "You can access Odoo at: http://$SERVER_IP:8069"
log "Admin password: $ODOO_ADMIN_PASSWD"
log "Please change the admin password after your first login."
