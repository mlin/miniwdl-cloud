#!/bin/bash
# Assemble an EC2 instance's instance storage volumes into a RAID0 array and mount it to
#     /mnt/scratch
# when deployed as user-data, the script's log goes to /var/log/cloud-init-output.log
# refs:
# https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ssd-instance-store.html
# https://github.com/kislyuk/aegea/blob/master/aegea/rootfs.skel/usr/bin/aegea-format-ephemeral-storage

set -euxo pipefail
shopt -s nullglob

if grep /dev/md0 <(df) ; then
    exit 0
fi

devices=(/dev/xvd[b-m] /dev/disk/by-id/nvme-Amazon_EC2_NVMe_Instance_Storage_AWS?????????????????)
num_devices="${#devices[@]}"
if (( num_devices > 0 )); then
    mdadm --create /dev/md0 --force --auto=yes --level=0 --chunk=256 --raid-devices=${num_devices} ${devices[@]}
    mkfs.xfs -f /dev/md0
    mkdir -p /mnt/scratch
    mount -o defaults,noatime,largeio,logbsize=256k -t xfs /dev/md0 /mnt/scratch
    echo UUID=$(blkid -s UUID -o value /dev/md0) /mnt/scratch xfs defaults,noatime,largeio,logbsize=256k 0 2 >> /etc/fstab
    update-initramfs -u
fi
mkdir -p /mnt/scratch/tmp
chown 1337:1337 /mnt/scratch /mnt/scratch/tmp

# Move docker storage onto /mnt/scratch
systemctl stop docker || true
if [ -d /var/lib/docker ] && [ ! -L /var/lib/docker ]; then
    mv /var/lib/docker /mnt/scratch
fi
mkdir -p /mnt/scratch/docker
ln -s /mnt/scratch/docker /var/lib/docker
systemctl restart docker || true

