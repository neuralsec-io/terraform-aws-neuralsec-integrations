output "service_name" {
  description = "Endpoint service name to paste into Neuralsec, com.amazonaws.vpce.<region>.vpce-svc-<id>."
  value       = aws_vpc_endpoint_service.this.service_name
}

output "endpoint_service_id" {
  description = "ID of the endpoint service, vpce-svc-<id>."
  value       = aws_vpc_endpoint_service.this.id
}

output "nlb_arn" {
  description = "ARN of the Network Load Balancer that publishes the service, the one this module creates or existing_nlb_arn."
  value       = local.nlb_arn
}

output "nlb_security_group_id" {
  description = "ID of the load balancer security group. Allow it on the target port in the service security group. Null when existing_nlb_arn is set."
  value       = try(aws_security_group.this[0].id, null)
}
