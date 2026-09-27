output "key_arn" {
  description = "ARN of the key."
  value       = module.key.arn
}

output "key_id" {
  description = "ID of the key."
  value       = module.key.key_id
}

output "policy" {
  description = "Composed key policy: root, administrators, users, grant management, CloudWatch Logs, the consumer statement, and the organization deny."
  value       = module.key.policy
}

output "alias_arns" {
  description = "Alias ARNs keyed by alias name."
  value       = module.key.alias_arns
}

output "alias_names" {
  description = "Full alias names keyed by alias name."
  value       = module.key.alias_names
}

output "grant_ids" {
  description = "Grant IDs keyed by grant name."
  value       = module.key.grant_ids
}

output "grant_tokens" {
  description = "Grant tokens keyed by grant name, for use before the grant propagates."
  value       = module.key.grant_tokens
  sensitive   = true
}

output "account_id" {
  description = "Account that owns the key, as declared."
  value       = module.key.account_id
}
