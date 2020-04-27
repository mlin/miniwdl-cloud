# miniwdl-cloud

Orchestrate a cloud fleet to run [WDL](https://openwdl.org/) workflows using [miniwdl](https://github.com/chanzuckerberg/miniwdl) and [Docker Swarm mode](https://docs.docker.com/engine/swarm/). This is for advanced operators at ease with using [Terraform](https://www.terraform.io/) to provision infrastructure in their own cloud account, and then SSHing into it to use `miniwdl run`.

AWS is targeted initially, but we've relied on core infrastructure services that'll be portable to other clouds.

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

* [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html), configured with [credentials](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-files.html) and ([role](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-role.html) if applicable) so that commands work on the desired account without any explicit auth arguments.
* S3 bucket for input & output files, in your preferred AWS region
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

### Connect to manager node

Once the deployment is complete, start a [mosh](https://mosh.org/) SSH session with the new manager instance. 

```
mosh wdler@$(terraform output manager_ip)
```

(You might use a separate terminal window/tab for this, so that you can continue working with Terraform alongside.) This brings you into a [Byobu](https://www.byobu.org/) window for the **wdler** user.

Try a test workflow:
```
miniwdl run_self_test --dir /mnt/shared/runs
```

The task containers run on the worker spot instances, orchestrated by miniwdl & Docker Swarm from the small manager node you're logged into, all mounting `/mnt/shared` through which input/output files and logs are exchanged.

## S3 I/O

## Scaling up & down

## Monitoring

## Security

## Limitations
