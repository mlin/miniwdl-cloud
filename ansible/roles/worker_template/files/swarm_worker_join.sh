#!/bin/bash
# Runs on first boot of a swarm worker (invoked by Terraform-managed instance user data). Joins the
# swarm (retrying for 5 minutes) using token written into the AMI at /root/swarm_worker_token

join_status=42
for tries in $(seq 30); do
    docker swarm join \
        --advertise-addr "$(curl -Ss http://169.254.169.254/latest/meta-data/local-ipv4)" \
        --token "$(cat /root/swarm_worker_token)" "10.0.1.1:2377" && join_status=$? || join_status=$?
    if (( join_status == 0 )); then
        rm /root/swarm_worker_token
        exit 0
    fi
    sleep 10
done
exit $join_status
