output "instance_id" {
  description = "EC2 instance ID."
  value       = aws_instance.this.id
}

output "public_ip" {
  description = "Public IP address of the instance."
  value       = aws_instance.this.public_ip
}

output "public_dns" {
  description = "Public DNS name of the instance."
  value       = aws_instance.this.public_dns
}

output "ami_id" {
  description = "AMI used to launch the instance."
  value       = data.aws_ami.amazon_linux_2023.id
}

output "ssh_connect_string" {
  description = "SSH command to connect to the instance (supply the private key path)."
  value       = format("ssh -i <private_key> ec2-user@%s", aws_instance.this.public_ip)
}
