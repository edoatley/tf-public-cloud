output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer."
  value       = aws_lb.this.dns_name
}

output "service_name" {
  description = "ECS service name."
  value       = aws_ecs_service.this.name
}

output "cluster_name" {
  description = "ECS cluster name."
  value       = aws_ecs_cluster.this.name
}

output "nat_gateway_ip" {
  description = "Elastic IP address of the NAT Gateway."
  value       = aws_eip.nat.public_ip
}

output "dashboard_url" {
  description = "CloudWatch dashboard URL."
  value       = "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards:name=${aws_cloudwatch_dashboard.app.dashboard_name}"
}

output "acm_validation_records" {
  description = "ACM DNS validation CNAME records to add to your DNS zone (only populated when enable_https = true)."
  value = var.enable_https ? {
    for dvo in aws_acm_certificate.this[0].domain_validation_options : dvo.domain_name => {
      name  = dvo.resource_record_name
      type  = dvo.resource_record_type
      value = dvo.resource_record_value
    }
  } : {}
}
