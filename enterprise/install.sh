#!/bin/bash

# ============================================================================
# Mixpost Enterprise - VPS Installation Script
# ============================================================================
# Usage: curl -fsSL https://mixpost.app/install-enterprise.sh | bash
#
# This script installs and configures a fresh VPS with all required software
# and sets up the Mixpost application ready for use.
#
# Supported OS: Ubuntu 22.04 / 24.04
# ============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
MIXPOST_DIR="/var/www/html"
MIXPOST_USER="www-data"
PHP_VERSION="8.3"
MYSQL_VERSION="8.0"
STANDALONE_APP_MAJOR_VERSION=5

# ---------------------------------------------------------------------------
# Color helpers
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

error()   { printf "${RED}Error: %s${NC}\n" "$1"; }
fatal()   { printf "${RED}Fatal: %s${NC}\n" "$1"; exit 1; }
info()    { printf "${CYAN}%s${NC}\n" "$1"; }
success() { printf "${GREEN}%s${NC}\n" "$1"; }
warn()    { printf "${YELLOW}%s${NC}\n" "$1"; }
step()    { printf "\n${BOLD}${CYAN}[%s/%s] %s${NC}\n" "$1" "$TOTAL_STEPS" "$2"; }

TOTAL_STEPS=10

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
    fatal "This script must be run as root. Use: sudo bash or login as root."
fi

# Detect OS
if [[ ! -f /etc/os-release ]]; then
    fatal "Cannot detect OS. This script supports Ubuntu 22.04 / 24.04 only."
fi

source /etc/os-release

if [[ "$ID" != "ubuntu" ]]; then
    fatal "This script supports Ubuntu only. Detected: $ID"
fi

UBUNTU_CODENAME="$VERSION_CODENAME"

if [[ "$UBUNTU_CODENAME" != "jammy" && "$UBUNTU_CODENAME" != "noble" ]]; then
    warn "This script is tested on Ubuntu 22.04 (jammy) and 24.04 (noble)."
    warn "Detected: $VERSION_ID ($UBUNTU_CODENAME). Proceeding anyway..."
fi

# ---------------------------------------------------------------------------
# Banner
# ---------------------------------------------------------------------------
cat << 'BANNER'

  __  ____                       __     ______      __                       _         
   /  |/  (_)  ______  ____  _____/ /_   / ____/___  / /____  _________  _____(_)_______ 
  / /|_/ / / |/_/ __ \/ __ \/ ___/ __/  / __/ / __ \/ __/ _ \/ ___/ __ \/ ___/ / ___/ _ \
 / /  / / />  </ /_/ / /_/ (__  ) /_   / /___/ / / / /_/  __/ /  / /_/ / /  / (__  )  __/
/_/  /_/_/_/|_/ .___/\____/____/\__/  /_____/_/ /_/\__/\___/_/  / .___/_/  /_/____/\___/ 
             /_/                                               /_/                       
  
Mixpost Enterprise — VPS Installer

BANNER

# ---------------------------------------------------------------------------
# Gather configuration from user
# ---------------------------------------------------------------------------
info "This installer will set up your server and install Mixpost Enterprise."
info "Please provide the required configuration values."

# App name
read -rp "$(printf "${BOLD}Application name${NC} [Mixpost]: ")" INPUT_APP_NAME
INPUT_APP_NAME=${INPUT_APP_NAME:-Mixpost}

# Domain / URL
while true; do
    read -rp "$(printf "${BOLD}Domain name${NC} (e.g. smm.example.com): ")" INPUT_DOMAIN
    INPUT_DOMAIN=$(echo "$INPUT_DOMAIN" | sed 's|https\?://||;s|/$||')
    if [[ -n "$INPUT_DOMAIN" ]]; then break; fi
    error "Domain name is required."
done

# SSL
read -rp "$(printf "${BOLD}Enable SSL with Let's Encrypt?${NC} [Y/n]: ")" INPUT_SSL
INPUT_SSL=${INPUT_SSL:-Y}
if [[ "$INPUT_SSL" =~ ^[Yy] ]]; then
    USE_SSL=true
    APP_URL="https://${INPUT_DOMAIN}"
    REVERB_SCHEME="https"
    while true; do
        read -rp "$(printf "${BOLD}Email for Let's Encrypt${NC}: ")" INPUT_SSL_EMAIL
        if [[ -n "$INPUT_SSL_EMAIL" ]]; then break; fi
        error "Email is required for Let's Encrypt."
    done
else
    USE_SSL=false
    APP_URL="http://${INPUT_DOMAIN}"
    REVERB_SCHEME="http"
fi

# License key
while true; do
    read -rp "$(printf "${BOLD}Mixpost Enterprise license key${NC}: ")" INPUT_LICENSE_KEY
    if [[ -n "$INPUT_LICENSE_KEY" ]]; then break; fi
    error "License key is required."
done

# Database credentials
read -rp "$(printf "${BOLD}Database name${NC} [mixpost_db]: ")" INPUT_DB_NAME
INPUT_DB_NAME=${INPUT_DB_NAME:-mixpost_db}

read -rp "$(printf "${BOLD}Database username${NC} [mixpost]: ")" INPUT_DB_USER
INPUT_DB_USER=${INPUT_DB_USER:-mixpost}

DB_PASSWORD=$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c 24)
read -rp "$(printf "${BOLD}Database password${NC} [auto-generated]: ")" INPUT_DB_PASS
INPUT_DB_PASS=${INPUT_DB_PASS:-$DB_PASSWORD}


# App key
APP_KEY=$(openssl rand -base64 32)

# Reverb credentials
REVERB_APP_ID=$(shuf -i 100000-999999 -n 1)
REVERB_APP_KEY=$(openssl rand -hex 16)
REVERB_APP_SECRET=$(openssl rand -hex 16)

# Timezone
read -rp "$(printf "${BOLD}Timezone${NC} [UTC]: ")" INPUT_TIMEZONE
INPUT_TIMEZONE=${INPUT_TIMEZONE:-UTC}

# SMTP (optional)
echo ""
read -rp "$(printf "${BOLD}Configure SMTP mail now?${NC} [y/N]: ")" INPUT_CONFIGURE_SMTP
if [[ "$INPUT_CONFIGURE_SMTP" =~ ^[Yy] ]]; then
    read -rp "  SMTP host [smtp.mailgun.org]: " INPUT_MAIL_HOST
    INPUT_MAIL_HOST=${INPUT_MAIL_HOST:-smtp.mailgun.org}
    read -rp "  SMTP port [587]: " INPUT_MAIL_PORT
    INPUT_MAIL_PORT=${INPUT_MAIL_PORT:-587}
    read -rp "  SMTP username: " INPUT_MAIL_USER
    read -rsp "  SMTP password: " INPUT_MAIL_PASS
    echo ""
    read -rp "  SMTP encryption (tls/ssl/null) [tls]: " INPUT_MAIL_ENCRYPTION
    INPUT_MAIL_ENCRYPTION=${INPUT_MAIL_ENCRYPTION:-tls}
    read -rp "  From address [hello@${INPUT_DOMAIN}]: " INPUT_MAIL_FROM
    INPUT_MAIL_FROM=${INPUT_MAIL_FROM:-hello@${INPUT_DOMAIN}}
    read -rp "  From name [Mixpost]: " INPUT_MAIL_FROM_NAME
    INPUT_MAIL_FROM_NAME=${INPUT_MAIL_FROM_NAME:-Mixpost}
else
    INPUT_MAIL_HOST="smtp.mailgun.org"
    INPUT_MAIL_PORT="587"
    INPUT_MAIL_USER=""
    INPUT_MAIL_PASS=""
    INPUT_MAIL_ENCRYPTION="tls"
    INPUT_MAIL_FROM="hello@example.com"
    INPUT_MAIL_FROM_NAME="Mixpost"
fi

# Confirmation
echo ""
info "============================================"
info "  Installation Summary"
info "============================================"
echo "  Domain:      ${INPUT_DOMAIN}"
echo "  URL:         ${APP_URL}"
echo "  SSL:         ${USE_SSL}"
[[ "$USE_SSL" == true ]] && echo "  SSL Email:   ${INPUT_SSL_EMAIL}"
echo "  Database:    ${INPUT_DB_NAME}"
echo "  DB User:     ${INPUT_DB_USER}"
echo "  Timezone:    ${INPUT_TIMEZONE}"
info "============================================"
echo ""
info "Installation typically takes 5-15 minutes depending on your server."
echo ""

read -rp "$(printf "${BOLD}Proceed with installation?${NC} [Y/n]: ")" CONFIRM
CONFIRM=${CONFIRM:-Y}
if [[ ! "$CONFIRM" =~ ^[Yy] ]]; then
    info "Installation cancelled."
    exit 0
fi

echo ""

# ============================================================================
# STEP 1: System Update & Base Packages
# ============================================================================
step 1 "Updating system and installing base packages..."

export DEBIAN_FRONTEND=noninteractive

# Clean up stale repo configs from previous installs
rm -f /etc/apt/sources.list.d/mysql.list
rm -f /etc/apt/sources.list.d/ppa_ondrej_php.list
rm -f /etc/apt/sources.list.d/php-sury.list
rm -f /etc/apt/keyrings/mysql.gpg
rm -f /etc/apt/keyrings/ppa_ondrej_php.gpg
rm -f /etc/apt/keyrings/deb.sury.org-php.gpg

apt-get update -qq
apt-get upgrade -y -qq

apt-get install -y -qq \
    software-properties-common \
    curl \
    gnupg \
    ca-certificates \
    zip \
    unzip \
    cron \
    nano \
    ufw \
    wget \
    lsb-release \
    apt-transport-https

success "Base packages installed."

# ============================================================================
# STEP 2: Install PHP 8.3
# ============================================================================
step 2 "Installing PHP ${PHP_VERSION} and extensions..."

add-apt-repository -y ppa:ondrej/php > /dev/null 2>&1

apt-get update -qq

apt-get install -y -qq \
    php${PHP_VERSION} \
    php${PHP_VERSION}-fpm \
    php${PHP_VERSION}-cli \
    php${PHP_VERSION}-mysql \
    php${PHP_VERSION}-gd \
    php${PHP_VERSION}-curl \
    php${PHP_VERSION}-bcmath \
    php${PHP_VERSION}-mbstring \
    php${PHP_VERSION}-redis \
    php${PHP_VERSION}-xml \
    php${PHP_VERSION}-zip \
    php${PHP_VERSION}-intl \
    php-pear \
    php${PHP_VERSION}-dev \
    libuv1-dev

# Install uv PECL extension
pecl install channel://pecl.php.net/uv-0.3.0 < /dev/null || true
echo "extension=uv.so" > /etc/php/${PHP_VERSION}/cli/conf.d/30-uv.ini
echo "extension=uv.so" > /etc/php/${PHP_VERSION}/fpm/conf.d/30-uv.ini

# Configure PHP
cat > /etc/php/${PHP_VERSION}/fpm/conf.d/99-mixpost.ini << 'PHPINI'
[PHP]
memory_limit=512M
post_max_size=70M
upload_max_filesize=64M
max_execution_time=60
variables_order=EGPCS
zend.max_allowed_stack_size=-1

[FFI]
ffi.enable=true
PHPINI

# Also apply to CLI
cp /etc/php/${PHP_VERSION}/fpm/conf.d/99-mixpost.ini /etc/php/${PHP_VERSION}/cli/conf.d/99-mixpost.ini

# Ensure PHP-FPM socket directory exists
mkdir -p /var/run/php

success "PHP ${PHP_VERSION} installed and configured."

# ============================================================================
# STEP 3: Install Composer
# ============================================================================
step 3 "Installing Composer..."

curl -sLS https://getcomposer.org/installer | php -- --install-dir=/usr/bin/ --filename=composer

success "Composer installed."

# ============================================================================
# STEP 4: Install Nginx
# ============================================================================
step 4 "Installing and configuring Nginx..."

apt-get install -y -qq nginx

# Configure Nginx for Mixpost
cat > /etc/nginx/sites-available/mixpost << NGINXCONF
server {
    listen 80;
    server_name ${INPUT_DOMAIN};
    server_tokens off;
    root ${MIXPOST_DIR}/public;
    index index.php index.html;
    client_max_body_size 70M;

    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-XSS-Protection "1; mode=block";
    add_header X-Content-Type-Options "nosniff";

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location = /robots.txt { access_log off; log_not_found off; }

    access_log off;
    error_log /var/log/nginx/mixpost-error.log error;

    error_page 404 /index.php;

    location ~ \.php\$ {
        try_files \$uri =404;
        fastcgi_split_path_info ^(.+\.php)(/.+)\$;
        fastcgi_pass unix:/var/run/php/php${PHP_VERSION}-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param PATH_INFO \$fastcgi_path_info;
        fastcgi_read_timeout 1000;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_buffer_size 128k;
        proxy_buffers 4 256k;
        proxy_busy_buffers_size 256k;
    }

    location ~ /\.(?!well-known).* {
        deny all;
    }

    location /app {
        proxy_http_version 1.1;
        proxy_set_header Host \$http_host;
        proxy_set_header Scheme \$scheme;
        proxy_set_header SERVER_PORT \$server_port;
        proxy_set_header REMOTE_ADDR \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_pass http://127.0.0.1:8080;
    }

    location /apps {
        proxy_http_version 1.1;
        proxy_set_header Host \$http_host;
        proxy_set_header Scheme \$scheme;
        proxy_set_header SERVER_PORT \$server_port;
        proxy_set_header REMOTE_ADDR \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_pass http://127.0.0.1:8080;
    }
}
NGINXCONF

# Enable site, disable default
ln -sf /etc/nginx/sites-available/mixpost /etc/nginx/sites-enabled/mixpost
rm -f /etc/nginx/sites-enabled/default

# Tune Nginx
sed -i 's/worker_connections\s*[0-9]*/worker_connections 10000/' /etc/nginx/nginx.conf
grep -q "worker_rlimit_nofile" /etc/nginx/nginx.conf || \
    sed -i '/^events/i worker_rlimit_nofile 10000;' /etc/nginx/nginx.conf
grep -q "multi_accept" /etc/nginx/nginx.conf || \
    sed -i '/worker_connections/a\        multi_accept on;' /etc/nginx/nginx.conf

nginx -t
systemctl enable nginx

success "Nginx installed and configured."

# ============================================================================
# STEP 5: Install MySQL 8.0
# ============================================================================
step 5 "Installing MySQL ${MYSQL_VERSION}..."

# Purge previous MySQL if root access is broken from a prior run
if command -v mysql &>/dev/null && ! mysql -u root -e "SELECT 1" &>/dev/null; then
    warn "Detected broken MySQL root access. Reinstalling MySQL..."
    systemctl stop mysql 2>/dev/null || true
    apt-get purge -y -qq mysql-server mysql-client mysql-common 2>/dev/null || true
    rm -rf /var/lib/mysql /etc/mysql
    apt-get autoremove -y -qq 2>/dev/null || true
fi

apt-get install -y -qq mysql-server mysql-client

systemctl start mysql
systemctl enable mysql

# Create database + user
mysql -u root <<MYSQL_SETUP
CREATE DATABASE IF NOT EXISTS \`${INPUT_DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${INPUT_DB_USER}'@'localhost' IDENTIFIED BY '${INPUT_DB_PASS}';
GRANT ALL PRIVILEGES ON \`${INPUT_DB_NAME}\`.* TO '${INPUT_DB_USER}'@'localhost';
FLUSH PRIVILEGES;
MYSQL_SETUP

success "MySQL ${MYSQL_VERSION} installed. Database '${INPUT_DB_NAME}' created."

# ============================================================================
# STEP 6: Install Redis
# ============================================================================
step 6 "Installing Redis..."

apt-get install -y -qq redis-server

# Configure Redis for persistence
sed -i 's/^# appendonly no/appendonly yes/' /etc/redis/redis.conf
sed -i 's/^appendonly no/appendonly yes/' /etc/redis/redis.conf

# Bind to localhost only
sed -i 's/^bind .*/bind 127.0.0.1 ::1/' /etc/redis/redis.conf

systemctl restart redis-server
systemctl enable redis-server

success "Redis installed and configured."

# ============================================================================
# STEP 7: Install Media Processing Libraries
# ============================================================================
step 7 "Installing FFmpeg, libvips, and media libraries..."

# Add libheif PPA for HEIF support
add-apt-repository -y ppa:strukturag/libheif 2>/dev/null || true
apt-get update -qq

apt-get install -y -qq \
    ffmpeg \
    libvips42t64 \
    libheif1 \
    libde265-0 \
    2>/dev/null || apt-get install -y -qq ffmpeg libvips42 2>/dev/null || apt-get install -y -qq ffmpeg

success "Media processing libraries installed."

# ============================================================================
# STEP 8: Install Mixpost Application
# ============================================================================
step 8 "Installing Mixpost Enterprise application..."

mkdir -p ${MIXPOST_DIR}
cd ${MIXPOST_DIR}

# Configure Composer auth for Mixpost license
mkdir -p /root/.config/composer
cat > /root/.config/composer/auth.json << COMPOSERAUTH
{
    "http-basic": {
        "packages.inovector.com": {
            "username": "username",
            "password": "${INPUT_LICENSE_KEY}"
        }
    }
}
COMPOSERAUTH

# Create the Mixpost Enterprise project
export COMPOSER_ALLOW_SUPERUSER=1

info "Downloading Mixpost Enterprise (this may take a few minutes)..."

composer create-project inovector/mixpost-enterprise-app:^${STANDALONE_APP_MAJOR_VERSION}.0 /tmp/mixpost-app --no-interaction --prefer-dist

# Copy files to web root
cp -r /tmp/mixpost-app/* ${MIXPOST_DIR}/
cp /tmp/mixpost-app/.* ${MIXPOST_DIR}/ 2>/dev/null || true
rm -rf /tmp/mixpost-app

# Create .env file
cat > ${MIXPOST_DIR}/.env << ENVFILE
# Application
APP_NAME="${INPUT_APP_NAME}"
APP_KEY=base64:${APP_KEY}
APP_DEBUG=false
APP_URL=${APP_URL}
APP_ENV=production

# Database
DB_CONNECTION=mysql
DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=${INPUT_DB_NAME}
DB_USERNAME=${INPUT_DB_USER}
DB_PASSWORD=${INPUT_DB_PASS}

# Redis
REDIS_CLIENT=phpredis
REDIS_URL=null
REDIS_HOST=127.0.0.1
REDIS_PASSWORD=null
REDIS_PORT=6379
REDIS_PREFIX=mixpost_database_

# Mixpost Configuration
MIXPOST_DEFAULT_LOCALE=en-GB
MIXPOST_TIMEZONE=${INPUT_TIMEZONE}
MIXPOST_TIME_FORMAT=12
MIXPOST_FIRST_DAY_WEEK=1
MIXPOST_CORE_PATH=mixpost
MIXPOST_LOG_CHANNEL=mixpost
MIXPOST_DISK=public
MIXPOST_FORGOT_PASSWORD=true
MIXPOST_TWO_FACTOR_AUTH=true
MIXPOST_API_ACCESS_TOKENS=true
MIXPOST_AUTO_SUBSCRIBE_POST_ACTIVITIES=false
MIXPOST_CACHE_PREFIX=mixpost
MIXPOST_PUBLIC_PAGES_PREFIX=pages
FORCE_CORE_PATH_CALLBACK_TO_NATIVE=false

# File Upload Limits (MB)
MIXPOST_MAX_IMAGE_FILE_SIZE=15
MIXPOST_MAX_GIF_FILE_SIZE=15
MIXPOST_MAX_VIDEO_FILE_SIZE=200
MIXPOST_CHUNKED_UPLOAD_SIZE=10
MIXPOST_CHUNKED_UPLOAD_THRESHOLD=10

# Mail
MAIL_MAILER=${INPUT_MAIL_HOST:+smtp}
MAIL_MAILER=${MAIL_MAILER:-smtp}
MAIL_HOST=${INPUT_MAIL_HOST}
MAIL_PORT=${INPUT_MAIL_PORT}
MAIL_USERNAME=${INPUT_MAIL_USER}
MAIL_PASSWORD=${INPUT_MAIL_PASS}
MAIL_ENCRYPTION=${INPUT_MAIL_ENCRYPTION}
MAIL_FROM_ADDRESS="${INPUT_MAIL_FROM}"
MAIL_FROM_NAME="${INPUT_MAIL_FROM_NAME}"

# Broadcasting (Reverb WebSocket)
BROADCAST_DRIVER=reverb
REVERB_APP_ID=${REVERB_APP_ID}
REVERB_APP_KEY=${REVERB_APP_KEY}
REVERB_APP_SECRET=${REVERB_APP_SECRET}
REVERB_HOST=${INPUT_DOMAIN}
REVERB_PORT=8080
REVERB_SCHEME=${REVERB_SCHEME}
REVERB_SCALING_ENABLED=true

# Queue & Session
QUEUE_CONNECTION=redis
SESSION_DRIVER=redis
CACHE_PREFIX=mixpost_cache_
SESSION_COOKIE=mixpost_session
HORIZON_PREFIX=mixpost_horizon:

# Sentry (optional)
SENTRY_LARAVEL_DSN=null
ENVFILE

# Laravel setup
php artisan storage:link
php artisan optimize:clear
php artisan optimize
php artisan migrate --force
php artisan mixpost:clear-settings-cache 2>/dev/null || true
php artisan mixpost:clear-services-cache 2>/dev/null || true

# Set permissions
chown -R ${MIXPOST_USER}:${MIXPOST_USER} ${MIXPOST_DIR}
chmod -R 755 ${MIXPOST_DIR}
chmod -R 775 ${MIXPOST_DIR}/storage ${MIXPOST_DIR}/bootstrap/cache

success "Mixpost Enterprise application installed."

# ============================================================================
# STEP 9: Configure Supervisor, Cron & Services
# ============================================================================
step 9 "Configuring Supervisor, cron jobs, and services..."

apt-get install -y -qq supervisor

# Supervisor config for Horizon (queue worker)
cat > /etc/supervisor/conf.d/mixpost-horizon.conf << 'HORIZONCONF'
[program:mixpost-horizon]
process_name=%(program_name)s_%(process_num)02d
command=php /var/www/html/artisan horizon
autostart=true
autorestart=true
user=www-data
numprocs=1
startsecs=1
redirect_stderr=true
stdout_logfile=/var/log/supervisor/horizon.log
stdout_logfile_maxbytes=5MB
stdout_logfile_backups=3
stopwaitsecs=5
stopsignal=SIGTERM
stopasgroup=true
killasgroup=true
HORIZONCONF

# Supervisor config for Reverb (WebSocket server)
cat > /etc/supervisor/conf.d/mixpost-reverb.conf << 'REVERBCONF'
[program:mixpost-reverb]
process_name=%(program_name)s_%(process_num)02d
command=php /var/www/html/artisan reverb:start --no-interaction
autostart=true
autorestart=true
user=www-data
numprocs=1
startsecs=1
redirect_stderr=true
stdout_logfile=/var/log/supervisor/reverb.log
stdout_logfile_maxbytes=5MB
stdout_logfile_backups=3
stopwaitsecs=5
stopsignal=SIGTERM
stopasgroup=true
killasgroup=true
REVERBCONF

# Create log directory
mkdir -p /var/log/supervisor

# Cron job for Laravel scheduler
cat > /etc/cron.d/mixpost << 'CRONCONF'
* * * * * www-data cd /var/www/html && php artisan schedule:run >> /dev/null 2>&1
CRONCONF

chmod 0644 /etc/cron.d/mixpost

# Restart services
systemctl restart supervisor
supervisorctl reread
supervisorctl update
systemctl restart php${PHP_VERSION}-fpm
systemctl restart nginx
systemctl restart cron

success "Supervisor, cron, and services configured."

# ============================================================================
# STEP 10: SSL (Let's Encrypt) & Firewall
# ============================================================================
step 10 "Configuring firewall and SSL..."

# Configure UFW firewall
ufw --force reset > /dev/null 2>&1
ufw default deny incoming > /dev/null 2>&1
ufw default allow outgoing > /dev/null 2>&1
ufw allow ssh > /dev/null 2>&1
ufw allow 80/tcp > /dev/null 2>&1
ufw allow 443/tcp > /dev/null 2>&1
ufw allow 8080/tcp > /dev/null 2>&1
ufw --force enable > /dev/null 2>&1

success "Firewall configured (SSH, HTTP, HTTPS, WebSocket:8080)."

if [[ "$USE_SSL" == true ]]; then
    info "Installing Certbot and obtaining SSL certificate..."

    apt-get install -y -qq certbot python3-certbot-nginx

    certbot --nginx \
        -d "${INPUT_DOMAIN}" \
        --non-interactive \
        --agree-tos \
        --email "${INPUT_SSL_EMAIL}" \
        --redirect

    # After certbot modifies nginx config, ensure WebSocket proxy
    # locations are still present in the SSL server block
    NGINX_CONF="/etc/nginx/sites-available/mixpost"

    # Check if certbot already handled the WebSocket locations in SSL block
    if ! grep -A2 "listen 443" "$NGINX_CONF" | grep -q "443"; then
        warn "Certbot may not have configured the SSL block properly. Please verify Nginx config."
    fi

    # Enable auto-renewal
    systemctl enable certbot.timer 2>/dev/null || true

    # Test renewal
    certbot renew --dry-run 2>/dev/null || warn "Certbot dry-run failed. Check certbot configuration."

    success "SSL certificate obtained and configured."
fi

# ============================================================================
# Final Summary
# ============================================================================
echo ""
echo ""
cat << 'BANNER'
    __  ____                       __     ______      __                       _         
   /  |/  (_)  ______  ____  _____/ /_   / ____/___  / /____  _________  _____(_)_______ 
  / /|_/ / / |/_/ __ \/ __ \/ ___/ __/  / __/ / __ \/ __/ _ \/ ___/ __ \/ ___/ / ___/ _ \
 / /  / / />  </ /_/ / /_/ (__  ) /_   / /___/ / / / /_/  __/ /  / /_/ / /  / (__  )  __/
/_/  /_/_/_/|_/ .___/\____/____/\__/  /_____/_/ /_/\__/\___/_/  / .___/_/  /_/____/\___/ 
             /_/                                               /_/                       
BANNER

echo ""
success "============================================"
success "  Mixpost Enterprise installed successfully!"
success "============================================"
echo ""
echo "  Application URL:    ${APP_URL}"
echo ""
echo "  Database Host:      127.0.0.1"
echo "  Database Name:      ${INPUT_DB_NAME}"
echo "  Database User:      ${INPUT_DB_USER}"
echo "  Database Password:  ${INPUT_DB_PASS}"
echo ""
echo "  MySQL Root Access:  sudo mysql"
echo ""
echo "  Application files:  ${MIXPOST_DIR}"
echo "  App .env file:      ${MIXPOST_DIR}/.env"
echo ""
info "  Services running:"
echo "    - Nginx          (web server)"
echo "    - PHP-FPM ${PHP_VERSION}   (PHP processor)"
echo "    - MySQL ${MYSQL_VERSION}      (database)"
echo "    - Redis          (cache & queue)"
echo "    - Horizon        (queue worker via Supervisor)"
echo "    - Reverb         (WebSocket server via Supervisor)"
echo "    - Cron           (Laravel scheduler)"
echo ""
if [[ "$USE_SSL" == true ]]; then
    success "  SSL: Enabled (auto-renewal configured)"
else
    warn "  SSL: Not configured. Run the following to enable:"
    echo "    apt install certbot python3-certbot-nginx"
    echo "    certbot --nginx -d ${INPUT_DOMAIN}"
fi
echo ""
warn "  IMPORTANT: Save the credentials above in a safe place!"
echo ""
info "  Next steps:"
echo "    1. Visit ${APP_URL} to create your admin account"
echo "    2. Configure your social media accounts in the dashboard"
echo "    3. Configure SMTP settings in .env if not done during setup"
echo ""
info "  Useful commands:"
echo "    supervisorctl status                 - Check Horizon & Reverb status"
echo "    systemctl status nginx               - Check Nginx status"
echo "    systemctl status mysql               - Check MySQL status"
echo "    systemctl status redis-server        - Check Redis status"
echo "    tail -f /var/log/nginx/mixpost-error.log  - View Nginx errors"
echo "    tail -f ${MIXPOST_DIR}/storage/logs/*.log - View app logs"
echo ""
success "------- Installation Complete! -------"
echo ""
