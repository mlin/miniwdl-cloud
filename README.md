# miniwdl-cloud

Orchestrate a cloud fleet to run [WDL](https://openwdl.org/) workflows using [miniwdl](https://github.com/chanzuckerberg/miniwdl) and [Docker Swarm mode](https://docs.docker.com/engine/swarm/). This is for advanced operators who are comfortable with provisioning infrastructure using [Terraform](https://www.terraform.io/) and [Ansible](https://www.ansible.com/) in their own cloud account, and then SSHing into it to invoke `miniwdl run`.

AWS is targeted initially, and we'd love help with other clouds!

## Overview of moving parts (AWS)

*diagram goes here*

**Compute:**
* Manager instance (small, on-demand) hosts user SSH session, `miniwdl run`, and Docker Swarm manager
* Worker instances (large, spot) host WDL task containers, scheduled by miniwdl via Docker Swarm
* Docker Swarm multiplexes WDL tasks onto workers based on their CPU/memory requirements
* Scale worker fleet as needed with `terraform apply ... -var=worker_count=N`
* VPC exposes only the the manager's SSH (and [mosh](https://mosh.org/)) to remote access

**Storage:**
* All instances mount a [FSx for Lustre](https://aws.amazon.com/fsx/lustre/) shared file system
* WDL tasks read inputs from, and write outputs to, this shared file system
* [FSx can](https://docs.aws.amazon.com/fsx/latest/LustreGuide/fsx-data-repositories.html) expose S3 objects as input files & write output files back
* Workers use [instance store](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/InstanceStorage.html) for Docker images & container scratch space

## Quick start

Requires: 
* [terraform](https://www.terraform.io/downloads.html)
* [ansible](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html)
* [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html), configured with [credentials](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-files.html) and, if applicable, [role](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-role.html)
* [mosh](https://mosh.org/#getting) (recommended to improve SSH experience)
* your SSH key in `~/.ssh/id_rsa[.pub]`

```
terraform init terraform/aws/swarm
terraform apply \
    -var=owner_tag=YOUR_NAME \   # Owner tag set on each AWS resource
    -var=s3bucket=YOUR_BUCKET \  # name of S3 bucket to associate with FSx Lustre
    terraform/aws/swarm          # see optional variables in terraform/aws/swarm/variables.tf

mosh wdler@$(terraform output manager_ip)

miniwdl run_self_test --dir /mnt/shared/test
```

Overview of Terraform-automated launch sequence:

1. Create VPC & firewalls
2. Create shared file system
3. Launch manager instance and provision with Ansible roles (install miniwdl + create swarm)
4. Launch worker template instance and provision with Ansible roles (poise to join swarm on boot)
5. Create AMI from stopped worker template instance
6. Issue worker spot instance requests using AMI

This typically takes about 10 minutes.
