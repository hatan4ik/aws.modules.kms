output "json" {
  description = "Rendered key policy document: sorted statements, sorted principals, actions, resources, and condition values, conditions grouped by operator, no empty blocks."
  value       = local.json

  precondition {
    condition     = length(local.statements) > 0
    error_message = "The key policy has no statements, which KMS rejects and which would lock the key. Enable enable_root_administration or declare key_administrator_arns, key_user_arns, key_service_principals, or statements."
  }

  precondition {
    condition     = length(var.service_grants) == 0 || var.key_usage == "ENCRYPT_DECRYPT"
    error_message = "service_grants require key_usage ENCRYPT_DECRYPT: CloudWatch Logs, S3 SSE-KMS behind CloudFront, and Secrets Manager accept only symmetric encryption keys."
  }

  precondition {
    condition     = !local.service_grants_need_dns_suffix || var.dns_suffix != null
    error_message = "dns_suffix is required when service_grants contains a cloudwatch-logs or secretsmanager entry: it builds the regional service principal and the kms:ViaService endpoint. Pass data.aws_partition's dns_suffix (amazonaws.com in aws and aws-us-gov, amazonaws.com.cn in aws-cn)."
  }

  precondition {
    condition     = length(local.service_grant_partition_mismatches) == 0
    error_message = "service_grants ${join(", ", local.service_grant_partition_mismatches)}: the resource_arn partition must be the key's partition (${var.partition})."
  }

  precondition {
    condition     = length(local.service_grant_sid_collisions) == 0
    error_message = "service_grants and statements (policy_statements in the root and replica modules) share the Sid(s) ${join(", ", local.service_grant_sid_collisions)}; every Sid in a key policy must be unique."
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
