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
  user_data_base64       = filebase64("${path.module}/../user-data/init.sh")

  root_block_device {
    volume_size = 40
  }

  tags = {
    Name  = "${var.name_tag_prefix}_manager"
    owner = var.owner_tag
  }
}

resource "aws_eip" "manager_eip" {
  vpc                       = true
  instance                  = aws_instance.manager.id
  associate_with_private_ip = "10.0.1.1"

  provisioner "remote-exec" {
    # no-op remote-exec to wait for manager to be reachable on its EIP
    inline = ["date"]

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file(var.private_key_path)
      host        = self.public_ip
    }
  }

  provisioner "local-exec" {
    command = "ssh-keyscan ${self.public_ip} >> ~/.ssh/known_hosts"
  }

  provisioner "local-exec" {
    command     = "ansible-playbook -u ubuntu -i '${self.public_ip},' --private-key ${var.private_key_path} --extra-vars 'private_ip=${self.private_ip} public_key_path=${var.public_key_path} lustre_dns_name=${module.common.lustre_dns_name} miniwdl_branch=${var.miniwdl_branch}' aws_manager.yml"
    working_dir = "${path.module}/../../../ansible"
  }
}

resource "aws_instance" "worker_template" {
  ami                    = module.common.ubuntu_ami_id
  instance_type          = var.manager_instance_type
  subnet_id              = module.common.subnet_id
  vpc_security_group_ids = [module.common.sg_lustre_id, module.common.sg_mosh_id]
  key_name               = module.common.ec2_key_name

  root_block_device {
    volume_size = 10
  }

  tags = {
    Name  = "${var.name_tag_prefix}_worker_template"
    owner = var.owner_tag
  }

  provisioner "remote-exec" {
    # no-op remote-exec to wait for host to come up before the following local-exec
    inline = ["date"]

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file(var.private_key_path)
      host        = self.public_ip
    }
  }

  provisioner "local-exec" {
    command = "ssh-keyscan ${self.public_ip} >> ~/.ssh/known_hosts"
  }

  provisioner "local-exec" {
    command     = "ansible-playbook -u ubuntu -i '${self.public_ip},' --private-key ${var.private_key_path} --extra-vars 'private_ip=${self.private_ip} public_key_path=${var.public_key_path} lustre_dns_name=${module.common.lustre_dns_name}' aws_worker_template.yml"
    working_dir = "${path.module}/../../../ansible"
  }

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

data "template_cloudinit_config" "persistent_worker_data" {
  part {
    content_type = "text/x-shellscript"
    content      = file("${path.module}/../user-data/init.sh")
  }

  part {
    content_type = "text/x-shellscript"
    content      = file("${path.module}/../user-data/init-worker.sh")
  }
}

resource "aws_spot_instance_request" "persistent_worker" {
  count                  = var.persistent_worker_count
  spot_type              = "persistent"
  ami                    = aws_ami_from_instance.worker_ami.id
  instance_type          = var.worker_instance_type
  subnet_id              = module.common.subnet_id
  vpc_security_group_ids = [module.common.sg_lustre_id, aws_security_group.sg_swarm.id]
  key_name               = module.common.ec2_key_name
  user_data_base64       = data.template_cloudinit_config.persistent_worker_data.rendered

  tags = {
    Name  = "${var.name_tag_prefix}_persistent_worker"
    owner = var.owner_tag
  }
}

data "template_cloudinit_config" "burst_worker_data" {
  part {
    content_type = "text/x-shellscript"
    content      = file("${path.module}/../user-data/init.sh")
  }

  part {
    content_type = "text/x-shellscript"
    content      = file("${path.module}/../user-data/init-worker.sh")
  }

  part {
    content_type = "text/x-shellscript"
    content      = file("${path.module}/../user-data/init-worker-burst.sh")
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
  user_data_base64       = data.template_cloudinit_config.burst_worker_data.rendered

  tags = {
    Name  = "${var.name_tag_prefix}_burst_worker"
    owner = var.owner_tag
  }
}
