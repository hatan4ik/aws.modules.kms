output "name" {
  description = "Unique fixture name, used as the alias namespace of the key under test."
  value       = local.name
}

output "principal_arn" {
  description = "ARN of the caller's own identity, named as administrator, user, and grantee of the key under test."
  value       = data.aws_caller_identity.current.arn
}

output "account_id" {
  description = "Account the caller's credentials belong to, for asserting the module's identity fallback."
  value       = data.aws_caller_identity.current.account_id
}

output "partition" {
  description = "Partition the caller's credentials belong to, for asserting the module's identity fallback."
  value       = data.aws_partition.current.partition
}

output "region" {
  description = "Region the key is created in, resolved from the caller's credentials."
  value       = data.aws_region.current.region
}

output "tags" {
  description = "Identifying tags applied to the key under test."
  value       = local.tags
}
