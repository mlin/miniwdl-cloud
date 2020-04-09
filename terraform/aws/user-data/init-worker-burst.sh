#!/bin/bash
# runs on first boot of a "burst" worker
set -euxo pipefail

# worker "apoptosis" cron job: self-terminate after 30min idle; determined by the running_containers
# sentinel file (maintained by swarm_heartbeat in init-worker.sh) hasn't been touched in 30min.
cat << 'EOF' > /root/worker_apoptosis.sh
#!/bin/bash
set -euxo pipefail

self="/mnt/shared/.swarm/workers/$(hostname)"
if [[ -n $(find "${self}/running_containers" -mmin +30) ]]; then
    shutdown -h now "shutdown initiated by worker_apoptosis.sh"
fi
EOF
chmod +x /root/worker_apoptosis.sh

echo "* * * * * root /root/worker_apoptosis.sh" > /etc/cron.d/worker_apoptosis
service cron reload
