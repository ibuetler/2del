#!/bin/bash
admin_username=lab_admin
admin_password=WohPaejie4
hostname=ivan
tooldir=/home/lab_admin/tooldir
ubuntu1_server_ip="10.0.1.16"

set -e

id > /tmp/mylog
sed -i "s/ubuntu/${hostname}/" /etc/hosts
export DEBIAN_FRONTEND="noninteractive"

tooldir=/home/${admin_username}/tools
mkdir -p {$tooldir,/opt/applic/,}

# Installation Docker
apt-get update -y
apt-get install -y ca-certificates curl vim software-properties-common
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources:
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Python Pip
apt-get install python3-pip -y
# Only 'pip3' command is currently available. Install 'pip' command too. This is needed for some packages using 'pip' instead of 'pip3'
# IVAN pip3 install --upgrade pip --break-system-packages

usermod -aG docker ${admin_username}
systemctl start docker
systemctl enable docker


# Wazuh https://documentation.wazuh.com/current/docker/wazuh-container.html
sysctl -w vm.max_map_count=262144


# Clone Wazuh, additional tools and SOC configuration repositories
cd /opt/applic/
git clone https://github.com/wazuh/wazuh-docker.git -b v4.1.2 --depth=1
git clone https://github.com/Hacking-Lab/SecurityOperationsCenter.git soc_config
git clone https://github.com/SecureAuthCorp/impacket.git
git clone https://github.com/aditosoftware/nodepki-docker.git nodepki

# Override Wazuh docker-compose.yml
cp /opt/applic/soc_config/soc/docker-compose.yml /opt/applic/wazuh-docker/docker-compose.yml


apt-get install smbclient -y
cd /opt/applic/impacket/
pip3 install . --break-system-packages


# Generate self-signed certificates
cd /opt/applic/soc_config/traefik/certs/
# TODO rename cert
openssl req -newkey rsa:2048 -x509 -nodes -keyout cert.key -new -out cert.crt -subj /CN=*.winattacklab.local -reqexts SAN -extensions SAN -config <(cat /etc/ssl/openssl.cnf <(printf '[SAN]\nsubjectAltName=DNS:*.winattacklab.local, IP:10.0.1.16')) -sha256 -days 3650
#https://serverfault.com/questions/880804/can-not-get-rid-of-neterr-cert-common-name-invalid-error-in-chrome-with-self

# Fix SeSecurityOperationsCenter/attack-launcher/Dockerfile by checking out the version 9.4 of thc-hydra
# sed -i 's/git clone \(https.*vanhauser-thc\/thc-hydra\)/git clone --depth 1 --branch "v9.4" \1/' /opt/applic/soc_config/attack-launcher/Dockerfile

# Start traefik
docker network create traefik_proxy
cd /opt/applic/soc_config/traefik/
docker compose up -d

# Start Wazuh
cd /opt/applic/wazuh-docker/
docker compose up -d

# Start attack launcher
cd /opt/applic/soc_config/attack-launcher/
docker compose up -d

# Start mailcatcher
cd /opt/applic/soc_config/mailcatcher/
docker compose up -d
chmod +x smtptest.py

# Install jq tool -> JSON parsing tool
apt-get update -y
apt-get install jq -y


# Wait 5 minutes & restart Wazuh
echo "sleeping 30 seconds"
sleep 30
cd /opt/applic/wazuh-docker
docker compose restart

# To open the dashboard from the host over the jump host
apt-get install xdg-utils -y
apt-get install firefox -y

# Install Wazuh Agent on Ubuntu Server
curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | apt-key add -
echo "deb https://packages.wazuh.com/4.x/apt/ stable main" | tee -a /etc/apt/sources.list.d/wazuh.list
apt-get update -y
apt-get install wazuh-agent -y

WAZUH_MANAGER="${ubuntu1_server_ip}" WAZUH_REGISTRATION_SERVER="${ubuntu1_server_ip}" apt-get install wazuh-agent -y

cd /var/ossec/etc/
sed -i "s/MANAGER_IP/${ubuntu1_server_ip}/" ossec.conf

systemctl enable wazuh-agent
systemctl start wazuh-agent


# Send cert to Windows Client
cd /opt/applic/soc_config/traefik/certs/
smbclient -U "${admin_username}%${admin_password}" //10.0.1.10/c$ -c 'cd ./ ; put cert.crt'

echo "finished"


