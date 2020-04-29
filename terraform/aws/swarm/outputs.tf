output "manager_ip" {
  value       = aws_instance.manager.public_ip
  description = "The public IP address of the manager instance"
}
output "manager_id" {
  value       = aws_instance.manager.id
  description = "ID of the manager instance"
}
output "worker_image_id" {
  value       = aws_ami_from_instance.worker_ami.id
  description = "ID of the worker VM image"
}
