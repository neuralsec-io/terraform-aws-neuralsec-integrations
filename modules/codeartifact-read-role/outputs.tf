output "role_arn" {
  description = "ARN of the read-only CodeArtifact role the Neuralsec broker assumes."
  value       = aws_iam_role.this.arn
}
