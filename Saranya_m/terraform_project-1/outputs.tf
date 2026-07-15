

#vpc_id

output "vpc_id" {
  description = "ID of the created VPC"
  value       = aws_vpc.main.id
}

# web_public_ip

output "web_public_ip" {
  description = "Public IP address of the web server EC2 instance"
  value       = aws_eip.web.public_ip
}

# web_public_url

output "web_public_url" {
  description = "HTTP URL of the web server"
  value       = "http://${aws_eip.web.public_ip}"
}

#db_private_ip

output "db_private_ip" {
  description = "Private IP address of the database EC2 instance"
  value       = aws_instance.db.private_ip
}
