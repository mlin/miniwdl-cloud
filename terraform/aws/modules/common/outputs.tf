output "vpc_id" {
  value       = aws_vpc.vpc.id
  description = "VPC ID"
}

output "vpc_cidr_block" {
  value       = aws_vpc.vpc.cidr_block
  description = "VPC CIDR block"
}

output "subnet_id" {
  value       = aws_subnet.subnet_public.id
  description = "subnet ID"
}

output "ubuntu_ami_id" {
  value = data.aws_ami.ubuntu_ami.id
}

output "sg_mosh_id" {
  value       = aws_security_group.sg_mosh.id
  description = "Internet-accessible SSH/mosh security group ID"
}

output "sg_lustre_id" {
  value       = aws_security_group.sg_lustre.id
  description = "internal Lustre security group ID"
}

output "ec2_key_name" {
  value = aws_key_pair.ec2key.key_name
}

output "lustre_dns_name" {
  value       = aws_fsx_lustre_file_system.lustre.dns_name
  description = "internal Lustre DNS name"
}

output "profile_name" {
  value       = aws_iam_instance_profile.profile.name
  description = "instance profile with r/w access to s3bucket"
}