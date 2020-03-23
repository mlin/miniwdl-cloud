output "manager_ip" {
  value       = aws_eip.manager_eip.public_ip
  description = "The public IP address of the manager instance"
}
