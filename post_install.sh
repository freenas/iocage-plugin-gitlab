#!/bin/sh

# Enable the service
sysrc -f /etc/rc.conf gitlab_enable=YES
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

# Enable Redis socket
echo 'unixsocket /var/run/redis/redis.sock' >> /usr/local/etc/redis.conf

# Grant permission to the socket to all members of the redis group
echo 'unixsocketperm 770' >> /usr/local/etc/redis.conf

# Add git user to redis group
service redis start
pw groupmod redis -m git

# gitlab *really* wants things in /usr/home
mv /home /usr

# Set git users home to /home/git
pw usermod git -d /usr/home/git

# Set some permissions for git user
chown -R git:git /usr/local/share/gitlab-shell
chown -R git:git /usr/local/www/gitlab

# Configure Git global settings for git user
# 'autocrlf' is needed for the web editor
git config --global core.autocrlf input

# Disable 'git gc --auto' because GitLab already runs 'git gc' when needed
git config --global gc.auto 0

# Enable packfile bitmaps
git config --global repack.writeBitmaps true

echo "Starting nginx..."
service nginx start
echo "Starting gitlab..."
service gitlab start

echo "Database Name: $DB"
echo "Database User: $USER"
echo "Database Password: $PASS"

