provider "aws" {
  region = var.region
}

module "key" {
  source = "../../"

  description = "Application data key for the orders service"
  tags        = var.tags

  # ----------------------------------------------------------------- key
  rotation_period_in_days = 180
  deletion_window_in_days = 30

  # ------------------------------------------------------------ identity
  # Passing both skips the aws_caller_identity and aws_partition lookups.
  account_id = var.account_id
  partition  = "aws"

  # -------------------------------------------------------------- policy
  key_administrator_arns = var.key_administrator_arns
  key_user_arns          = var.key_user_arns

  # CloudWatch Logs may use the key only for log groups in this account and
  # Region, which the encryption-context condition enforces.
  key_service_principals = {
    "logs.${var.region}.amazonaws.com" = {
      conditions = [{
        test     = "ArnLike"
        variable = "kms:EncryptionContext:aws:logs:arn"
        values   = ["arn:aws:logs:${var.region}:${var.account_id}:log-group:${var.log_group_prefix}*"]
      }]
    }
  }

  policy_statements = {
    # A consumer account may decrypt, but only through S3 in this Region.
    AllowConsumerDecryptViaS3 = {
      principals = { AWS = ["arn:aws:iam::${var.consumer_account_id}:root"] }
      actions    = ["kms:Decrypt", "kms:DescribeKey"]
      conditions = [{ test = "StringEquals", variable = "kms:ViaService", values = ["s3.${var.region}.amazonaws.com"] }]
    }
    # Nobody outside the organization may use the key, whatever else allows it.
    DenyOutsideOrganization = {
      effect     = "Deny"
      principals = { AWS = ["*"] }
      actions    = ["kms:*"]
      conditions = [
        { test = "StringNotEquals", variable = "aws:PrincipalOrgID", values = [var.organization_id] },
        { test = "Bool", variable = "aws:PrincipalIsAWSService", values = ["false"] },
      ]
    }
  }

  # ------------------------------------------------------------- aliases
  aliases = ["orders/data", "orders/data-v2"]

  # -------------------------------------------------------------- grants
  # Auto Scaling launches instances whose volumes are encrypted with the key;
  # the grant lets its service-linked role attach those volumes.
  grants = {
    autoscaling-volumes = {
      grantee_principal = var.autoscaling_role_arn
      operations        = ["Encrypt", "Decrypt", "ReEncryptFrom", "ReEncryptTo", "GenerateDataKey", "GenerateDataKeyWithoutPlaintext", "DescribeKey", "CreateGrant"]
      constraints       = { encryption_context_subset = { "aws:ebs:id" = var.volume_id_prefix } }
      retire_on_delete  = true
    }
  }
}
