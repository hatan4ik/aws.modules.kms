output "key_arn" {
  description = "ARN of the signing key."
  value       = module.key.arn
}

output "key_id" {
  description = "ID of the signing key."
  value       = module.key.key_id
}

output "key_spec" {
  description = "Key material specification (RSA_4096)."
  value       = module.key.key_spec
}

output "key_usage" {
  description = "Cryptographic usage (SIGN_VERIFY)."
  value       = module.key.key_usage
}

output "alias_arn" {
  description = "ARN of the release/signing alias."
  value       = module.key.alias_arns["release/signing"]
}
