#!/bin/bash

# ASCII Art Banner
echo '
 _____ ____    ___   ___   _____   _  __
|  _  |  _  \ /   | /   | |  _  \ | |/ /
| | | | | | |/ /| |/ /| | | | | | | ` /
| |_| | |_| / /_| / /_| | | |_| | | . \
|_____|____/_____|_____|_|_____/ |_|\_\
'
echo "Odoo 16 Uninstallation Script for Ubuntu 22.04 LTS"
echo "Created by Maher Mechi"
echo "======================================================"

# This script automates the complete removal of Odoo 16 and its dependencies.

# Exit immediately if a command exits with a non-zero status
set -e

# Function to log messages
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Function to prompt for confirmation
confirm() {
    read -p "$1 (y/n): " answer
    case ${answer:0:1} in
        y|Y ) return 0 ;;
        * ) return 1 ;;
    esac
}

# Check if script is run as root
if [[ $EUID -ne 0 ]]; then
   log "This script must be run as root" 
   exit 1
fi

log "Starting Odoo 16 uninstallation process..."

# Step 1: Stop the Odoo Service
log "Stopping Odoo service..."
if systemctl is-active --quiet odoo; then
    systemctl stop odoo
    systemctl disable odoo
    log "Odoo service stopped and disabled."
else
    log "Odoo service is not running."
fi

# Step 2: Remove Odoo Files
log "Removing Odoo files..."
if [ -d "/opt/odoo" ]; then
    rm -rf /opt/odoo
    log "Odoo directory removed."
else
    log "Odoo directory not found."
fi

# Remove Odoo configuration file
if [ -f "/etc/odoo-server.conf" ]; then
    rm /etc/odoo-server.conf
    log "Odoo configuration file removed."
fi

# Remove Odoo log directory
if [ -d "/var/log/odoo" ]; then
    rm -rf /var/log/odoo
    log "Odoo log directory removed."
fi

# Step 3: Remove the Odoo User
log "Removing Odoo user..."
if id "odoo" &>/dev/null; then
    userdel -r odoo
    log "Odoo user removed."
else
    log "Odoo user not found."
fi

# Step 4: Uninstall PostgreSQL
if confirm "Do you want to uninstall PostgreSQL? This will remove all databases."; then
    log "Uninstalling PostgreSQL..."
    apt-get --purge remove postgresql\* -y
    rm -rf /etc/postgresql/
    rm -rf /etc/postgresql-common/
    rm -rf /var/lib/postgresql/
    log "PostgreSQL removed."
else
    log "Skipping PostgreSQL removal."
fi

# Step 5: Remove Remaining Dependencies
log "Removing remaining Odoo dependencies..."
apt-get remove --auto-remove odoo -y

# Step 6: Clean Up
log "Cleaning up..."
apt-get update
apt-get autoremove -y

# Remove Odoo service file
if [ -f "/etc/systemd/system/odoo.service" ]; then
    rm /etc/systemd/system/odoo.service
    systemctl daemon-reload
    log "Odoo service file removed."
fi

# Final cleanup
log "Performing final cleanup..."
apt-get clean

log "Odoo 16 uninstallation process completed."
log "Please reboot your system to ensure all changes take effect."

# Prompt for reboot
if confirm "Do you want to reboot now?"; then
    log "Rebooting system..."
    reboot
else
    log "Please remember to reboot your system later."
fi
