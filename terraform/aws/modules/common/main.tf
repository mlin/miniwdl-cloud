# common infra shared by other AWS modules: VPC resources, FSx for Lustre, EC2 key pair

resource "aws_vpc" "vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name  = "${var.name_tag_prefix}_vpc"
    owner = var.owner_tag
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name  = "${var.name_tag_prefix}_igw"
    owner = var.owner_tag
  }
}

resource "aws_subnet" "subnet_public" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = "10.0.0.0/16"
  map_public_ip_on_launch = true
  availability_zone       = var.availability_zone
  tags = {
    Name  = "${var.name_tag_prefix}_subnet"
    owner = var.owner_tag
  }
}

resource "aws_route_table" "rtb_public" {
  vpc_id = aws_vpc.vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name  = "${var.name_tag_prefix}_rtb"
    owner = "${var.owner_tag}"
  }
}

resource "aws_route_table_association" "rta_subnet_public" {
  subnet_id      = aws_subnet.subnet_public.id
  route_table_id = aws_route_table.rtb_public.id
}

data "aws_ami" "ubuntu_ami" {
  most_recent = true

  # The YYYYMM pattern below should be advanced from time to time, while ensuring we get an AMI
  # kernel version that has Lustre client modules available from AWS' apt repo. See:
  #   https://docs.aws.amazon.com/fsx/latest/LustreGuide/install-lustre-client.html
  #   aws s3 cp s3://fsx-lustre-client-repo/ubuntu/dists/focal/main/binary-amd64/Packages - | grep "Package: lustre-client-modules-"
  # The Ansible playbooks do perform 'apt upgrade' after pinning the kernel version.
  #   aws ec2 describe-images --owners 099720109477 --filters 'Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-202007*'
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-202007*"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }

  owners = ["099720109477"] # Canonical
}

resource "aws_security_group" "sg_mosh" {
  name   = "${var.name_tag_prefix}_sg_mosh"
  vpc_id = aws_vpc.vpc.id
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 60000
    to_port     = 61000
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name  = "${var.name_tag_prefix}_sg_mosh"
    owner = var.owner_tag
  }
}

resource "aws_security_group" "sg_lustre" {
  name   = "${var.name_tag_prefix}_sg_lustre"
  vpc_id = aws_vpc.vpc.id
  ingress {
    from_port   = 988
    to_port     = 988
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.vpc.cidr_block]
  }
  ingress {
    from_port   = 1021
    to_port     = 1023
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.vpc.cidr_block]
  }
  tags = {
    Name  = "${var.name_tag_prefix}_sg_lustre"
    owner = var.owner_tag
  }
}

resource "aws_fsx_lustre_file_system" "lustre" {
  storage_capacity              = var.lustre_GiB
  subnet_ids                    = [aws_subnet.subnet_public.id]
  security_group_ids            = [aws_security_group.sg_lustre.id]
  import_path                   = var.inputs_prefix != "" ? "s3://${var.s3bucket}/${var.inputs_prefix}" : "s3://${var.s3bucket}"
  export_path                   = var.outputs_prefix != "" ? "s3://${var.s3bucket}/${var.outputs_prefix}" : "s3://${var.s3bucket}"
  weekly_maintenance_start_time = var.lustre_weekly_maintenance_start_time

  tags = {
    Name  = "${var.name_tag_prefix}_lustre"
    owner = var.owner_tag
  }
}

resource "aws_key_pair" "ec2key" {
  key_name   = "${var.name_tag_prefix}_key"
  public_key = file(var.public_key_path)
}

resource "aws_iam_role" "role" {
  name = "${var.name_tag_prefix}_role"

  assume_role_policy = <<-EOF
  {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Action": "sts:AssumeRole",
        "Principal": {
          "Service": "ec2.amazonaws.com"
        },
        "Effect": "Allow",
        "Sid": ""
      }
    ]
  }
  EOF

  tags = {
    Name  = "${var.name_tag_prefix}_role"
    owner = var.owner_tag
  }
}

resource "aws_iam_instance_profile" "profile" {
  name = "${var.name_tag_prefix}_profile"
  role = aws_iam_role.role.name
}

resource "aws_iam_role_policy" "policy" {
  name = "${var.name_tag_prefix}_policy"
  role = aws_iam_role.role.id

  # Allow read/write access to s3bucket, and read access to all ECR docker registries:
  policy = <<-EOF
  {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": ["s3:ListBucket"],
        "Resource": ["arn:aws:s3:::${var.s3bucket}"]
      },
      {
        "Effect": "Allow",
        "Action": [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject"
        ],
        "Resource": ["arn:aws:s3:::${var.s3bucket}/*"]
      },
      {
            "Effect": "Allow",
            "Action": [
                "ecr:GetAuthorizationToken",
                "ecr:BatchCheckLayerAvailability",
                "ecr:GetDownloadUrlForLayer",
                "ecr:GetRepositoryPolicy",
                "ecr:DescribeRepositories",
                "ecr:ListImages",
                "ecr:DescribeImages",
                "ecr:BatchGetImage",
                "ecr:GetLifecyclePolicy",
                "ecr:GetLifecyclePolicyPreview",
                "ecr:ListTagsForResource",
                "ecr:DescribeImageScanFindings"
            ],
            "Resource": "*"
        }
    ]
  }
  EOF
}