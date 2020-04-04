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
  description = "FSx for Lustre shared scratch capacity in GiB (multiple of 1200)"
  default     = 1200
}
variable "lustre_weekly_maintenance_start_time" {
  description = "weekly UTC start time of FSX for Lustre 30-minute maintenance windows (%u:%H:%M). Consider setting to: date --date @$((`date +%s` - 1860)) -u +%u:%H:%M"
  default     = "1:00:00"
}
variable "s3bucket" {
  description = "Name of S3 bucket (in the desired region) to be linked to the Lustre scratch space"
}
variable "inputs_prefix" {
  description = "S3 key prefix under which inputs may be read (with trailing slash, without leading slash)"
  default = ""
}
variable "outputs_prefix" {
  description = "S3 key prefix under which outputs may be written (with trailing slash, without leading slash)"
  default     = ""
}
variable "instance_type" {
  description = "EC2 instance type (should have NVMe instance store volumes)"
  default     = "m5d.4xlarge"
}
variable "miniwdl_branch" {
  description = "branch of chanzuckerberg/miniwdl to install on manager"
  default     = "release"
}
