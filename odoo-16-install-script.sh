#!/bin/bash

# Odoo 16 Installation Script for Ubuntu 22.04 LTS
# This script automates the installation of Odoo 16 without user interaction.

# Exit immediately if a command exits with a non-zero status
set -e

# Function to log messages
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Update and upgrade the system
log "Updating and upgrading the system..."
sudo apt update && sudo DEBIAN_FRONTEND=noninteractive apt upgrade -y

# Install dependencies
log "Installing dependencies..."
sudo apt install -y git wget nodejs npm python3 build-essential libzip-dev python3-dev libxslt1-dev python3-pip libldap2-dev python3-wheel libsasl2-dev python3-venv python3-setuptools node-less libjpeg-dev xfonts-75dpi xfonts-base libpq-dev libffi-dev fontconfig

# Install rtlcss
log "Installing rtlcss..."
sudo npm install -g rtlcss

# Install wkhtmltopdf
log "Installing wkhtmltopdf..."
wget https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-2/wkhtmltox_0.12.6.1-2.jammy_amd64.deb
sudo dpkg -i wkhtmltox_0.12.6.1-2.jammy_amd64.deb
rm wkhtmltox_0.12.6.1-2.jammy_amd64.deb

# Create Odoo user
log "Creating Odoo user..."
sudo adduser --system --group --home=/opt/odoo --shell=/bin/bash odoo

# Install and configure PostgreSQL
log "Installing and configuring PostgreSQL..."
sudo apt install postgresql -y
sudo systemctl start postgresql
sudo su - postgres -c "createuser -s odoo"

# Install Odoo 16
log "Installing Odoo 16..."
sudo git clone https://github.com/odoo/odoo.git --depth 1 --branch 16.0 --single-branch /opt/odoo/odoo-server
sudo chown -R odoo:odoo /opt/odoo/odoo-server

# Set up Python virtual environment and install requirements
log "Setting up Python virtual environment and installing requirements..."
sudo -H -u odoo bash -c "python3 -m venv /opt/odoo/odoo-server/venv"
sudo -H -u odoo bash -c "/opt/odoo/odoo-server/venv/bin/pip3 install wheel"
sudo -H -u odoo bash -c "/opt/odoo/odoo-server/venv/bin/pip3 install -r /opt/odoo/odoo-server/requirements.txt"

# Configure Odoo
log "Configuring Odoo..."
sudo mkdir -p /var/log/odoo
sudo chown odoo:odoo /var/log/odoo
sudo chmod 777 /var/log/odoo

# Generate a random password for the Odoo admin
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

# Create Odoo systemd service file
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

# Start Odoo service
log "Starting Odoo service..."
sudo systemctl daemon-reload
sudo systemctl enable --now odoo.service

# Get the server's IP address
SERVER_IP=$(hostname -I | awk '{print $1}')

# Installation complete
log "Odoo 16 installation complete!"
log "You can access Odoo at: http://$SERVER_IP:8069"
log "Admin password: $ODOO_ADMIN_PASSWD"
log "Please change the admin password after your first login."
