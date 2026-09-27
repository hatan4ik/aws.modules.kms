# Renders one KMS key policy from typed inputs. This module creates no
# resources and declares no provider: it exists so the policy shape has a
# single owner and can be unit-tested with terraform test alone.

locals {
  root_arn = "arn:${var.partition}:iam::${var.account_id}:root"

  # The administrator statement AWS generates in the console, plus
  # kms:ReplicateKey for multi-Region keys. Sorted so the JSON is stable.
  administrator_actions = sort(concat([
    "kms:Create*", "kms:Describe*", "kms:Enable*", "kms:List*", "kms:Put*", "kms:Update*", "kms:Revoke*", "kms:Disable*",
    "kms:Get*", "kms:Delete*", "kms:TagResource", "kms:UntagResource", "kms:ScheduleKeyDeletion", "kms:CancelKeyDeletion",
    "kms:RotateKeyOnDemand",
  ], var.multi_region ? ["kms:ReplicateKey"] : []))

  # The use actions a key type supports; anything else fails at the API.
  use_actions_by_usage = {
    ENCRYPT_DECRYPT     = ["kms:Decrypt", "kms:DescribeKey", "kms:Encrypt", "kms:GenerateDataKey*", "kms:ReEncrypt*"]
    SIGN_VERIFY         = ["kms:DescribeKey", "kms:GetPublicKey", "kms:Sign", "kms:Verify"]
    GENERATE_VERIFY_MAC = ["kms:DescribeKey", "kms:GenerateMac", "kms:VerifyMac"]
    KEY_AGREEMENT       = ["kms:DeriveSharedSecret", "kms:DescribeKey", "kms:GetPublicKey"]
  }
  use_actions = local.use_actions_by_usage[var.key_usage]

  # Conditions grouped by operator: { test => { variable => sorted values } }.
  service_conditions = {
    for principal, entry in var.key_service_principals : principal => {
      for test in distinct([for condition in entry.conditions : condition.test]) : test => {
        for condition in entry.conditions : condition.variable => sort(tolist(condition.values)) if condition.test == test
      }
    }
  }

  statement_conditions = {
    for sid, statement in var.statements : sid => {
      for test in distinct([for condition in statement.conditions : condition.test]) : test => {
        for condition in statement.conditions : condition.variable => sort(tolist(condition.values)) if condition.test == test
      }
    }
  }

  root_statements = var.enable_root_administration ? [{
    Sid       = "EnableRootAccess"
    Effect    = "Allow"
    Principal = { AWS = [local.root_arn] }
    Action    = ["kms:*"]
    Resource  = ["*"]
  }] : []

  administrator_statements = length(var.key_administrator_arns) == 0 ? [] : [{
    Sid       = "AllowKeyAdministration"
    Effect    = "Allow"
    Principal = { AWS = sort(tolist(var.key_administrator_arns)) }
    Action    = local.administrator_actions
    Resource  = ["*"]
  }]

  # Two statements of different shapes: a filtered comprehension keeps the
  # tuple typed when the set is empty.
  user_statements = [for statement in [
    {
      Sid       = "AllowKeyUse"
      Effect    = "Allow"
      Principal = { AWS = sort(tolist(var.key_user_arns)) }
      Action    = local.use_actions
      Resource  = ["*"]
    },
    {
      Sid       = "AllowAttachmentOfPersistentResources"
      Effect    = "Allow"
      Principal = { AWS = sort(tolist(var.key_user_arns)) }
      Action    = ["kms:CreateGrant", "kms:ListGrants", "kms:RevokeGrant"]
      Resource  = ["*"]
      Condition = { Bool = { "kms:GrantIsForAWSResource" = ["true"] } }
    },
  ] : statement if length(var.key_user_arns) > 0]

  # One statement per service principal, sorted by principal, with a Sid
  # derived from it (logs.us-east-1.amazonaws.com -> LogsUsEast1AmazonawsCom).
  service_statements = [for principal in sort(keys(var.key_service_principals)) : merge(
    {
      Sid       = "AllowServiceUse${join("", [for token in regexall("[a-zA-Z0-9]+", principal) : title(token)])}"
      Effect    = "Allow"
      Principal = { Service = [principal] }
      Action    = var.key_service_principals[principal].actions == null ? local.use_actions : sort(tolist(var.key_service_principals[principal].actions))
      Resource  = ["*"]
    },
    length(var.key_service_principals[principal].conditions) == 0 ? {} : { Condition = local.service_conditions[principal] },
  )]

  declared_statements = [for sid in sort(keys(var.statements)) : merge(
    {
      Sid       = sid
      Effect    = var.statements[sid].effect
      Principal = { for type in sort(keys(var.statements[sid].principals)) : type => sort(tolist(var.statements[sid].principals[type])) }
      Action    = sort(tolist(var.statements[sid].actions))
      Resource  = sort(tolist(var.statements[sid].resources))
    },
    length(var.statements[sid].conditions) == 0 ? {} : { Condition = local.statement_conditions[sid] },
  )]

  statements = concat(
    local.root_statements,
    local.administrator_statements,
    local.user_statements,
    local.service_statements,
    local.declared_statements,
  )

  json = jsonencode({
    Version   = "2012-10-17"
    Statement = local.statements
  })
}
