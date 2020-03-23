output "monolith_ip" {
  value       = aws_spot_instance_request.monolith.public_ip
  description = "The public IP address of the instance"
}
