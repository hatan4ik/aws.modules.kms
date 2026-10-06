# One multi-Region replica key in the Region of the provider the caller
# passes (providers = { aws = aws.<alias> }). The partition and account come
# from primary_key_arn. The only lookup is aws_partition, and only when a
# cloudwatch-logs or secretsmanager service grant needs the partition's DNS
# suffix; it makes no API call (it reads the provider's configuration).

data "aws_partition" "current" {
  count = local.service_grants_need_dns_suffix ? 1 : 0
}

locals {
  # arn:<partition>:kms:<region>:<account>:key/mrk-<id>
  primary_key_arn_parts = split(":", var.primary_key_arn)
  partition             = local.primary_key_arn_parts[1]
  account_id            = local.primary_key_arn_parts[4]

  # AWS caps tag values at 256 characters while description allows 8192, so
  # the description is truncated when it stands in for the Name tag.
  name   = length(var.aliases) > 0 ? sort(tolist(var.aliases))[0] : substr(var.description, 0, 256)
  policy = var.policy_json_override != null ? var.policy_json_override : module.key_policy[0].json

  service_grants_need_dns_suffix = anytrue([for grant in values(var.service_grants) : grant.service != "cloudfront"])
  dns_suffix                     = local.service_grants_need_dns_suffix ? data.aws_partition.current[0].dns_suffix : null
}

module "key_policy" {
  source = "../key-policy"
  count  = var.policy_json_override == null ? 1 : 0

  partition    = local.partition
  account_id   = local.account_id
  key_usage    = var.key_usage
  multi_region = true

  enable_root_administration = var.enable_root_administration
  key_administrator_arns     = var.key_administrator_arns
  key_user_arns              = var.key_user_arns
  key_service_principals     = var.key_service_principals
  statements                 = var.policy_statements

  dns_suffix     = local.dns_suffix
  service_grants = var.service_grants
}

resource "aws_kms_replica_key" "this" {
  primary_key_arn                    = var.primary_key_arn
  description                        = var.description
  deletion_window_in_days            = var.deletion_window_in_days
  enabled                            = var.enabled
  bypass_policy_lockout_safety_check = var.bypass_policy_lockout_safety_check
  policy                             = local.policy

  tags = merge({ Name = local.name }, var.tags)

  lifecycle {
    precondition {
      condition     = var.policy_json_override == null ? true : (length(var.key_administrator_arns) == 0 && length(var.key_user_arns) == 0 && length(var.key_service_principals) == 0 && length(var.policy_statements) == 0 && length(var.service_grants) == 0)
      error_message = "policy_json_override replaces the composed policy. Remove key_administrator_arns, key_user_arns, key_service_principals, policy_statements, and service_grants, or drop the override and declare the policy through them."
    }

    precondition {
      condition     = length(data.aws_partition.current) == 0 ? true : data.aws_partition.current[0].partition == local.partition
      error_message = "primary_key_arn is in partition ${local.partition} but the AWS provider passed to the replica is configured for ${try(data.aws_partition.current[0].partition, "unknown")}; service_grants read the DNS suffix from the provider's partition, so the two must agree."
    }
  }
}

resource "aws_kms_alias" "this" {
  for_each = var.aliases

  name          = "alias/${each.key}"
  target_key_id = aws_kms_replica_key.this.key_id
}
