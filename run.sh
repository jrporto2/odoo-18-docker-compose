#!/bin/bash
set -x
#curl -s https://raw.githubusercontent.com/jrporto2/odoo-18-docker-compose/refs/heads/master/run.sh | sudo bash -s odoo-one 10017 20017 password
DESTINATION=$1
PORT=$2
CHAT=$3
MASTERPASSWORD=${4:-adminpasswd}
#clear directory
rm -rf $DESTINATION
# Clone Odoo directory
git clone --depth=1 https://github.com/jrporto2/odoo-18-docker-compose.git $DESTINATION
rm -rf $DESTINATION/.git
mkdir -p $DESTINATION/datadrive/odoo/{addons,etc,filestore,logsx,sessions}
mkdir -p $DESTINATION/datadrive/nginx/{certs,conf.d,logs}
mkdir -p $DESTINATION/datadrive/postgres/{db,custom-init-scripts}
mkdir -p $DESTINATION/datadrive/pgadmin/data
# Change ownership to current user and set restrictive permissions for security
#sudo chown -R $USER:$USER $DESTINATION
sudo chown -R 101:101 $DESTINATION
sudo chmod -R 755 $DESTINATION  # Only the user has access
sudo chmod -R 755 $DESTINATION/datadrive/odoo/sessions
sudo chmod -R 755 $DESTINATION/datadrive/odoo/filestore
sudo scp /etc/ssl/certs/origin_certificate.pem $DESTINATION/datadrive/nginx/certs/origin_certificate.pem
sudo scp /etc/ssl/certs/origin_private_key.pem $DESTINATION/datadrive/nginx/certs/origin_private_key.pem
sudo chmod +x $DESTINATION/entrypoint.sh
# Check if running on macOS
if [[ "$OSTYPE" == "darwin"* ]]; then
  echo "Running on macOS. Skipping inotify configuration."
else
  # System configuration
  if grep -qF "fs.inotify.max_user_watches" /etc/sysctl.conf; then
    echo $(grep -F "fs.inotify.max_user_watches" /etc/sysctl.conf)
  else
    echo "fs.inotify.max_user_watches = 524288" | sudo tee -a /etc/sysctl.conf
  fi
  sudo sysctl -p
fi
# Set ports in .env file
# Update docker-compose configuration
if [[ "$OSTYPE" == "darwin"* ]]; then
  # macOS sed syntax
  sed -i '' 's/10017/'$PORT'/g' $DESTINATION/.env
  sed -i '' 's/20017/'$CHAT'/g' $DESTINATION/.env
else
  # Linux sed syntax
  sed -i 's/10017/'$PORT'/g' $DESTINATION/.env
  sed -i 's/20017/'$CHAT'/g' $DESTINATION/.env
  sed -i 's/adminpasswd/'$MASTERPASSWORD'/g' $DESTINATION/datadrive/odoo/etc/odoo.conf 
fi

# Set file and directory permissions after installation
find $DESTINATION -type f -exec chmod 644 {} \;
find $DESTINATION -type d -exec chmod 755 {} \;
echo $DESTINATION
sudo chown -R 999:999 $DESTINATION/datadrive/postgres
sudo chown -R 999:999 $DESTINATION/datadrive/postgres/db
sudo chown -R 101:101 $DESTINATION/datadrive/odoo
sudo chown -R 5050:5050 $DESTINATION/datadrive/pgadmin
sudo chown -R 101:101 $DESTINATION/datadrive/nginx
# Run Odoo
docker compose -f $DESTINATION/docker-compose.yml up -d

echo "Odoo started at http://localhost:$PORT | Master Password: $MASTERPASSWORD | Live chat port: $CHAT"
