# launch one spot instance which serves both manager & worker roles for miniwdl swarm, with
# attached FSx for Lustre file system that also handles I/O with an associated S3 bucket.

provider "aws" {
  region = var.region
}

module "common" {
  source                               = "../modules/common"
  name_tag_prefix                      = var.name_tag_prefix
  owner_tag                            = var.owner_tag
  availability_zone                    = var.availability_zone
  public_key_path                      = var.public_key_path
  lustre_GiB                           = var.lustre_GiB
  s3bucket                             = var.s3bucket
  inputs_prefix                        = var.inputs_prefix
  outputs_prefix                       = var.outputs_prefix
  lustre_weekly_maintenance_start_time = var.lustre_weekly_maintenance_start_time
}

resource "aws_spot_instance_request" "monolith" {
  spot_type              = "persistent"
  wait_for_fulfillment   = true
  ami                    = module.common.ubuntu_ami_id
  instance_type          = var.instance_type
  subnet_id              = module.common.subnet_id
  vpc_security_group_ids = [module.common.sg_mosh_id, module.common.sg_lustre_id]
  key_name               = module.common.ec2_key_name

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
    # wait for ssh availability
    inline = [
      "sudo apt-get -qq update",
    ]

    connection {
      type = "ssh"
      user = "ubuntu"
      host = self.public_ip
    }
  }

  provisioner "local-exec" {
    # upload ansible playbooks
    command = "ssh-keyscan ${self.public_ip} >> ~/.ssh/known_hosts && scp -r ${var.public_key_path} ${path.module}/../../../ansible ubuntu@${self.public_ip}:~/"
  }

  provisioner "remote-exec" {
    # run ansible playbook
    inline = [
      "sudo add-apt-repository --yes universe",
      "sudo apt-add-repository --yes --update ppa:ansible/ansible",
      "sudo apt-get -qq install -y python3-pip ansible",
      "ansible-playbook --connection=local -i 'localhost,'  --extra-vars 'ansible_python_interpreter=auto public_key_path=~/${basename(var.public_key_path)} lustre_dns_name=${module.common.lustre_dns_name} s3_export_path=s3://${var.s3bucket}/${var.outputs_prefix} miniwdl_branch=${var.miniwdl_branch}' ~/ansible/aws_monolith.yml"
    ]

    connection {
      type = "ssh"
      user = "ubuntu"
      host = self.public_ip
    }
  }

  provisioner "remote-exec" {
    # reboot
    inline     = ["sudo reboot"]
    on_failure = continue

    connection {
      type = "ssh"
      user = "wdler"
      host = self.public_ip
    }
  }

  provisioner "local-exec" {
    command = "sleep 30"
  }

  provisioner "remote-exec" {
    inline = [
      # test firewall survived reboot
      "if docker run --rm -it alpine:3 wget -qO - http://169.254.169.254 ; then exit 1; fi",
      # miniwdl self-test
      "miniwdl run_self_test --dir /mnt/shared/runs"
    ]

    connection {
      type = "ssh"
      user = "wdler"
      host = self.public_ip
    }
  }
}
