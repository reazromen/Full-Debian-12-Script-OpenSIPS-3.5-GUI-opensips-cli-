#!/bin/bash

# === CONFIGURATION ===
DB_ROOT_PASS="your_root_db_password"
DB_OPENSIPS_USER="opensips"
DB_OPENSIPS_PASS="opensipsrw"
DB_NAME="opensips"
CP_ADMIN_PASS="opensips"

# === UPDATE SYSTEM ===
apt update && apt upgrade -y

# === INSTALL DEPENDENCIES ===
apt install -y gnupg2 curl lsb-release ca-certificates \
    mariadb-server apache2 php php-mysql php-cli php-xml php-curl php-mbstring git \
    build-essential bison flex pkg-config libssl-dev libcurl4-openssl-dev \
    libxml2-dev libpcre3-dev libedit-dev libmariadb-dev libevent-dev python3-pip

# === SETUP OPENSIPS REPO ===
wget -O - https://apt.opensips.org/pubkey.gpg | gpg --dearmor -o /etc/apt/trusted.gpg.d/opensips.gpg
echo "deb http://apt.opensips.org bookworm 3.5-releases" > /etc/apt/sources.list.d/opensips.list
apt update

# === INSTALL OPENSIPS CORE ===
apt install -y opensips opensips-mysql-module opensips-json-module opensips-tls-module

# === ENABLE AND START MYSQL ===
systemctl enable mariadb
systemctl start mariadb

# === MYSQL: SECURE INSTALLATION AND CREATE DATABASE ===
mysql -u root <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT_PASS}';
DELETE FROM mysql.user WHERE User='';
DROP DATABASE IF EXISTS test;
FLUSH PRIVILEGES;
EOF

mysql -uroot -p${DB_ROOT_PASS} <<EOF
CREATE DATABASE ${DB_NAME};
CREATE USER '${DB_OPENSIPS_USER}'@'localhost' IDENTIFIED BY '${DB_OPENSIPS_PASS}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_OPENSIPS_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF

# === INSTALL opensips-cli (via pip3) ===
pip3 install opensips-cli

# === CONFIGURE opensips-cli ===
mkdir -p /etc/opensips
cat > /etc/opensips/opensips-cli.cfg <<EOF
[default]
database_url = mysql://${DB_OPENSIPS_USER}:${DB_OPENSIPS_PASS}@localhost/${DB_NAME}
database_admin_url = mysql://root:${DB_ROOT_PASS}@localhost
EOF

# === SETUP OPENSIPS DB STRUCTURE ===
opensips-cli -x database create

# === SETUP OPENSIPS CONTROL PANEL ===
cd /var/www/html
git clone https://github.com/OpenSIPS/opensips-cp
cd opensips-cp
cp config/tools/system/config.php.sample config/tools/system/config.php
cp config/db.inc.php.sample config/db.inc.php

# === CONFIGURE DB ACCESS FOR CONTROL PANEL ===
sed -i "s/\$config->db_pass = .*/\$config->db_pass = \"${DB_OPENSIPS_PASS}\";/g" config/db.inc.php

# === IMPORT GUI TABLES ===
mysql -u${DB_OPENSIPS_USER} -p${DB_OPENSIPS_PASS} ${DB_NAME} < config/db_schema.mysql

# === SET ADMIN LOGIN ===
mysql -u${DB_OPENSIPS_USER} -p${DB_OPENSIPS_PASS} ${DB_NAME} <<EOF
INSERT INTO admin (username, password, permissions) VALUES ('admin', MD5('${CP_ADMIN_PASS}'), 'ALL');
EOF

# === APACHE CONFIG ===
chown -R www-data:www-data /var/www/html/opensips-cp
systemctl restart apache2

# === DONE ===
echo
echo "✅ OpenSIPS 3.5 + Control Panel Installed Successfully"
echo "👉 Access GUI: http://$(hostname -I | awk '{print $1}')/opensips-cp/web/"
echo "🔐 Login: admin / ${CP_ADMIN_PASS}"
