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
  description = "Path to public key for SSH from this PC to cloud instance; corresponding private key must be usable noninteractively e.g. through ssh-agent"
  default     = "~/.ssh/id_rsa.pub"
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
  description = "List existing S3 objects in the Lustre file system only if they have this key prefix (default: expose all existing objects in bucket)"
  default     = ""
}
variable "outputs_prefix" {
  description = "Apply this key prefix to Lustre file paths written back to S3 (default: files may be written anywhere in bucket)"
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
