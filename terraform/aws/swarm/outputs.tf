output "manager_ip" {
  value       = aws_instance.manager.public_ip
  description = "The public IP address of the manager instance"
}
output "manager_id" {
  value       = aws_instance.manager.id
  description = "AWS ID of the manager instance"
}
