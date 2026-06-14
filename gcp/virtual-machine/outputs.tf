output "instance_name" {
  description = "Name of the Compute Engine instance."
  value       = google_compute_instance.this.name
}

output "instance_id" {
  description = "Unique ID of the Compute Engine instance."
  value       = google_compute_instance.this.id
}

output "public_ip" {
  description = "Static public IP address of the instance."
  value       = google_compute_address.this.address
}

output "image_self_link" {
  description = "Self-link of the boot disk image used."
  value       = data.google_compute_image.debian_12.self_link
}

output "ssh_connect_string" {
  description = "SSH command to connect to the instance (supply the private key path)."
  value       = format("ssh -i <private_key> debian@%s", google_compute_address.this.address)
}
