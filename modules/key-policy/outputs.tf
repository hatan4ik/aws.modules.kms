output "json" {
  description = "Rendered key policy document: sorted statements, sorted principals, actions, resources, and condition values, conditions grouped by operator, no empty blocks."
  value       = local.json

  precondition {
    condition     = length(local.statements) > 0
    error_message = "The key policy has no statements, which KMS rejects and which would lock the key. Enable enable_root_administration or declare key_administrator_arns, key_user_arns, key_service_principals, or statements."
  }

  precondition {
    condition     = local.json_bytes <= local.max_policy_bytes
    error_message = "The rendered key policy is ${local.json_bytes} bytes; KMS rejects key policies larger than ${local.max_policy_bytes} bytes (32 KB). Consolidate principals or statements, or split the access across grants."
  }
}

output "statement_count" {
  description = "Number of statements in the rendered policy."
  value       = length(local.statements)
}

output "size_bytes" {
  description = "Size of the rendered policy in bytes (UTF-8), the measure KMS applies its 32 KB key policy limit to."
  value       = local.json_bytes
}
