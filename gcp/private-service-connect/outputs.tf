output "psc_endpoint_ip" {
  description = "Address of the PSC endpoint, inside the consumer subnetwork. This is what the consumer curls."
  value       = google_compute_address.psc_endpoint.address
}

output "service_attachment_id" {
  description = "Full resource ID of the producer's service attachment."
  value       = google_compute_service_attachment.this.id
}

output "service_attachment_connected_status" {
  description = "Connection status of the consumer endpoint as seen by the producer. Empty immediately after create; run terraform refresh to populate."
  value       = try(google_compute_service_attachment.this.connected_endpoints[0].status, "(not yet reported - run terraform refresh)")
}

output "producer_instance_name" {
  description = "Name of the producer Compute Engine instance serving the web page."
  value       = google_compute_instance.producer.name
}

output "producer_instance_ip" {
  description = "Internal address of the producer instance, in the producer VPC. The consumer has no route to this."
  value       = google_compute_instance.producer.network_interface[0].network_ip
}

output "consumer_instance_name" {
  description = "Name of the consumer Compute Engine instance that tests the endpoint on boot."
  value       = google_compute_instance.consumer.name
}

output "consumer_instance_ip" {
  description = "Internal address of the consumer instance. The producer never sees this address - it sees a PSC NAT address instead."
  value       = google_compute_instance.consumer.network_interface[0].network_ip
}

output "producer_network_name" {
  description = "Name of the producer VPC network."
  value       = google_compute_network.producer.name
}

output "consumer_network_name" {
  description = "Name of the consumer VPC network."
  value       = google_compute_network.consumer.name
}

output "verify_command" {
  description = "Command that reads the consumer instance's boot-time PSC test result from the serial console."
  value       = format("gcloud compute instances get-serial-port-output %s --zone %s | grep PSC-", google_compute_instance.consumer.name, var.zone)
}
