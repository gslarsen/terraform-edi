output "api_redeployment_triggers_sha" {
  description = "api redeployment triggers sha"
  value       = aws_api_gateway_deployment.edi.triggers.redeployment
}
