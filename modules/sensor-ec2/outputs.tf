output "document_name" {
  description = "Name of the SSM Command document."
  value       = aws_ssm_document.sensor.name
}

output "association_id" {
  description = "ID of the SSM association that runs the document."
  value       = aws_ssm_association.sensor.association_id
}
