output "api_redeployment_triggers_sha" {
  description = "api redeployment triggers sha"
  value       = aws_api_gateway_deployment.edi.triggers.redeployment
}

output "total_count_of_resources" {
  description = "total count of resources"
  value       = length(jsondecode(file("terraform.tfstate.backup")).resources)
}
