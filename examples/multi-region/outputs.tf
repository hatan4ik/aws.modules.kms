output "primary_key_arn" {
  description = "ARN of the primary key."
  value       = module.primary.arn
}

output "replica_key_arn" {
  description = "ARN of the replica key in the replica Region."
  value       = module.replica.arn
}

output "key_id" {
  description = "Multi-Region key ID shared by the primary and the replica."
  value       = module.primary.key_id
}

output "primary_alias_arn" {
  description = "ARN of the orders/data alias in the primary Region."
  value       = module.primary.alias_arns["orders/data"]
}

output "replica_alias_arn" {
  description = "ARN of the orders/data alias in the replica Region."
  value       = module.replica.alias_arns["orders/data"]
}

output "primary_policy" {
  description = "Key policy applied to the primary key."
  value       = module.primary.policy
}

output "replica_policy" {
  description = "Key policy applied to the replica key. Must equal primary_policy; tests/multi_region_example.tftest.hcl guards it."
  value       = module.replica.policy
}
