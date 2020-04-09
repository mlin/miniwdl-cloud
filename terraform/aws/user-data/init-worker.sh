#!/bin/bash
set -euxo pipefail

# join swarm
docker swarm join \
    --advertise-addr "$(curl http://169.254.169.254/latest/meta-data/local-ipv4)" \
    --token "$(cat /root/swarm_token)" \
    "$(cat /mnt/shared/.swarm/manager)"
rm -f /mnt/shared/.swarm/token

# enable swarm-heartbeat.sh cron job
cat << 'EOF' > /root/swarm_heartbeat.sh
#!/bin/bash

# Custom swarm heartbeat cron job: touch sentinel files on the shared file system, whose timestamps
# then indicate various conditions of the worker node:
# - alive
# - joined to the swarm
# - has running docker containers
# Querying dockerd for this also has the side-effect of nudging it to rejoin the swarm on reboot.

set -euxo pipefail

self="/mnt/shared/.swarm/workers/$(hostname)"
mkdir -p "${self}"

touch "${self}"
touch "${self}/alive"

if [[ ! -f ${self}/in-swarm ]] || [ "$(docker info --format '{{ json .Swarm.LocalNodeState }}')" == '"active"' ]; then
    touch "${self}/in-swarm"
fi

if [[ ! -f ${self}/running-containers ]] || [ -n "$(docker ps -q)" ]; then
    touch "${self}/running-containers"
fi
EOF
chmod +x /root/swarm_heartbeat.sh

echo "* * * * * /root/swarm_heartbeat.sh" | tee /etc/cron.d/swarm_heartbeat
service cron reload
