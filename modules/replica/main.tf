# One multi-Region replica key in the Region of the provider the caller
# passes (providers = { aws = aws.<alias> }). The partition and account come
# from primary_key_arn, so the module performs no lookups.

locals {
  # arn:<partition>:kms:<region>:<account>:key/mrk-<id>
  primary_key_arn_parts = split(":", var.primary_key_arn)
  partition             = local.primary_key_arn_parts[1]
  account_id            = local.primary_key_arn_parts[4]

  name   = length(var.aliases) > 0 ? sort(tolist(var.aliases))[0] : var.description
  policy = var.policy_json_override != null ? var.policy_json_override : module.key_policy[0].json
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
      condition     = var.policy_json_override == null ? true : (length(var.key_administrator_arns) == 0 && length(var.key_user_arns) == 0 && length(var.key_service_principals) == 0 && length(var.policy_statements) == 0)
      error_message = "policy_json_override replaces the composed policy. Remove key_administrator_arns, key_user_arns, key_service_principals, and policy_statements, or drop the override and declare the policy through them."
    }
  }
}

resource "aws_kms_alias" "this" {
  for_each = var.aliases

  name          = "alias/${each.key}"
  target_key_id = aws_kms_replica_key.this.key_id
}
