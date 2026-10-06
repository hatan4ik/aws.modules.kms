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

  # Presets for the AWS-documented minimum grant of three common
  # integrations, one statement per entry, sorted by Sid. The region,
  # account, and partition come from resource_arn
  # (arn:<partition>:<service>:<region>:<account>:...), so a grant cannot
  # name one Region in its principal and another in its condition. The
  # actions and conditions, and the AWS pages they follow, are in
  # docs/DESIGN.md ("Service grant presets").
  service_grant_arn_parts = { for sid, grant in var.service_grants : sid => split(":", grant.resource_arn) }
  # A null dns_suffix with a regional preset fails the output precondition;
  # the placeholder only keeps the interpolation valid until it does.
  service_grant_dns_suffix = var.dns_suffix == null ? "dns-suffix-required" : var.dns_suffix
  service_grant_wildcard   = { for sid, grant in var.service_grants : sid => length(regexall("[*?]", grant.resource_arn)) > 0 }

  service_grant_statements = [for sid in sort(keys(var.service_grants)) : (
    var.service_grants[sid].service == "cloudwatch-logs" ? {
      # The regional CloudWatch Logs principal, as aws.modules.ecs builds it:
      # logs.<region>.<dns_suffix>. Scoped to one log group through the
      # encryption context CloudWatch Logs sends on every call.
      Sid       = sid
      Effect    = "Allow"
      Principal = { Service = ["logs.${local.service_grant_arn_parts[sid][3]}.${local.service_grant_dns_suffix}"] }
      Action    = ["kms:Decrypt", "kms:Describe*", "kms:Encrypt", "kms:GenerateDataKey*", "kms:ReEncrypt*"]
      Resource  = ["*"]
      Condition = { (local.service_grant_wildcard[sid] ? "ArnLike" : "ArnEquals") = { "kms:EncryptionContext:aws:logs:arn" = [var.service_grants[sid].resource_arn] } }
    } :
    var.service_grants[sid].service == "cloudfront" ? {
      # Read-only origin access control: CloudFront decrypts S3 objects for
      # GET on behalf of this one distribution. Same statement as
      # aws.modules.cloudfront's required_kms_key_policy_json.
      Sid       = sid
      Effect    = "Allow"
      Principal = { Service = ["cloudfront.amazonaws.com"] }
      Action    = ["kms:Decrypt"]
      Resource  = ["*"]
      Condition = { StringEquals = { "AWS:SourceArn" = [var.service_grants[sid].resource_arn] } }
    } :
    {
      # Secrets Manager calls KMS with the caller's identity, so the grantee
      # is the caller, limited to requests that Secrets Manager makes in the
      # secret's Region for this secret.
      Sid       = sid
      Effect    = "Allow"
      Principal = { AWS = sort(tolist(coalesce(var.service_grants[sid].principal_arns, []))) }
      Action    = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey"]
      Resource  = ["*"]
      Condition = local.service_grant_wildcard[sid] ? {
        StringEquals = { "kms:ViaService" = ["secretsmanager.${local.service_grant_arn_parts[sid][3]}.${local.service_grant_dns_suffix}"] }
        StringLike   = { "kms:EncryptionContext:SecretARN" = [var.service_grants[sid].resource_arn] }
        } : {
        StringEquals = {
          "kms:EncryptionContext:SecretARN" = [var.service_grants[sid].resource_arn]
          "kms:ViaService"                  = ["secretsmanager.${local.service_grant_arn_parts[sid][3]}.${local.service_grant_dns_suffix}"]
        }
      }
    }
  )]

  # Plan-time rules that span inputs, enforced by output preconditions.
  service_grants_need_dns_suffix = anytrue([for grant in values(var.service_grants) : grant.service != "cloudfront"])
  service_grant_partition_mismatches = sort([
    for sid, parts in local.service_grant_arn_parts : sid if parts[1] != var.partition
  ])
  service_grant_sid_collisions = sort(setintersection(toset(keys(var.service_grants)), toset(keys(var.statements))))

  statements = concat(
    local.root_statements,
    local.administrator_statements,
    local.user_statements,
    local.service_statements,
    local.service_grant_statements,
    local.declared_statements,
  )

  json = jsonencode({
    Version   = "2012-10-17"
    Statement = local.statements
  })

  # KMS limits a key policy to 32 KB (32768 bytes). length() counts
  # characters, not bytes, so the UTF-8 size is recovered from the base64
  # encoding: every 4 base64 characters are 3 bytes, minus the padding.
  max_policy_bytes = 32768
  json_base64      = base64encode(local.json)
  json_bytes       = length(local.json_base64) / 4 * 3 - length(regexall("=", local.json_base64))
}
