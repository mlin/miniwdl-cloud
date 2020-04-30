#!/bin/bash

# This script runs as a cron job on on worker nodes. Its responsibilities:
# 1) Touch sentinel files on the shared file system, whose timestamps then advertise our status.
# 2) Querying dockerd for this status info has the side-effect of nudging it to rejoin the swarm
#    after a reboot.
# 3) Shut down if we haven't been connected to the swarm for >=30min.
# 4) If we're a "burst" worker, then shut down if we haven't had any containers for >=30min.
# 5) If testing environment specifies, shut down based on a (biased) coinflip.

if [[ ! -f /var/local/swarm_worker ]]; then
    # That sentinel file is created by a user-data script on first boot from the worker AMI.
    # User-data setting is handled from Terraform. This switch prevents spurious entries from the
    # worker template instance when we install the cron job there.
    exit 0
fi

self="/mnt/shared/.swarm/workers/$(hostname)"
mkdir -p "$self"
rm -f "${self}/shutdown"
if [[ ! -f /var/local/swarm_worker_boot ]]; then
    cat /proc/cpuinfo > "${self}/boot"
    touch /var/local/swarm_worker_boot
fi
(uptime; free -h; df -h) > "${self}/alive"



if [[ ! -f ${self}/in-swarm ]] || [ "$(docker info --format '{{ json .Swarm.LocalNodeState }}')" == '"active"' ]; then
    touch "${self}/in-swarm"
fi
if [[ -n $(find "${self}/in-swarm" -mmin +30) ]]; then
    echo orphaned > "${self}/shutdown"
    /sbin/shutdown -h now "swarm worker orphaned >=30min"
fi



if [[ ! -f ${self}/running-containers ]] || [ -n "$(docker ps -q)" ]; then
    touch "${self}/running-containers"
fi



if [[ ! -f /var/local/swarm_worker_burst ]]; then
    # Sentinel file specifically indicating we're a "burst" worker is also created by user-data.
    exit 0
fi


if [[ -n $(find "${self}/running-containers" -mmin +30) ]]; then
    echo idle > "${self}/shutdown"
    /sbin/shutdown -h now "swarm worker idle >=30min"
fi
if [[ -f /mnt/shared/.swarm/workers/_induce_shutdown ]]; then
    p_shutdown=$(</mnt/shared/.swarm/workers/_induce_shutdown)
    p_shutdown=${p_shutdown:-1}
    q=$(( RANDOM%100 ))
    if (( q < p_shutdown )); then
        (echo induced $q "$p_shutdown" > "${self}/shutdown") || true
        /sbin/shutdown -h now "induced"
    fi
fi
