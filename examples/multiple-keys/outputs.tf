output "key_arns" {
  description = "Key ARNs keyed by purpose."
  value       = { for purpose, key in module.key : purpose => key.arn }
}

output "key_ids" {
  description = "Key IDs keyed by purpose."
  value       = { for purpose, key in module.key : purpose => key.key_id }
}

output "alias_names" {
  description = "Full alias name of each key, keyed by purpose."
  value       = { for purpose, key in module.key : purpose => key.alias_names["${var.alias_prefix}/${purpose}"] }
}
