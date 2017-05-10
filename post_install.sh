#!/bin/sh

# Enable the service
sysrc -f /etc/rc.conf gitlab_enable=YES
sysrc -f /etc/rc.conf postgresql_enable="YES"
sysrc -f /etc/rc.conf redis_enable=YES
sysrc -f /etc/rc.conf nginx_enable=YES

# Start the service
service postgresql initdb
service postgresql start

USER="gitlab"
DB="gitlab"

# Save the config values
echo "$DB" > /root/dbname
echo "$USER" > /root/dbuser
export LC_ALL=C
cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1 > /root/dbpassword
PASS=`cat /root/dbpassword`

echo "Database Name: $DB"
echo "Database User: $USER"
echo "Database Password: $PASS"

# create user git
psql -d template1 -U pgsql -c "CREATE USER git CREATEDB SUPERUSER;"

# Create the GitLab production database & grant all privileges on database
psql -d template1 -U pgsql -c "CREATE DATABASE gitlabhq_production OWNER git;"

# Connect as superuser to gitlab db and enable pg_trgm extension
psql -U pgsql -d gitlabhq_production -c "CREATE EXTENSION IF NOT EXISTS pg_trgm;"

# Enable Redis socket
echo 'unixsocket /var/run/redis/redis.sock' >> /usr/local/etc/redis.conf

# Grant permission to the socket to all members of the redis group
echo 'unixsocketperm 770' >> /usr/local/etc/redis.conf

# Activate the changes to redis.conf
service redis start

# Add git user to redis group
pw groupmod redis -m git

service gitlab start
service nginx start
