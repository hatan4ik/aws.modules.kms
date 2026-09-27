output "key_id" {
  description = "ID of the replica key (the same mrk- ID as the primary)."
  value       = aws_kms_replica_key.this.key_id
}

output "arn" {
  description = "ARN of the replica key in its Region."
  value       = aws_kms_replica_key.this.arn
}

output "policy" {
  description = "Key policy JSON applied to the replica, composed or supplied."
  value       = aws_kms_replica_key.this.policy
}

output "alias_arns" {
  description = "Alias ARNs keyed by alias name (without the alias/ prefix)."
  value       = { for name, alias in aws_kms_alias.this : name => alias.arn }
}

output "alias_names" {
  description = "Full alias names (alias/<name>) keyed by alias name."
  value       = { for name, alias in aws_kms_alias.this : name => alias.name }
}

output "account_id" {
  description = "Account that owns the key, parsed from primary_key_arn."
  value       = local.account_id
}

output "partition" {
  description = "Partition of the key, parsed from primary_key_arn."
  value       = local.partition
}
