#!/bin/bash
# custom swarm heartbeat cron job: touch a shared file if the node is an active swarm worker.
# this also has the side-effect of nudging dockerd to rejoin swarm on reboot.
set -euxo pipefail

if [ "$(docker info --format '{{ json .Swarm.LocalNodeState }}')" == '"active"' ]; then
    touch "/mnt/shared/swarm/workers/$(hostname)"
fi
