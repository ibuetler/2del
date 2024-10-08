#!/bin/bash
admin_username=lab_admin
admin_password=WohPaejie4
hostname=ivan
tooldir=/home/lab_admin/tooldir
ubuntu1_server_ip="10.0.1.16"

set -e

# Send cert to Windows Client
cd /opt/applic/soc_config/traefik/certs/
smbclient -U "${admin_username}%${admin_password}" //10.0.1.16/c$ -c 'cd ./ ; put cert.crt'

echo "finished"


