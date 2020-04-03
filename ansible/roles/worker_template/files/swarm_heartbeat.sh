#!/bin/bash
# custom swarm heartbeat cron job: touch sentinel files on the shared file system, whose timestamps
# then indicate various conditions of the worker node:
# - alive
# - joined to the swarm
# - has running docker containers
# Querying dockerd for this also has the side-effect of nudging it to rejoin the swarm on reboot.
set -euxo pipefail

self="/mnt/shared/swarm/workers/$(hostname)"
mkdir -p "${self}"

touch "${self}/alive"

if [ "$(docker info --format '{{ json .Swarm.LocalNodeState }}')" == '"active"' ]; then
    touch "${self}/in-swarm"
fi

if [ -n "$(docker ps -q)" ]; then
    touch "${self}/running-containers"
fi

# future idea -- shutdown if running-containers is >15m old and either
# - a sentinel file /mnt/shared/swarm/QUIESCE exists; or
# - in-swarm is also >15m old
