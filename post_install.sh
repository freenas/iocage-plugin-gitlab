#!/bin/sh

# Enable the service
sysrc -f /etc/rc.conf gitlab_enable=YES
sysrc -f /etc/rc.conf gitlab_pages_enable="YES"
sysrc -f /etc/rc.conf postgresql_enable="YES"
sysrc -f /etc/rc.conf redis_enable=YES
sysrc -f /etc/rc.conf nginx_enable=YES

# Start the service
service postgresql initdb
service postgresql start

USER="git"
DB="gitlabhq_production"

# Save the config values
echo "$DB" > /root/dbname
echo "$USER" > /root/dbuser
export LC_ALL=C
cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1 > /root/dbpassword
PASS=`cat /root/dbpassword`

# create user git
psql -d template1 -U pgsql -c "CREATE USER ${USER} CREATEDB SUPERUSER;"

# Create the GitLab production database & grant all privileges on database
psql -d template1 -U pgsql -c "CREATE DATABASE ${DB} OWNER ${USER};"

# Set a password on the postgres account
psql -d template1 -U pgsql -c "ALTER USER ${USER} WITH PASSWORD '${PASS}';"

# Connect as superuser to gitlab db and enable pg_trgm extension
psql -U pgsql -d ${DB} -c "CREATE EXTENSION IF NOT EXISTS pg_trgm;"

# Fix permission for postgres 
echo "listen_addresses = '*'" >> /usr/local/pgsql/data/postgresql.conf
echo "host  all  all 0.0.0.0/0 md5" >> /usr/local/pgsql/data/pg_hba.conf

# Restart postgresql after config change
service postgresql restart

# Enable Redis socket
echo 'unixsocket /var/run/redis/redis.sock' >> /usr/local/etc/redis.conf

# Grant permission to the socket to all members of the redis group
echo 'unixsocketperm 770' >> /usr/local/etc/redis.conf

# Add git user to redis group
service redis start
pw groupmod redis -m git

# gitlab *really* wants things in /usr/home
mkdir -p /usr/home/git

# Set git users home to /home/git
pw usermod git -d /usr/home/git

# Set the hostname for gitlab instance
if [ -n "$IOCAGE_PLUGIN_IP" ] ; then
  sed -i '' "s|host: localhost|host: ${IOCAGE_PLUGIN_IP}|g" /usr/local/www/gitlab/config/gitlab.yml
fi

# Set db password for gitlab
sed -i '' "s|secure password|${PASS}|g" /usr/local/www/gitlab/config/database.yml

# Set some permissions for git user
chown -R git:git /usr/local/share/gitlab-shell
chown -R git:git /usr/local/www/gitlab

# remove the old Gemfile.lock to avoid problems with new gems
rm Gemfile.lock

# Run database migrations
su -l git -c "cd /usr/local/www/gitlab && rake gitlab:setup RAILS_ENV=production"

# Compile GetText PO files
su -l git -c "cd /usr/local/www/gitlab && rake gettext:compile RAILS_ENV=production"

# Update node dependencies and recompile assets
su -l git -c "cd /usr/local/www/gitlab && rake yarn:install gitlab:assets:clean gitlab:assets:compile RAILS_ENV=production NODE_ENV=production"

# Clean up cache
su -l git -c "cd /usr/local/www/gitlab && rake cache:clear RAILS_ENV=production"

# Enable push options
su -l git -c "git config --global receive.advertisePushOptions true"

# Configure Git global settings for git user
# 'autocrlf' is needed for the web editor
su -l git -c "git config --global core.autocrlf input"

# Disable 'git gc --auto' because GitLab already runs 'git gc' when needed
su -l git -c "git config --global gc.auto 0"

# Enable packfile bitmaps
su -l git -c "git config --global repack.writeBitmaps true"

# We need also give git permission to gitlab-shell
chown -R git:git /var/log/gitlab-shell/

echo "Starting nginx..."
service nginx start
echo "Starting gitlab..."
service gitlab start
echo "Starting gltlab pages..."
service gitlab_pages start

echo "Database Name: $DB"
echo "Database User: $USER"
echo "Database Password: $PASS"
echo "Please open the URL to set your password, Login Name is root."
