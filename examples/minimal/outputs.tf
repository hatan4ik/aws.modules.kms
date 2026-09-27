output "key_arn" {
  description = "ARN of the key."
  value       = module.key.arn
}

output "key_id" {
  description = "ID of the key."
  value       = module.key.key_id
}

output "alias_arn" {
  description = "ARN of the orders/data alias."
  value       = module.key.alias_arns["orders/data"]
}

output "policy" {
  description = "Key policy the module composed: the account root statement only."
  value       = module.key.policy
}
