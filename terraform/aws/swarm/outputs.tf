output "manager_ip" {
  value       = aws_instance.manager.public_ip
  description = "The public IP address of the manager instance"
}
