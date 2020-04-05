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

# TODO: "burst" workers shut themselves down after 30min inactivity
# if [[ -n $(find "${self}/running_containers" -mmin +30) ]]; then
#     shutdown -h now "shutdown initiated by swarm_heartbeat.sh"
# fi
