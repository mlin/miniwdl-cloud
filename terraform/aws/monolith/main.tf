provider "aws" {
  region = var.region
}

module "common" {
  source            = "../modules/common"
  name_tag_prefix   = var.name_tag_prefix
  owner_tag         = var.owner_tag
  availability_zone = var.availability_zone
  public_key_path   = var.public_key_path
  private_key_path  = var.private_key_path
  lustre_GiB        = var.lustre_GiB
  s3bucket          = var.s3bucket
  inputs_prefix     = var.inputs_prefix
  outputs_prefix    = var.outputs_prefix
}

resource "aws_spot_instance_request" "monolith" {
  spot_type              = "one-time"
  wait_for_fulfillment   = true
  ami                    = module.common.ubuntu_ami_id
  instance_type          = var.instance_type
  subnet_id              = module.common.subnet_id
  vpc_security_group_ids = [module.common.sg_mosh_id, module.common.sg_lustre_id]
  key_name               = module.common.ec2_key_name
  user_data_base64       = filebase64("${path.module}/../user-data/init.sh")

  root_block_device {
    volume_size = 40
  }

  tags = {
    Name  = "${var.name_tag_prefix}_monolith"
    owner = var.owner_tag
  }

  timeouts {
    create = "60m"
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
    command     = "ansible-playbook -u ubuntu -i '${self.public_ip},' --private-key ${var.private_key_path} --extra-vars 'public_key_path=${var.public_key_path} lustre_dns_name=${module.common.lustre_dns_name} miniwdl_branch=${var.miniwdl_branch}' aws_monolith.yml"
    working_dir = "${path.module}/../../../ansible"
  }
}
