#!/bin/bash
# Run a lot of small jobs
set -euxo pipefail

cat << "EOF" > ~/test_stress.wdl
version 1.0

workflow stress_test {
  input {
    Int num_calls
  }
  scatter (i in range(num_calls)) {
    call stressor
  }

  call postprocessor {
    input:
    numerator = stressor.numerator,
    denominator = stressor.denominator
  }
  output {
    Float estimate = postprocessor.estimate
  }
}

task stressor {
  input {
    Int samples = 10000000
  }
  command <<<
    set -euo pipefail
    python3 -c "
    import random
    random.seed()
    inside = 0
    for _ in range(~{samples}):
      x = random.random()
      y = random.random()
      if x*x + y*y <= 1.0:
        inside += 1
    print(inside)" > numerator.txt
  >>>
  output {
    File numerator = "numerator.txt"
    File denominator = write_lines([samples])
  }
  runtime {
    cpu: 1
    docker: "continuumio/miniconda3"
  }
}

task postprocessor {
  input {
    Array[File] numerator
    Array[File] denominator
  }
  command <<<
    set -euxo pipefail
    ADDER="import sys; print(sum(int(line.strip()) for line in sys.stdin if line.strip()))"
    inside=$(python3 -c "$ADDER" < <(cat "~{write_lines(numerator)}" | xargs cat))
    N=$(python3 -c "$ADDER" < <(cat "~{write_lines(denominator)}" | xargs cat))
    python3 -c "print(4.0*float(${inside})/float(${N}))"
  >>>
  output {
    Float estimate = read_float(stdout())
  }
  runtime {
    cpu: 1
    docker: "continuumio/miniconda3"
  }
}
EOF
miniwdl check ~/test_stress.wdl

docker node ls
tree -aD /mnt/shared/.swarm

# the following sentinel file causes a 5% chance that each burst worker shuts itself down in any
# given minute (implemented in worker_heartbeat.sh)
sudo bash -c "echo 5 > /mnt/shared/.swarm/workers/_induce_shutdown"

exit_code=0
time timeout 1h miniwdl run ~/test_stress.wdl \
  num_calls=1000 stressor.samples=100000000 \
  --dir /mnt/shared/runs --verbose || exit_code=$?

docker node ls
tree -aD /mnt/shared/.swarm

exit $exit_code
