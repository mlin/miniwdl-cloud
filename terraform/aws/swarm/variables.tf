variable "name_tag_prefix" {
  description = "prefixed to the Name tag of each AWS resource"
  default     = "miniwdl_test"
}
variable "owner_tag" {
  description = "owner tag (e.g. your e-mail address) to distinguish resources in a shared AWS account"
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
  description = "Path to public key for SSH from this PC to manager instance; corresponding private key must be usable noninteractively e.g. through ssh-agent"
  default     = "~/.ssh/id_rsa.pub"
}
variable "lustre_GiB" {
  description = "FSx for Lustre shared scratch capacity in GiB (multiple of 1200)"
  default     = 1200
  type        = number
}
variable "lustre_weekly_maintenance_start_time" {
  description = "weekly UTC start time of FSx for Lustre 30-minute maintenance window (%u:%H:%M). Consider setting to 6 days, 23.5 hours from now: date --date @$((`date +%s` - 1860)) -u +%u:%H:%M"
  default     = "1:00:00"
}
variable "s3bucket" {
  description = "Name of S3 bucket linked to the Lustre file system (must be in the same region)"
}
variable "inputs_prefix" {
  description = "List existing S3 objects in the Lustre file system only if they have this key prefix (default: expose all existing objects in bucket)"
  default     = ""
}
variable "outputs_prefix" {
  description = "Apply this key prefix to Lustre file paths written back to S3 (default: files may be written anywhere in bucket)"
  default     = ""
}
variable "manager_instance_type" {
  description = "EC2 on-demand instance type for manager node"
  default     = "t3a.medium"
}
variable "miniwdl_branch" {
  description = "branch of chanzuckerberg/miniwdl to install on manager"
  default     = "release"
}
variable "worker_instance_type" {
  description = "EC2 spot instance type for task workers (should have NVMe instance store volumes)"
  default     = "m5d.4xlarge"
}
variable "worker_count" {
  description = "Number of workers to launch via persistent spot instance requests"
  default     = 1
  type        = number
}
variable "burst_worker_count" {
  description = "Number of workers to launch via one-time spot instance requests (no auto-regeneration after spot interruption or 30min idle)"
  default     = 1
  type        = number
}
variable "burst_worker_idle_minutes" {
  description = "Burst workers shut themselves down after this many minutes idle"
  default     = 30
  type        = number
}
variable "worker_privileges" {
  description = "Permit tasks to assume IAM role with s3bucket read/write + ECR read-only. Use only with trusted WDL and docker images"
  default     = false
  type        = bool
}
