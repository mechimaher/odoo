#!/bin/bash

# Professional Odoo 17 Installation Script for Ubuntu 24.04 LTS
# This script provides a robust, flexible, and error-resistant installation of Odoo 17.
# Compatible with WSL, PyCharm, cloud hosting, and standard Ubuntu installations.

set -e

# Color codes for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Log all output to a file
LOG_FILE="/var/log/odoo17_install.log"
exec > >(tee -i ${LOG_FILE}) 2>&1

# Functions for printing messages
print_message() { echo -e "${GREEN}$1${NC}"; }
print_warning() { echo -e "${YELLOW}Warning: $1${NC}"; }
print_error() { echo -e "${RED}Error: $1${NC}"; }

# Function to check if a command executed successfully
check_command() {
    if [ $? -ne 0 ]; then
        print_error "$1"
        exit 1
    fi
}

# Function to check if a package is installed
is_installed() { dpkg -s "$1" >/dev/null 2>&1; }

# Function to install a package if not already installed
install_package() {
    if ! is_installed "$1"; then
        print_message "Installing $1..."
        apt install -y "$1"
        check_command "Failed to install $1"
    else
        print_message "$1 is already installed."
    fi
}

# Check if script is run as root
if [[ $EUID -ne 0 ]]; then
   print_error "This script must be run as root"
   exit 1
fi

# Detect system information
print_message "Detecting system information..."
DISTRO=$(lsb_release -is)
RELEASE=$(lsb_release -rs)
IP_ADDRESS=$(hostname -I | awk '{print $1}')
DOMAIN=${DOMAIN:-"localhost"}
ODOO_USER=${ODOO_USER:-"odoo17"}
ODOO_DIR=${ODOO_DIR:-"/opt/$ODOO_USER"}

# Ensure compatible Ubuntu version
SUPPORTED_UBUNTU_VERSIONS=("20.04" "22.04" "24.04")
if [[ ! " ${SUPPORTED_UBUNTU_VERSIONS[@]} " =~ " ${RELEASE} " ]]; then
    print_error "Unsupported Ubuntu version: $RELEASE. Supported versions are ${SUPPORTED_UBUNTU_VERSIONS[@]}"
    exit 1
fi

# Detect environment (WSL, PyCharm, AWS, or Standard)
print_message "Detecting environment..."
if grep -qEi "(Microsoft|WSL)" /proc/version &> /dev/null; then
    ENV="WSL"
elif [ -n "$PYCHARM_HOSTED" ] || [ -n "$JETBRAINS_REMOTE_RUN" ]; then
    ENV="PYCHARM"
elif [ -f /sys/hypervisor/uuid ] && [ `head -c 3 /sys/hypervisor/uuid` == "ec2" ]; then
    ENV="AWS-EC2"
else
    ENV="STANDARD"
fi
print_message "Detected environment: $ENV"
print_message "Detected $DISTRO $RELEASE"
print_message "IP Address: $IP_ADDRESS"
print_message "Using domain: $DOMAIN"

# Update and upgrade system
print_message "Updating and upgrading system..."
apt update && apt upgrade -y
check_command "Failed to update and upgrade system"

# Install dependencies
print_message "Installing dependencies..."
PACKAGES=(
    git wget build-essential python3-dev python3-pip python3-venv
    libxml2-dev libxslt1-dev zlib1g-dev libsasl2-dev
    libldap2-dev libssl-dev libffi-dev libmysqlclient-dev
    libjpeg-dev libpq-dev libjpeg8-dev liblcms2-dev libblas-dev libatlas-base-dev
    node-less libtiff5-dev libopenjp2-7-dev libcap-dev
)
for package in "${PACKAGES[@]}"; do
    install_package "$package"
done

# Install and configure PostgreSQL
print_message "Installing and configuring PostgreSQL..."
install_package "postgresql"

# Ensure PostgreSQL version is 12 or higher
PG_VERSION=$(psql --version | grep -oP '\d+\.\d+')
if [[ "$PG_VERSION" < "12" ]]; then
    print_error "PostgreSQL version 12 or higher is required. Detected version: $PG_VERSION."
    exit 1
fi

# Create Odoo system user
print_message "Creating Odoo system user..."
if id "$ODOO_USER" &>/dev/null; then
    print_warning "User $ODOO_USER already exists. Skipping user creation."
else
    adduser --system --home=$ODOO_DIR --group $ODOO_USER
    check_command "Failed to create Odoo system user"
fi

# Create PostgreSQL user
print_message "Creating PostgreSQL user..."
if sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$ODOO_USER'" | grep -q 1; then
    print_warning "PostgreSQL user $ODOO_USER already exists. Skipping user creation."
else
    sudo -u postgres createuser -s $ODOO_USER
    check_command "Failed to create PostgreSQL user"
fi

# Install wkhtmltopdf
print_message "Installing wkhtmltopdf..."
install_package "wkhtmltopdf"

# Install Odoo
print_message "Installing Odoo 17..."
if [ -d "$ODOO_DIR/odoo17" ]; then
    print_warning "Odoo directory already exists. Updating..."
    su - $ODOO_USER -c "cd $ODOO_DIR/odoo17 && git pull"
else
    su - $ODOO_USER -c "
        git clone https://www.github.com/odoo/odoo --depth 1 --branch 17.0 $ODOO_DIR/odoo17
        python3 -m venv $ODOO_DIR/odoo17-venv
        source $ODOO_DIR/odoo17-venv/bin/activate
        pip3 install wheel setuptools pip --upgrade
        pip3 install -r $ODOO_DIR/odoo17/requirements.txt
        mkdir -p $ODOO_DIR/odoo17/custom-addons
        deactivate
    "
fi
check_command "Failed to install/update Odoo 17"

# Create or update Odoo configuration file
print_message "Creating/updating Odoo configuration file..."
if [ -f "/etc/odoo17.conf" ]; then
    print_warning "Odoo configuration file already exists. Backing up and creating new one."
    mv /etc/odoo17.conf /etc/odoo17.conf.bak
fi

cat << EOF > /etc/odoo17.conf
[options]
admin_passwd = $(openssl rand -base64 12)
db_host = False
db_port = False
db_user = $ODOO_USER
db_password = False
addons_path = $ODOO_DIR/odoo17/addons,$ODOO_DIR/odoo17/custom-addons
xmlrpc_port = 8069
EOF
check_command "Failed to create/update Odoo configuration file"

# Create or update Odoo systemd service file (skipping PyCharm)
if [ "$ENV" != "PYCHARM" ]; then
    print_message "Creating/updating Odoo systemd service file..."
    cat << EOF > /etc/systemd/system/odoo17.service
[Unit]
Description=Odoo17
Requires=postgresql.service
After=network.target postgresql.service

[Service]
Type=simple
SyslogIdentifier=odoo17
PermissionsStartOnly=true
User=$ODOO_USER
Group=$ODOO_USER
ExecStart=$ODOO_DIR/odoo17-venv/bin/python3 $ODOO_DIR/odoo17/odoo-bin -c /etc/odoo17.conf
StandardOutput=journal+console
Restart=always

[Install]
WantedBy=multi-user.target
EOF
    check_command "Failed to create/update Odoo systemd service file"

    # Reload systemd, enable and start Odoo service
    print_message "Starting Odoo service..."
    systemctl daemon-reload
    systemctl enable --now odoo17
    check_command "Failed to start Odoo service"
else
    print_message "Skipping systemd service creation in PyCharm environment."
fi

# Install and configure Nginx (skip for PyCharm)
if [ "$ENV" != "PYCHARM" ]; then
    print_message "Installing and configuring Nginx..."
    install_package "nginx"

    # Install Certbot
    print_message "Installing Certbot..."
    install_package "certbot"
    install_package "python3-certbot-nginx"

    # Create or update Nginx configuration for Odoo
    print_message "Creating/updating Nginx configuration for Odoo..."
    cat << EOF > /etc/nginx/sites-available/odoo
upstream odoo17 {
    server 127.0.0.1:8069;
}

upstream odoochat {
    server 127.0.0.1:8072;
}

server {
    listen 80;
    server_name $DOMAIN;

    access_log /var/log/nginx/odoo17.access.log;
    error_log /var/log/nginx/odoo17.error.log;

    proxy_buffers 16 64k;
    proxy_buffer_size 128k;

    location / {
        proxy_pass http://odoo17;
        proxy_next_upstream error timeout invalid_header http_500 http_502 http_503 http_504;
        proxy_redirect off;

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location /longpolling {
        proxy_pass http://odoochat;
    }

    location ~* /web/static/ {
        proxy_cache_valid 200 60m;
        proxy_buffering on;
        expires 864000;
        proxy_pass http://odoo17;
    }
}
EOF
    check_command "Failed to create/update Nginx configuration for Odoo"

    # Enable Odoo Nginx configuration
    if [ ! -f /etc/nginx/sites-enabled/odoo ]; then
        ln -s /etc/nginx/sites-available/odoo /etc/nginx/sites-enabled/
    fi
    rm -f /etc/nginx/sites-enabled/default
    check_command "Failed to enable Odoo Nginx configuration"

    # Restart Nginx
    print_message "Restarting Nginx..."
    systemctl restart nginx
    check_command "Failed to restart Nginx"
else
    print_message "Skipping Nginx installation and configuration in PyCharm environment."
fi

print_message "Odoo 17 installation completed successfully!"

# Environment-specific instructions
case $ENV in
    WSL)
        print_message "WSL environment detected. Please ensure that you have configured port forwarding correctly."
        print_message "You may need to run the following commands on your Windows host:"
        print_message "netsh interface portproxy add v4tov4 listenport=80 listenaddress=0.0.0.0 connectport=80 connectaddress=$IP_ADDRESS"
        print_message "netsh interface portproxy add v4tov4 listenport=443 listenaddress=0.0.0.0 connectport=443 connectaddress=$IP_ADDRESS"
        print_message "For local testing, add the following entry to your Windows hosts file:"
        print_message "$IP_ADDRESS $DOMAIN"
        ;;
    PYCHARM)
        print_message "PyCharm environment detected. To run Odoo, use the following command:"
        print_message "$ODOO_DIR/odoo17-venv/bin/python3 $ODOO_DIR/odoo17/odoo-bin -c /etc/odoo17.conf"
        ;;
    AWS-EC2)
        print_message "AWS EC2 environment detected. Ensure that you have configured your security groups to allow incoming traffic on ports 80 and 443."
        ;;
    STANDARD)
        print_message "Standard Ubuntu environment detected. No additional steps required."
        ;;
esac

if [ "$ENV" != "PYCHARM" ]; then
    print_message "You can now access Odoo at http://$DOMAIN or http://$IP_ADDRESS"
    print_message "To set up SSL with Certbot, run: sudo certbot --nginx -d $DOMAIN"
fi

print_message "Please make sure to change the default master password in /etc/odoo17.conf"
print_message "Installation complete. Enjoy your Odoo 17 instance!"
