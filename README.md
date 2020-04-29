# miniwdl-cloud

Orchestrate a cloud fleet to run [WDL](https://openwdl.org/) workflows using [miniwdl](https://github.com/chanzuckerberg/miniwdl) and [Docker Swarm mode](https://docs.docker.com/engine/swarm/). This is for advanced operators at ease with using [Terraform](https://www.terraform.io/) to provision infrastructure in their own cloud account, and then SSHing into it to use `miniwdl run`.

AWS is targeted initially, but we've relied on core infrastructure services to preserve portability to other clouds.

## Overview of moving parts (AWS)

![architecture diagram](arch.png)

**Compute:**
* Manager instance (small, on-demand) hosts user SSH session, miniwdl, and Docker Swarm manager
* Worker instances (large, spot) host WDL task containers, scheduled by miniwdl via Docker Swarm
* Docker Swarm multiplexes WDL tasks onto workers based on their CPU/memory requirements
* Scale worker fleet as needed with `terraform apply ... -var=worker_count=N`
* VPC exposes only the the manager's SSH (and [mosh](https://mosh.org/)) to remote access

**Storage:**
* All instances mount a [FSx for Lustre](https://aws.amazon.com/fsx/lustre/) shared file system
* WDL tasks read inputs from, and write outputs to, this shared file system
* The shared file system is [linked to an S3 bucket](https://docs.aws.amazon.com/fsx/latest/LustreGuide/fsx-data-repositories.html) where input files can be read & output files written back
* Workers use [instance store](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/InstanceStorage.html) for Docker images & container scratch space

## Getting Started

Prerequisites:

* S3 bucket for input & output files, in your preferred AWS region.
  * Suggestion: create a new bucket with test inputs & use it to try out the S3 I/O functionality here, before using any important bucket.
* [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html), configured with [credentials](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-files.html) and ([role](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-role.html) if applicable) so that commands work on the desired account without any explicit auth arguments.
* [terraform](https://www.terraform.io/downloads.html)
* SSH key pair (a default one in `~/.ssh/id_rsa[.pub]` is fine)
* [mosh](https://mosh.org/#getting) (recommended to improve SSH experience)

### Prepare terminal session

Clone this repo or your preferred version/fork thereof:

```
git clone https://github.com/mlin/miniwdl-cloud.git
cd miniwdl-cloud
```

Open the [`environment`](https://github.com/mlin/miniwdl-cloud/blob/master/environment) file in your editor and customize it as needed, in particular setting the AWS region/AZ and S3 bucket name. Then,

```
source environment
```

and verify the displayed information.

### Deploy infrastructure

Initialize Terraform and deploy the stack:

```
terraform init terraform/aws/swarm
terraform apply terraform/aws/swarm
```

This takes about 20 minutes to:

1. Create VPC & firewall rules
2. Provision shared file system
3. Launch manager instance & install miniwdl and Docker Swarm
4. Launch worker template instance and configure it to join the swarm on boot
5. Snapshot VM image from worker template instance
6. Issue spot instance requests using worker VM image

### Connect to manager node and run workflows

Once the deployment is complete, start a [mosh](https://mosh.org/) SSH session with the new manager instance. 

```
mosh wdler@$(terraform output manager_ip)
```

(You might use a separate terminal window/tab for this, to continue working with Terraform alongside.) This brings you into a [Byobu](https://www.byobu.org/) window for the **wdler** user.

Try a test workflow:
```
miniwdl run_self_test --dir /mnt/shared/runs
```

The task containers run on the worker spot instances, orchestrated by miniwdl & Docker Swarm from the small manager node you're logged into, all mounting `/mnt/shared` through which input/output files and logs are exchanged.

Following the self-test, you can browse the run directory under `/mnt/shared/runs` and also find a copy of its log and output JSON in a corresponding location in your S3 bucket. (The self-test workflow doesn't output any files.)

From here, you can `miniwdl run ... --dir /mnt/shared/runs` your own WDL workflows, perhaps supplied from your PC using `scp`  or an [editor plugin](https://code.visualstudio.com/docs/remote/ssh), or downloaded using `wget` or `git` on the manager. Input files can be sourced from the linked S3 bucket (discussed next) or public URIs.

## S3 I/O

On AWS, miniwdl-cloud relies on [FSx for Lustre features](https://aws.amazon.com/fsx/lustre/features/?nc=sn&loc=2#Seamless_integration_with_your_Amazon_S3_data) handling transfers to and from the linked S3 bucket, simplifying file localization for WDL workflows.

**S3 input:** during creation of the FSx for Lustre share, it's populated with file & directory entries mirroring your S3 bucket. For example, the object `s3://your-bucket/foo/bar.txt` surfaces as `/mnt/shared/foo/bar.txt`, which `miniwdl run` can use as an input like any local file. (FSx automatically transfers the S3 data when needed; [see its docs](https://docs.aws.amazon.com/fsx/latest/LustreGuide/fsx-data-repositories.html))

**Automatic writeback of workflow outputs:** the manager configures miniwdl to write workflow outputs back to S3 via FSx. For example, if the workflow generates an output file `/mnt/shared/runs/12345_hello/output_links/result/data.txt`, it's written back to `s3://your-bucket/runs/12345_hello/output_links/result/data.txt`. It also writes the workflow log file and `outputs.s3.json`, a version of the outputs JSON with `s3://` URIs instead of local File paths.
* Only top-level run outputs are written to S3 (excluding nested call outputs that aren't output from the top-level run), while everything remains on `/mnt/shared`.
* Auto-writeback can be disabled for a run by setting `MINIWDL__FSX_TO_S3__ENABLE=false` in the environment, which can be useful for dev/test without cluttering your S3 bucket.

**Custom S3 output:** alternatively, you can instruct FSx to write arbitrary files under `/mnt/shared` to S3 by running `fsx_to_s3 {file_or_directory}`. If the default run folder organization doesn't suit you, then disable auto-writeback, populate a subdirectory tree corresponding to the desired S3 key layout, and then `fsx_to_s3` the subdirectory (e.g. `/mnt/shared/results/data.txt` to `s3://your-bucket/results/data.txt`).
* To avoid copying large files on Lustre, you can `mv` them in or create additional [hard links](https://en.wikipedia.org/wiki/Hard_link) to their existing inodes (`fsx_to_s3` won't work on symbolic links).
* Take care that it's possible to overwrite existing S3 objects when `fsx_to_s3` writes to keys derived from the Lustre file paths.
* The [`fsx_to_s3` script](https://github.com/mlin/miniwdl-cloud/blob/master/ansible/roles/aws_fsx_lustre_client/files/fsx_to_s3) awaits completion of the S3 transfers. [FSx docs](https://docs.aws.amazon.com/fsx/latest/LustreGuide/exporting-files-hsm.html) describe low-level commands available to initiate them asynchronously.

## Scaling up & down

## Monitoring

## Security

## Limitations
