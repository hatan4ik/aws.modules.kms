variables {
  account_id = "123456789012"
}

run "renders_root_administration_only_by_default" {
  command = plan

  assert {
    condition     = output.statement_count == 1 && length(jsondecode(output.json).Statement) == 1
    error_message = "The default policy must contain exactly the root administration statement."
  }

  assert {
    condition     = jsondecode(output.json).Version == "2012-10-17"
    error_message = "The policy must use the 2012-10-17 policy language version."
  }

  assert {
    condition     = jsondecode(output.json).Statement[0].Sid == "EnableRootAccess" && jsondecode(output.json).Statement[0].Effect == "Allow"
    error_message = "The root statement must be an Allow named EnableRootAccess."
  }

  assert {
    condition     = jsondecode(output.json).Statement[0].Principal.AWS == ["arn:aws:iam::123456789012:root"]
    error_message = "The root statement must name the account root in the aws partition by default."
  }

  assert {
    condition     = jsondecode(output.json).Statement[0].Action == ["kms:*"] && jsondecode(output.json).Statement[0].Resource == ["*"]
    error_message = "The root statement must grant every KMS action on the key."
  }

  assert {
    condition     = !contains(keys(jsondecode(output.json).Statement[0]), "Condition")
    error_message = "A statement without conditions must not render an empty Condition block."
  }
}

run "uses_the_declared_partition" {
  command = plan

  variables {
    partition = "aws-us-gov"
  }

  assert {
    condition     = jsondecode(output.json).Statement[0].Principal.AWS == ["arn:aws-us-gov:iam::123456789012:root"]
    error_message = "The root principal must be built from the declared partition."
  }
}

run "renders_administrators_users_and_grant_management" {
  command = plan

  variables {
    key_administrator_arns = [
      "arn:aws:iam::123456789012:role/platform/kms-admin",
      "arn:aws:iam::123456789012:role/break-glass",
    ]
    key_user_arns = ["arn:aws:iam::123456789012:role/orders-task"]
  }

  assert {
    condition     = output.statement_count == 4
    error_message = "Root, administration, use, and grant-management statements must all render."
  }

  assert {
    condition     = jsondecode(output.json).Statement[1].Sid == "AllowKeyAdministration" && jsondecode(output.json).Statement[1].Principal.AWS == ["arn:aws:iam::123456789012:role/break-glass", "arn:aws:iam::123456789012:role/platform/kms-admin"]
    error_message = "Administrator principals must render sorted under AllowKeyAdministration."
  }

  assert {
    condition = jsondecode(output.json).Statement[1].Action == [
      "kms:CancelKeyDeletion", "kms:Create*", "kms:Delete*", "kms:Describe*", "kms:Disable*", "kms:Enable*", "kms:Get*",
      "kms:List*", "kms:Put*", "kms:Revoke*", "kms:RotateKeyOnDemand", "kms:ScheduleKeyDeletion", "kms:TagResource",
      "kms:UntagResource", "kms:Update*",
    ]
    error_message = "Administrators must receive exactly the AWS-documented administration actions, sorted."
  }

  assert {
    condition     = jsondecode(output.json).Statement[2].Sid == "AllowKeyUse" && jsondecode(output.json).Statement[2].Principal.AWS == ["arn:aws:iam::123456789012:role/orders-task"]
    error_message = "User principals must render under AllowKeyUse."
  }

  assert {
    condition     = jsondecode(output.json).Statement[2].Action == ["kms:Decrypt", "kms:DescribeKey", "kms:Encrypt", "kms:GenerateDataKey*", "kms:ReEncrypt*"]
    error_message = "Users of an encryption key must receive exactly the symmetric use actions."
  }

  assert {
    condition     = jsondecode(output.json).Statement[3].Sid == "AllowAttachmentOfPersistentResources" && jsondecode(output.json).Statement[3].Action == ["kms:CreateGrant", "kms:ListGrants", "kms:RevokeGrant"]
    error_message = "Users must be able to manage grants for AWS resources."
  }

  assert {
    condition     = jsondecode(output.json).Statement[3].Condition.Bool["kms:GrantIsForAWSResource"] == ["true"]
    error_message = "Grant management by users must be limited to grants created for AWS resources."
  }
}

run "adds_replicate_key_for_multi_region_administrators" {
  command = plan

  variables {
    multi_region           = true
    key_administrator_arns = ["arn:aws:iam::123456789012:role/kms-admin"]
  }

  assert {
    condition     = contains(jsondecode(output.json).Statement[1].Action, "kms:ReplicateKey")
    error_message = "Administrators of a multi-Region key must be able to replicate it."
  }
}

run "selects_use_actions_by_key_usage" {
  command = plan

  variables {
    key_usage     = "SIGN_VERIFY"
    key_user_arns = ["arn:aws:iam::123456789012:role/signer"]
    key_service_principals = {
      "lambda.amazonaws.com" = {}
    }
  }

  assert {
    condition     = jsondecode(output.json).Statement[1].Action == ["kms:DescribeKey", "kms:GetPublicKey", "kms:Sign", "kms:Verify"]
    error_message = "Users of a signing key must receive the signing actions, not the encryption actions."
  }

  assert {
    condition     = jsondecode(output.json).Statement[3].Action == ["kms:DescribeKey", "kms:GetPublicKey", "kms:Sign", "kms:Verify"]
    error_message = "Service principals without explicit actions must receive the key's use actions."
  }
}

run "renders_service_principals_with_conditions" {
  command = plan

  variables {
    key_service_principals = {
      "logs.us-east-1.amazonaws.com" = {
        conditions = [{
          test     = "ArnLike"
          variable = "kms:EncryptionContext:aws:logs:arn"
          values   = ["arn:aws:logs:us-east-1:123456789012:log-group:*"]
        }]
      }
      "cloudtrail.amazonaws.com" = {
        actions = ["kms:GenerateDataKey*", "kms:DescribeKey"]
        conditions = [
          { test = "StringEquals", variable = "aws:SourceAccount", values = ["123456789012"] },
          { test = "StringLike", variable = "kms:EncryptionContext:aws:cloudtrail:arn", values = ["arn:aws:cloudtrail:*:123456789012:trail/*"] },
          { test = "StringEquals", variable = "aws:SourceArn", values = ["arn:aws:cloudtrail:us-east-1:123456789012:trail/org"] },
        ]
      }
    }
  }

  assert {
    condition     = output.statement_count == 3
    error_message = "Each service principal must render its own statement after the root statement."
  }

  assert {
    condition     = jsondecode(output.json).Statement[1].Sid == "AllowServiceUseCloudtrailAmazonawsCom" && jsondecode(output.json).Statement[2].Sid == "AllowServiceUseLogsUsEast1AmazonawsCom"
    error_message = "Service statements must be sorted by principal and carry an alphanumeric Sid derived from it."
  }

  assert {
    condition     = jsondecode(output.json).Statement[1].Principal.Service == ["cloudtrail.amazonaws.com"] && jsondecode(output.json).Statement[1].Action == ["kms:DescribeKey", "kms:GenerateDataKey*"]
    error_message = "A service principal may narrow its actions."
  }

  assert {
    condition     = jsondecode(output.json).Statement[1].Condition.StringEquals["aws:SourceAccount"] == ["123456789012"] && jsondecode(output.json).Statement[1].Condition.StringEquals["aws:SourceArn"] == ["arn:aws:cloudtrail:us-east-1:123456789012:trail/org"] && jsondecode(output.json).Statement[1].Condition.StringLike["kms:EncryptionContext:aws:cloudtrail:arn"] == ["arn:aws:cloudtrail:*:123456789012:trail/*"]
    error_message = "Conditions must be grouped by operator with every variable of that operator under it."
  }

  assert {
    condition     = jsondecode(output.json).Statement[2].Condition.ArnLike["kms:EncryptionContext:aws:logs:arn"] == ["arn:aws:logs:us-east-1:123456789012:log-group:*"]
    error_message = "The CloudWatch Logs encryption-context condition must render under ArnLike."
  }
}

run "renders_declared_statements_sorted_by_sid" {
  command = plan

  variables {
    enable_root_administration = false
    statements = {
      DenyOutsideOrganization = {
        effect     = "Deny"
        principals = { AWS = ["*"] }
        actions    = ["kms:*"]
        conditions = [{ test = "StringNotEquals", variable = "aws:PrincipalOrgID", values = ["o-abc123"] }]
      }
      AllowCrossAccountDecrypt = {
        principals = { AWS = ["arn:aws:iam::210987654321:root"] }
        actions    = ["kms:Decrypt", "kms:DescribeKey"]
      }
      AllowFederatedRead = {
        principals = { Federated = ["arn:aws:iam::123456789012:saml-provider/okta"], AWS = ["arn:aws:iam::123456789012:role/reader"] }
        actions    = ["kms:DescribeKey"]
        resources  = ["*"]
      }
    }
  }

  assert {
    condition     = output.statement_count == 3 && jsondecode(output.json).Statement[0].Sid == "AllowCrossAccountDecrypt" && jsondecode(output.json).Statement[1].Sid == "AllowFederatedRead" && jsondecode(output.json).Statement[2].Sid == "DenyOutsideOrganization"
    error_message = "Declared statements must render sorted by Sid and replace the root statement when it is disabled."
  }

  assert {
    condition     = jsondecode(output.json).Statement[2].Effect == "Deny" && jsondecode(output.json).Statement[2].Principal.AWS == ["*"] && jsondecode(output.json).Statement[2].Condition.StringNotEquals["aws:PrincipalOrgID"] == ["o-abc123"]
    error_message = "Deny statements must keep their effect, wildcard principal, and conditions."
  }

  assert {
    condition     = keys(jsondecode(output.json).Statement[1].Principal) == ["AWS", "Federated"] && jsondecode(output.json).Statement[1].Resource == ["*"]
    error_message = "Principal types must render sorted and Resource must default to the key itself."
  }

  assert {
    condition     = jsondecode(output.json).Statement[0].Action == ["kms:Decrypt", "kms:DescribeKey"] && !contains(keys(jsondecode(output.json).Statement[0]), "Condition")
    error_message = "Actions must be sorted and statements without conditions must not render a Condition block."
  }
}

run "rejects_policy_without_any_statement" {
  command = plan

  variables {
    enable_root_administration = false
  }

  expect_failures = [output.json]
}

run "rejects_malformed_account_id" {
  command = plan

  variables {
    account_id = "12345"
  }

  expect_failures = [var.account_id]
}

run "rejects_unknown_partition" {
  command = plan

  variables {
    partition = "azure"
  }

  expect_failures = [var.partition]
}

run "rejects_unknown_key_usage" {
  command = plan

  variables {
    key_usage = "ENCRYPT"
  }

  expect_failures = [var.key_usage]
}

run "rejects_administrator_that_is_not_an_iam_principal_arn" {
  command = plan

  variables {
    key_administrator_arns = ["kms-admin"]
  }

  expect_failures = [var.key_administrator_arns]
}

run "rejects_user_that_is_not_an_iam_principal_arn" {
  command = plan

  variables {
    key_user_arns = ["arn:aws:s3:::bucket"]
  }

  expect_failures = [var.key_user_arns]
}

run "rejects_service_principal_outside_amazonaws" {
  command = plan

  variables {
    key_service_principals = {
      "logs.example.com" = {}
    }
  }

  expect_failures = [var.key_service_principals]
}

run "rejects_service_principal_with_duplicate_condition" {
  command = plan

  variables {
    key_service_principals = {
      "logs.amazonaws.com" = {
        conditions = [
          { test = "StringEquals", variable = "aws:SourceAccount", values = ["123456789012"] },
          { test = "StringEquals", variable = "aws:SourceAccount", values = ["210987654321"] },
        ]
      }
    }
  }

  expect_failures = [var.key_service_principals]
}

run "rejects_statement_with_reserved_sid" {
  command = plan

  variables {
    statements = {
      AllowKeyUse = {
        principals = { AWS = ["arn:aws:iam::123456789012:role/reader"] }
        actions    = ["kms:DescribeKey"]
      }
    }
  }

  expect_failures = [var.statements]
}

run "rejects_statement_with_non_alphanumeric_sid" {
  command = plan

  variables {
    statements = {
      "allow-read" = {
        principals = { AWS = ["arn:aws:iam::123456789012:role/reader"] }
        actions    = ["kms:DescribeKey"]
      }
    }
  }

  expect_failures = [var.statements]
}

run "rejects_statement_without_principals" {
  command = plan

  variables {
    statements = {
      AllowNobody = {
        principals = {}
        actions    = ["kms:DescribeKey"]
      }
    }
  }

  expect_failures = [var.statements]
}

run "rejects_statement_with_unknown_principal_type" {
  command = plan

  variables {
    statements = {
      AllowUser = {
        principals = { User = ["arn:aws:iam::123456789012:user/alice"] }
        actions    = ["kms:DescribeKey"]
      }
    }
  }

  expect_failures = [var.statements]
}

run "rejects_statement_with_invalid_effect" {
  command = plan

  variables {
    statements = {
      AllowRead = {
        effect     = "Permit"
        principals = { AWS = ["arn:aws:iam::123456789012:role/reader"] }
        actions    = ["kms:DescribeKey"]
      }
    }
  }

  expect_failures = [var.statements]
}

run "rejects_unconditional_allow_to_wildcard_principal" {
  command = plan

  variables {
    statements = {
      AllowAnyone = {
        principals = { AWS = ["*"] }
        actions    = ["kms:Decrypt"]
      }
    }
  }

  expect_failures = [var.statements]
}
