variable "name_tag_prefix" {
  description = "name tag prefix"
  default     = "miniwdl_test"
}
variable "owner_tag" {
  description = "owner tag"
}
variable "region" {
  description = "AWS region"
  default     = "us-west-2"
}
variable "availability_zone" {
  description = "AWS availability zone"
  default     = "us-west-2c"
}
variable "public_key_path" {
  description = "SSH public key path"
  default     = "~/.ssh/id_rsa.pub"
}
variable "private_key_path" {
  description = "SSH private key path"
  default     = "~/.ssh/id_rsa"
}
variable "lustre_GiB" {
  description = "FSx Lustre shared scratch capacity in GiB (multiple of 1200)"
  default     = 1200
}
variable "s3bucket" {
  description = "Name of S3 bucket (in the desired region) to be linked to the Lustre scratch space"
}
variable "inputs_prefix" {
  description = "S3 key prefix under which inputs may be read (with trailing slash, without leading slash)"
  default     = ""
}
variable "outputs_prefix" {
  description = "S3 key prefix under which outputs may be written (with trailing slash, without leading slash)"
  default     = ""
}
variable "manager_instance_type" {
  description = "EC2 on-demand instance type for manager node"
  default     = "t3a.medium"
}
variable "worker_instance_type" {
  description = "EC2 spot instance type for task workers (should have NVMe instance store volumes)"
  default     = "m5d.4xlarge"
}
variable "worker_count" {
  description = "Number of worker spot instances to launch"
  default     = 2
}