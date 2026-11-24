output "client_public_ip" {
  value = aws_instance.client.public_ip
}

output "client_private_ip" {
  value = aws_instance.client.private_ip
}

output "server_private_ip" {
  description = "Server IP the client container connects to"
  value       = data.aws_instance.server.private_ip
}

output "client_url" {
  value = "http://${aws_instance.client.public_ip}:8501"
}
