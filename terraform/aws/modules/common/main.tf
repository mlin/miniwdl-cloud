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

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-bionic-18.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
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
  storage_capacity   = var.lustre_GiB
  subnet_ids         = [aws_subnet.subnet_public.id]
  security_group_ids = [aws_security_group.sg_lustre.id]
  import_path        = "s3://${var.s3bucket}/${var.inputs_prefix}"
  export_path        = "s3://${var.s3bucket}/${var.outputs_prefix}"

  tags = {
    Name  = "${var.name_tag_prefix}_lustre"
    owner = var.owner_tag
  }
}

resource "aws_key_pair" "ec2key" {
  key_name   = "${var.name_tag_prefix}_key"
  public_key = file(var.public_key_path)
}
