#!/bin/bash
# runs on first boot of a "burst" worker
set -euxo pipefail

# worker "apoptosis" cron job: self-terminate after 30min idle, measured by mtime of the
# running_containers sentinel file (maintained by swarm_heartbeat in init-worker.sh)
cat << 'EOF' > /root/worker_apoptosis.sh
#!/bin/bash
set -euxo pipefail

self="/mnt/shared/.swarm/workers/$(hostname)"
rm -f "${self}/shutdown"
if [[ -n $(find "${self}/running_containers" -mmin +30) ]]; then
    touch "${self}/shutdown" || true
    /sbin/shutdown -h now "shutdown initiated by worker_apoptosis.sh"
fi

if [[ -f /mnt/shared/.swarm/_mock_interruption ]]; then
    p_interrupt=$(</mnt/shared/.swarm/_mock_interruption)
    p_interrupt=${p_interrupt:-1}
    q=$(( RANDOM%100 ))
    if (( q < p_interrupt )); then
        touch "${self}/shutdown"
        /sbin/shutdown -h now "worker_apoptosis.sh mock interruption"
    fi
fi
EOF
chmod +x /root/worker_apoptosis.sh

echo "* * * * * root /root/worker_apoptosis.sh" > /etc/cron.d/worker_apoptosis
service cron reload
