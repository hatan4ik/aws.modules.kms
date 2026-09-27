mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }
}

variables {
  description = "orders data key"
  account_id  = "123456789012"
  partition   = "aws"
}

run "composes_administrators_users_services_and_statements" {
  command = plan

  variables {
    key_administrator_arns = ["arn:aws:iam::123456789012:role/platform/kms-admin"]
    key_user_arns          = ["arn:aws:iam::123456789012:role/orders-task", "arn:aws:iam::123456789012:role/orders-worker"]
    key_service_principals = {
      "logs.us-east-1.amazonaws.com" = {
        conditions = [{
          test     = "ArnLike"
          variable = "kms:EncryptionContext:aws:logs:arn"
          values   = ["arn:aws:logs:us-east-1:123456789012:log-group:/aws/ecs/*"]
        }]
      }
    }
    policy_statements = {
      AllowCrossAccountDecrypt = {
        principals = { AWS = ["arn:aws:iam::210987654321:root"] }
        actions    = ["kms:Decrypt", "kms:DescribeKey"]
        conditions = [{ test = "StringEquals", variable = "kms:ViaService", values = ["s3.us-east-1.amazonaws.com"] }]
      }
    }
  }

  assert {
    condition     = [for statement in jsondecode(aws_kms_key.this.policy).Statement : statement.Sid] == ["EnableRootAccess", "AllowKeyAdministration", "AllowKeyUse", "AllowAttachmentOfPersistentResources", "AllowServiceUseLogsUsEast1AmazonawsCom", "AllowCrossAccountDecrypt"]
    error_message = "Statements must render in the documented order with the documented Sids."
  }

  assert {
    condition     = jsondecode(aws_kms_key.this.policy).Statement[1].Principal.AWS == ["arn:aws:iam::123456789012:role/platform/kms-admin"] && contains(jsondecode(aws_kms_key.this.policy).Statement[1].Action, "kms:ScheduleKeyDeletion") && !contains(jsondecode(aws_kms_key.this.policy).Statement[1].Action, "kms:Decrypt")
    error_message = "Administrators must be able to manage but not use the key."
  }

  assert {
    condition     = jsondecode(aws_kms_key.this.policy).Statement[2].Principal.AWS == ["arn:aws:iam::123456789012:role/orders-task", "arn:aws:iam::123456789012:role/orders-worker"] && jsondecode(aws_kms_key.this.policy).Statement[2].Action == ["kms:Decrypt", "kms:DescribeKey", "kms:Encrypt", "kms:GenerateDataKey*", "kms:ReEncrypt*"]
    error_message = "Users must receive the symmetric use actions, sorted."
  }

  assert {
    condition     = jsondecode(aws_kms_key.this.policy).Statement[3].Condition.Bool["kms:GrantIsForAWSResource"] == ["true"]
    error_message = "Grant management by users must be limited to AWS resources."
  }

  assert {
    condition     = jsondecode(aws_kms_key.this.policy).Statement[4].Principal.Service == ["logs.us-east-1.amazonaws.com"] && jsondecode(aws_kms_key.this.policy).Statement[4].Condition.ArnLike["kms:EncryptionContext:aws:logs:arn"] == ["arn:aws:logs:us-east-1:123456789012:log-group:/aws/ecs/*"]
    error_message = "The CloudWatch Logs service principal must be limited by the encryption-context condition."
  }

  assert {
    condition     = jsondecode(aws_kms_key.this.policy).Statement[5].Condition.StringEquals["kms:ViaService"] == ["s3.us-east-1.amazonaws.com"] && jsondecode(aws_kms_key.this.policy).Statement[5].Resource == ["*"]
    error_message = "Declared statements must keep their conditions and default to the key as resource."
  }
}

run "grants_signing_actions_to_users_of_a_signing_key" {
  command = plan

  variables {
    key_spec            = "RSA_4096"
    key_usage           = "SIGN_VERIFY"
    enable_key_rotation = false
    key_user_arns       = ["arn:aws:iam::123456789012:role/release-signer"]
  }

  assert {
    condition     = jsondecode(aws_kms_key.this.policy).Statement[1].Action == ["kms:DescribeKey", "kms:GetPublicKey", "kms:Sign", "kms:Verify"]
    error_message = "Users of a signing key must receive signing actions, not encryption actions."
  }

  assert {
    condition     = aws_kms_key.this.customer_master_key_spec == "RSA_4096" && aws_kms_key.this.key_usage == "SIGN_VERIFY" && aws_kms_key.this.enable_key_rotation == false
    error_message = "key_spec must map to the provider's customer_master_key_spec and rotation must stay off for asymmetric keys."
  }
}

run "applies_a_caller_policy_verbatim_and_skips_the_renderer" {
  command = plan

  variables {
    enable_root_administration = false
    policy_json_override = jsonencode({
      Version   = "2012-10-17"
      Statement = [{ Sid = "Custom", Effect = "Allow", Principal = { AWS = "arn:aws:iam::123456789012:role/owner" }, Action = "kms:*", Resource = "*" }]
    })
  }

  assert {
    condition     = aws_kms_key.this.policy == var.policy_json_override && output.policy == var.policy_json_override
    error_message = "A supplied policy document must be applied unchanged."
  }

  assert {
    condition     = length(module.key_policy) == 0
    error_message = "The policy renderer must not be instantiated when the caller supplies the document."
  }
}
