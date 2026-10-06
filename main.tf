# Composition root. The policy is rendered by a pure submodule with its own
# tests; this file wires it to one KMS key with its aliases and grants.

# The one documented exception to the no-data-source rule: the account and
# partition are needed for the root principal of the policy and nothing else
# in the interface can supply them. Both lookups are skipped when the caller
# passes account_id and partition. aws_partition also runs when a
# cloudwatch-logs or secretsmanager service grant needs the partition's DNS
# suffix; it makes no API call (it reads the provider's configuration).
data "aws_caller_identity" "current" {
  count = var.account_id == null ? 1 : 0
}

data "aws_partition" "current" {
  count = var.partition == null || local.service_grants_need_dns_suffix ? 1 : 0
}

module "key_policy" {
  source = "./modules/key-policy"
  count  = var.policy_json_override == null ? 1 : 0

  partition    = local.partition
  account_id   = local.account_id
  key_usage    = var.key_usage
  multi_region = var.multi_region

  enable_root_administration = var.enable_root_administration
  key_administrator_arns     = var.key_administrator_arns
  key_user_arns              = var.key_user_arns
  key_service_principals     = var.key_service_principals
  statements                 = var.policy_statements

  dns_suffix     = local.dns_suffix
  service_grants = var.service_grants
}

resource "aws_kms_key" "this" {
  region                             = var.region
  description                        = var.description
  key_usage                          = var.key_usage
  customer_master_key_spec           = var.key_spec
  enable_key_rotation                = var.enable_key_rotation
  rotation_period_in_days            = var.rotation_period_in_days
  deletion_window_in_days            = var.deletion_window_in_days
  multi_region                       = var.multi_region
  is_enabled                         = var.is_enabled
  bypass_policy_lockout_safety_check = var.bypass_policy_lockout_safety_check
  custom_key_store_id                = var.custom_key_store_id
  policy                             = local.policy

  tags = merge({ Name = local.name }, var.tags)

  lifecycle {
    precondition {
      condition     = local.key_spec_usage_compatible
      error_message = "key_spec ${var.key_spec} does not support key_usage ${var.key_usage}. SYMMETRIC_DEFAULT: ENCRYPT_DECRYPT; RSA_*: ENCRYPT_DECRYPT or SIGN_VERIFY; ECC_NIST_*: SIGN_VERIFY or KEY_AGREEMENT; ECC_SECG_P256K1: SIGN_VERIFY; HMAC_*: GENERATE_VERIFY_MAC; ML_DSA_*: SIGN_VERIFY."
    }

    precondition {
      condition     = !var.enable_key_rotation || local.rotation_supported
      error_message = "Automatic rotation is supported only for SYMMETRIC_DEFAULT keys outside custom key stores. Set enable_key_rotation = false for key_spec ${var.key_spec}${var.custom_key_store_id == null ? "" : " in a custom key store"}."
    }

    precondition {
      condition     = var.rotation_period_in_days == null ? true : var.enable_key_rotation
      error_message = "rotation_period_in_days requires enable_key_rotation = true."
    }

    precondition {
      condition     = var.custom_key_store_id == null ? true : (local.symmetric && !var.multi_region)
      error_message = "Keys in a custom key store must use key_spec SYMMETRIC_DEFAULT and cannot be multi-Region."
    }

    precondition {
      condition     = var.policy_json_override == null ? true : (length(var.key_administrator_arns) == 0 && length(var.key_user_arns) == 0 && length(var.key_service_principals) == 0 && length(var.policy_statements) == 0 && length(var.service_grants) == 0)
      error_message = "policy_json_override replaces the composed policy. Remove key_administrator_arns, key_user_arns, key_service_principals, policy_statements, and service_grants, or drop the override and declare the policy through them."
    }

    precondition {
      condition     = length(var.service_grants) == 0 || local.symmetric
      error_message = "service_grants require key_spec SYMMETRIC_DEFAULT: CloudWatch Logs, S3 SSE-KMS behind CloudFront, and Secrets Manager accept only symmetric encryption keys."
    }

    precondition {
      condition     = var.partition == null || length(data.aws_partition.current) == 0 ? true : data.aws_partition.current[0].partition == var.partition
      error_message = "partition is declared as ${coalesce(var.partition, "null")} but the AWS provider is configured for ${try(data.aws_partition.current[0].partition, "unknown")}; service_grants read the DNS suffix from the provider's partition, so the two must agree."
    }
  }
}

resource "aws_kms_alias" "this" {
  for_each = var.aliases

  region        = var.region
  name          = "alias/${each.key}"
  target_key_id = aws_kms_key.this.key_id
}

resource "aws_kms_grant" "this" {
  for_each = var.grants

  region                = var.region
  name                  = each.key
  key_id                = aws_kms_key.this.key_id
  grantee_principal     = each.value.grantee_principal
  operations            = each.value.operations
  retiring_principal    = each.value.retiring_principal
  grant_creation_tokens = each.value.grant_creation_tokens
  retire_on_delete      = each.value.retire_on_delete

  dynamic "constraints" {
    for_each = each.value.constraints == null ? [] : [each.value.constraints]

    content {
      encryption_context_equals = constraints.value.encryption_context_equals
      encryption_context_subset = constraints.value.encryption_context_subset
    }
  }
}
