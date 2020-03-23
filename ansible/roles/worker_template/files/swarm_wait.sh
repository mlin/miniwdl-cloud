#!/bin/bash
set -euxo pipefail

while [ "$(docker info --format '{{ json .Swarm.LocalNodeState }}')" != '"active"' ]; do
    >&2 echo "$(date) waiting for this host to join swarm..."
    sleep 2
done
