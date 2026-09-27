output "json" {
  description = "Rendered key policy document: sorted statements, sorted principals, actions, resources, and condition values, conditions grouped by operator, no empty blocks."
  value       = local.json

  precondition {
    condition     = length(local.statements) > 0
    error_message = "The key policy has no statements, which KMS rejects and which would lock the key. Enable enable_root_administration or declare key_administrator_arns, key_user_arns, key_service_principals, or statements."
  }
}

output "statement_count" {
  description = "Number of statements in the rendered policy."
  value       = length(local.statements)
}
