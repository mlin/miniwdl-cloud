# miniwdl swarm with one (small, on-demand) manager node and several (powerful, spot) worker nodes.
# Operator SSH into the manager node and use `miniwdl run` to schedule WDL tasks on the workers via
# Docker Swarm. A shared FSx for Lustre file system provides the I/O bus for workflows, including
# reading inputs from & writing outputs to an associated S3 bucket.

provider "aws" {
  region = var.region
}

provider "template" {
}

module "common" {
  source                               = "../modules/common"
  name_tag_prefix                      = var.name_tag_prefix
  owner_tag                            = var.owner_tag
  availability_zone                    = var.availability_zone
  public_key_path                      = var.public_key_path
  private_key_path                     = var.private_key_path
  lustre_GiB                           = var.lustre_GiB
  s3bucket                             = var.s3bucket
  inputs_prefix                        = var.inputs_prefix
  outputs_prefix                       = var.outputs_prefix
  lustre_weekly_maintenance_start_time = var.lustre_weekly_maintenance_start_time
}

# security groups for internal swarm coordination
resource "aws_security_group" "sg_swarm_manager" {
  name   = "${var.name_tag_prefix}_sg_swarm_manager"
  vpc_id = module.common.vpc_id
  ingress {
    from_port   = 2377
    to_port     = 2377
    protocol    = "tcp"
    cidr_blocks = [module.common.vpc_cidr_block]
  }
  tags = {
    Name  = "${var.name_tag_prefix}_sg_swarm_manager"
    owner = var.owner_tag
  }
}

resource "aws_security_group" "sg_swarm" {
  name   = "${var.name_tag_prefix}_sg_swarm"
  vpc_id = module.common.vpc_id
  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.sg_swarm_manager.id]
  }
  ingress {
    from_port   = 7946
    to_port     = 7946
    protocol    = "tcp"
    cidr_blocks = [module.common.vpc_cidr_block]
  }
  ingress {
    from_port   = 7946
    to_port     = 7946
    protocol    = "udp"
    cidr_blocks = [module.common.vpc_cidr_block]
  }
  ingress {
    from_port   = 4789
    to_port     = 4789
    protocol    = "udp"
    cidr_blocks = [module.common.vpc_cidr_block]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name  = "${var.name_tag_prefix}_sg_swarm"
    owner = var.owner_tag
  }
}

resource "aws_instance" "manager" {
  ami                    = module.common.ubuntu_ami_id
  instance_type          = var.manager_instance_type
  private_ip             = "10.0.1.1"
  subnet_id              = module.common.subnet_id
  vpc_security_group_ids = [module.common.sg_mosh_id, module.common.sg_lustre_id, aws_security_group.sg_swarm_manager.id, aws_security_group.sg_swarm.id]
  key_name               = module.common.ec2_key_name

  root_block_device {
    volume_size = 40
  }

  tags = {
    Name  = "${var.name_tag_prefix}_manager"
    owner = var.owner_tag
  }

  # wait for ssh availability
  provisioner "remote-exec" {
    inline = [
      "sudo mkdir /var/provision",
      "sudo chown -R ubuntu /var/provision"
    ]

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file(var.private_key_path)
      host        = self.public_ip
    }
  }

  # upload ansible playbooks
  provisioner "local-exec" {
    command = "ssh-keyscan ${self.public_ip} >> ~/.ssh/known_hosts && scp -r ${var.public_key_path} ${path.module}/../../../ansible ubuntu@${self.public_ip}:/var/provision"
  }

  # run ansible playbook
  provisioner "remote-exec" {
    inline = [
      "sudo chmod -R a+r /var/provision",
      "sudo add-apt-repository --yes universe",
      "sudo apt-add-repository --yes --update ppa:ansible/ansible",
      "sudo apt-get -qq install -y python3-pip ansible",
      "ansible-playbook --connection=local -i 'localhost,'  --extra-vars 'ansible_python_interpreter=auto public_key_path=/var/provision/${basename(var.public_key_path)} lustre_dns_name=${module.common.lustre_dns_name} miniwdl_branch=${var.miniwdl_branch}' /var/provision/ansible/aws_manager.yml"
    ]

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file(var.private_key_path)
      host        = self.public_ip
    }
  }

  # download public SSH key we'll use to jump from manager to workers (generated in manager role)
  provisioner "local-exec" {
    command = "scp wdler@${self.public_ip}:~/.ssh/id_rsa.pub ${path.cwd}/jump.id_rsa.pub.${self.id} && chmod ug+rw ${path.cwd}/jump.id_rsa.pub.${self.id}"
  }

  # reboot to ensure apt upgrades & persistent firewall are in effect
  provisioner "remote-exec" {
    # reboot
    inline     = ["sudo reboot"]
    on_failure = continue

    connection {
      type        = "ssh"
      user        = "wdler"
      private_key = file(var.private_key_path)
      host        = self.public_ip
    }
  }
}

data "local_file" "jump_ssh_public_key" {
  filename = "${path.cwd}/jump.id_rsa.pub.${aws_instance.manager.id}"
}

# worker tempate instance: will be provisioned & then snapshotted to create worker AMI
resource "aws_instance" "worker_template" {
  ami                    = module.common.ubuntu_ami_id
  instance_type          = var.manager_instance_type
  subnet_id              = module.common.subnet_id
  vpc_security_group_ids = [module.common.sg_lustre_id, aws_security_group.sg_swarm.id]
  key_name               = module.common.ec2_key_name
  # we've launched the instance using the same EC2 key pair generated from localhost
  # ~/.ssh/id_rsa.pub, but the VPC intentionally makes the template instance unreachable from
  # localhost. Instead, use cloud-init user data to add the jump SSH key:
  user_data = <<-EOF
  #cloud-config
  ssh_authorized_keys:
    - ${data.local_file.jump_ssh_public_key.content}
  EOF

  root_block_device {
    volume_size = 10
  }

  tags = {
    Name  = "${var.name_tag_prefix}_worker_template"
    owner = var.owner_tag
  }

  # wait for ssh availability (jumping via manager)
  provisioner "remote-exec" {
    inline = ["while ! ssh -o StrictHostKeyChecking=no ubuntu@${self.private_ip} whoami ; do sleep 3; done"]

    connection {
      type        = "ssh"
      user        = "wdler"
      private_key = file(var.private_key_path)
      host        = aws_instance.manager.public_ip
    }
  }

  # run ansible playbooks via jump ssh
  provisioner "remote-exec" {
    inline = [
      "ansible-playbook -u ubuntu -i '${self.private_ip},' --extra-vars 'ansible_python_interpreter=auto lustre_dns_name=${module.common.lustre_dns_name}' /var/provision/ansible/aws_worker_template.yml"
    ]

    connection {
      type        = "ssh"
      user        = "wdler"
      private_key = file(var.private_key_path)
      host        = aws_instance.manager.public_ip
    }
  }

  # stop the template instance to prepare for snapshotting (and stay stopped afterwards)
  provisioner "local-exec" {
    command = "aws ec2 stop-instances --region ${var.region} --instance-id ${self.id} && aws ec2 wait instance-stopped --region ${var.region} --instance-ids ${self.id}"
  }
}

resource "aws_ami_from_instance" "worker_ami" {
  name               = "${var.name_tag_prefix}_worker_ami"
  source_instance_id = aws_instance.worker_template.id

  tags = {
    Name  = "${var.name_tag_prefix}_worker_ami"
    owner = var.owner_tag
  }
}

# worker instances launched using worker AMI

resource "aws_spot_instance_request" "persistent_worker" {
  count                  = var.worker_count
  spot_type              = "persistent"
  ami                    = aws_ami_from_instance.worker_ami.id
  instance_type          = var.worker_instance_type
  subnet_id              = module.common.subnet_id
  vpc_security_group_ids = [module.common.sg_lustre_id, aws_security_group.sg_swarm.id]
  key_name               = module.common.ec2_key_name
  user_data              = <<-EOF
  #!/bin/bash
  /root/scratch-docker.sh
  touch /var/local/swarm_worker  # signals swarm_heartbeat cron job
  /root/swarm_worker_join.sh
  EOF

  tags = {
    Name  = "${var.name_tag_prefix}_persistent_worker"
    owner = var.owner_tag
  }
}

resource "aws_spot_instance_request" "burst_worker" {
  count                  = var.burst_worker_count
  spot_type              = "one-time"
  ami                    = aws_ami_from_instance.worker_ami.id
  instance_type          = var.worker_instance_type
  subnet_id              = module.common.subnet_id
  vpc_security_group_ids = [module.common.sg_lustre_id, aws_security_group.sg_swarm.id]
  key_name               = module.common.ec2_key_name
  user_data              = <<-EOF
  #!/bin/bash
  /root/scratch-docker.sh
  touch /var/local/swarm_worker /var/local/swarm_worker_burst  # signals swarm_heartbeat cron job
  /root/swarm_worker_join.sh
  EOF

  tags = {
    Name  = "${var.name_tag_prefix}_burst_worker"
    owner = var.owner_tag
  }
}
