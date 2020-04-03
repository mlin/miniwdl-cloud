#!/bin/bash
# Verify that tasks running on the swarm are blocked from:
# - EC2 instance metadata service
# - Swarm manager
# - FSx Lustre endpoint
# - FSx Lustre ioctl's
set -euxo pipefail

cat << "EOF" > ~/test_containment.wdl
version 1.0

workflow test_containment {
  call firewall
  call lustre_ioctl
}

task firewall {
  # ensure container cannot reach sensitive endpoints
  input {
    Array[String] blocklist
  }
  command <<<
    set -exo pipefail
    apt-get -qq update
    apt-get install -y netcat

    # positive control
    nc -zvw 2 www.amazon.com 443

    # proceed to test each endpoint
    while IFS=: read addr port; do
      if nc -zvw 2 "$addr" "$port"; then
        exit 2
      fi
    done < "~{write_lines(blocklist)}"
  >>>
  runtime {
    docker: "ubuntu:18.04"
  }
}

task lustre_ioctl {
  # ensure container cannot issue exotic Lustre ioctl's
  command <<<
    set -euxo pipefail
    apt-get -qq update
    apt-get install -y add-apt-key wget
    wget -O - https://fsx-lustre-client-repo-public-keys.s3.amazonaws.com/fsx-ubuntu-public-key.asc | apt-key add -
    echo "deb https://fsx-lustre-client-repo.s3.amazonaws.com/ubuntu bionic main" > /etc/apt/sources.list.d/fsxlustreclientrepo.list
    apt-get -qq update
    apt-get install -y lustre-utils

    echo p0wned > test.txt
    if lfs hsm_archive test.txt; then
      exit 1
    fi
  >>>
  runtime {
    docker: "ubuntu:18.04"
  }
}
EOF
miniwdl run ~/test_containment.wdl \
  firewall.blocklist="$(df | grep /mnt/shared | cut -f1 -d@):988" \
  firewall.blocklist=10.0.1.1:2377 \
  firewall.blocklist=10.0.1.1:7946 \
  firewall.blocklist=169.254.169.254:80 \
  --verbose --dir /mnt/shared
