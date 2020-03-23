# miniwdl-cloud

Orchestrate a fleet of cloud instances to run [WDL](https://openwdl.org/) workflows using [miniwdl](https://github.com/chanzuckerberg/miniwdl) and [Docker Swarm mode](https://docs.docker.com/engine/swarm/). This is for advanced users comfortable with provisioning infrastructure using [Terraform](https://www.terraform.io/) and [Ansible](https://www.ansible.com/) on their own cloud account. AWS is targeted initially, and we'd love help with other clouds!

## Overview of moving parts (AWS)

*diagram goes here*

* Manager instance hosts user SSH session, `miniwdl run`, and Docker Swarm manager
* Worker spot instances host WDL task containers, scheduled by miniwdl via Docker Swarm
* Docker Swarm multiplexes WDL tasks onto workers based on resource availability
* Worker fleet size dynamically adjustable by a variable given to `terraform apply`
* All instances mount a [FSx for Lustre](https://aws.amazon.com/fsx/lustre/) shared file system
* WDL tasks read inputs from, and write outputs to, the shared file system
* [FSx can](https://docs.aws.amazon.com/fsx/latest/LustreGuide/fsx-data-repositories.html) expose S3 objects as input files & write output files back
* Everything lives in a VPC, with only the manager's SSH (and [mosh](https://mosh.org/)) externally accessible

## Quick start

Requires: 
* terraform
* ansible
* AWS CLI, configured
* mosh
* your SSH key in `~/.ssh/id_rsa[.pub]`

```
terraform init terraform/aws/swarm
terraform apply -auto-approve \
    -var=owner_tag=YOUR_NAME \
    -var=s3bucket=YOUR_BUCKET \
    terraform/aws/swarm
mosh "wdler@$(terraform output manager_ip)"
```
