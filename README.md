# miniwdl-cloud

Orchestrate a cloud fleet to run [WDL](https://openwdl.org/) workflows using [miniwdl](https://github.com/chanzuckerberg/miniwdl) and [Docker Swarm mode](https://docs.docker.com/engine/swarm/). This is for advanced operators at ease with using [Terraform](https://www.terraform.io/) to provision infrastructure in their own cloud account, and then SSHing into it to use `miniwdl run`.

AWS is targeted initially, but we've relied on core infrastructure services that'll be portable to other clouds.

## Overview of moving parts (AWS)

*diagram goes here*

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
* [terraform](https://www.terraform.io/downloads.html)
* SSH key pair (a default one in `~/.ssh/id_rsa[.pub]` is fine)
* [mosh](https://mosh.org/#getting) (recommended to improve SSH experience)

### Configure session

In the desired terminal session, start an [SSH agent](https://www.ssh.com/ssh/agent) and add your key to it.

```
eval `ssh-agent`
ssh-add
```

If your private key isn't the default `~/.ssh/id_rsa`, then supply its path to `ssh-add`. If your private key file is password-protected, you will unlock it at this time. The Terraform deployment procedure will upload the public key to EC2, then use the SSH agent to connect to the launched servers for provisioning.

Next, set environment variables for a few Terraform variables that won't be changing frequently:

```
# desired AWS region
export TF_VAR_region=us-west-2

# S3 bucket for input & output files (must be in the same region)
export TF_VAR_s3bucket=your-bucket-name

# prefixed to the Name tag of each AWS resource:
export TF_VAR_name_tax_prefix=my_miniwdl_cloud

# sets the 'owner' tag of all AWS resources
export TF_VAR_owner_tag=your@email.com

# if other than ~/.ssh/id_rsa.pub
# export TF_VAR_public_key_path=/path/to/ssh_key.pub
```

### Deploy infrastructure

Initialize Terraform and deploy the stack:

```
terraform init terraform/aws/swarm
terraform apply terraform/aws/swarm
```

This takes about 20 minutes, during which it:

1. Creates VPC & firewall rules
2. Creates shared file system
3. Launches manager instance & provisions it with miniwdl and Docker Swarm
4. Launches worker template instance and poises it to join the swarm on boot
5. Creates AMI from worker template instance
6. Issues worker spot instance requests using AMI

### Connect to manager node

Once the deployment is complete, start a [mosh](https://mosh.org/) SSH session with the new manager instance. 

```
mosh wdler@$(terraform output manager_ip)
```

(You might use a separate terminal window/tab for this, so that you can continue working with Terraform alongside.) This brings you into a [Byobu](https://www.byobu.org/) window for the **wdler** user.

Try a test workflow:
```
miniwdl run_self_test --dir /mnt/shared/test
```

## S3 I/O

## Scaling up & down

## Monitoring

## Limitations

## Security
