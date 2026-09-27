output "key_id" {
  description = "ID of the key."
  value       = aws_kms_key.this.key_id
}

output "arn" {
  description = "ARN of the key."
  value       = aws_kms_key.this.arn
}

output "key_usage" {
  description = "Cryptographic usage of the key."
  value       = aws_kms_key.this.key_usage
}

output "key_spec" {
  description = "Key material specification of the key."
  value       = aws_kms_key.this.customer_master_key_spec
}

output "policy" {
  description = "Key policy JSON applied to the key, composed or supplied."
  value       = aws_kms_key.this.policy
}

output "alias_arns" {
  description = "Alias ARNs keyed by alias name (without the alias/ prefix)."
  value       = { for name, alias in aws_kms_alias.this : name => alias.arn }
}

output "alias_names" {
  description = "Full alias names (alias/<name>) keyed by alias name."
  value       = { for name, alias in aws_kms_alias.this : name => alias.name }
}

output "grant_ids" {
  description = "Grant IDs keyed by grant name."
  value       = { for name, grant in aws_kms_grant.this : name => grant.grant_id }
}

output "grant_tokens" {
  description = "Grant tokens keyed by grant name, for callers that must use a grant before it propagates."
  value       = { for name, grant in aws_kms_grant.this : name => grant.grant_token }
  sensitive   = true
}

output "multi_region" {
  description = "Whether the key is a multi-Region primary."
  value       = aws_kms_key.this.multi_region
}

output "account_id" {
  description = "Account that owns the key: account_id when declared, otherwise the looked-up caller account."
  value       = local.account_id
}

output "partition" {
  description = "Partition of the key: partition when declared, otherwise the looked-up partition."
  value       = local.partition
}
