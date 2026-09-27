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

run "rejects_empty_description" {
  command = plan
  variables {
    description = ""
  }
  expect_failures = [var.description]
}

run "rejects_unknown_key_usage" {
  command = plan
  variables {
    key_usage = "ENCRYPT"
  }
  expect_failures = [var.key_usage]
}

run "rejects_unknown_key_spec" {
  command = plan
  variables {
    key_spec = "AES_256"
  }
  expect_failures = [var.key_spec]
}

run "rejects_hmac_spec_for_encryption" {
  command = plan
  variables {
    key_spec            = "HMAC_256"
    key_usage           = "ENCRYPT_DECRYPT"
    enable_key_rotation = false
  }
  expect_failures = [aws_kms_key.this]
}

run "rejects_ecc_spec_for_encryption" {
  command = plan
  variables {
    key_spec            = "ECC_NIST_P256"
    key_usage           = "ENCRYPT_DECRYPT"
    enable_key_rotation = false
  }
  expect_failures = [aws_kms_key.this]
}

run "rejects_secg_spec_for_key_agreement" {
  command = plan
  variables {
    key_spec            = "ECC_SECG_P256K1"
    key_usage           = "KEY_AGREEMENT"
    enable_key_rotation = false
  }
  expect_failures = [aws_kms_key.this]
}

run "rejects_symmetric_spec_for_signing" {
  command = plan
  variables {
    key_usage = "SIGN_VERIFY"
  }
  expect_failures = [aws_kms_key.this]
}

run "rejects_ml_dsa_spec_for_key_agreement" {
  command = plan
  variables {
    key_spec            = "ML_DSA_65"
    key_usage           = "KEY_AGREEMENT"
    enable_key_rotation = false
  }
  expect_failures = [aws_kms_key.this]
}

run "accepts_every_compatible_asymmetric_combination" {
  command = plan
  variables {
    key_spec            = "ECC_NIST_P384"
    key_usage           = "KEY_AGREEMENT"
    enable_key_rotation = false
  }
  assert {
    condition     = aws_kms_key.this.customer_master_key_spec == "ECC_NIST_P384" && aws_kms_key.this.key_usage == "KEY_AGREEMENT"
    error_message = "NIST curves must be accepted for key agreement."
  }
}

run "rejects_rotation_on_asymmetric_key" {
  command = plan
  variables {
    key_spec  = "RSA_4096"
    key_usage = "SIGN_VERIFY"
  }
  expect_failures = [aws_kms_key.this]
}

run "rejects_rotation_on_hmac_key" {
  command = plan
  variables {
    key_spec  = "HMAC_512"
    key_usage = "GENERATE_VERIFY_MAC"
  }
  expect_failures = [aws_kms_key.this]
}

run "rejects_rotation_in_custom_key_store" {
  command = plan
  variables {
    custom_key_store_id = "cks-0123456789abcdef0"
  }
  expect_failures = [aws_kms_key.this]
}

run "rejects_multi_region_key_in_custom_key_store" {
  command = plan
  variables {
    custom_key_store_id = "cks-0123456789abcdef0"
    enable_key_rotation = false
    multi_region        = true
  }
  expect_failures = [aws_kms_key.this]
}

run "rejects_rotation_period_without_rotation" {
  command = plan
  variables {
    key_spec                = "RSA_2048"
    key_usage               = "SIGN_VERIFY"
    enable_key_rotation     = false
    rotation_period_in_days = 180
  }
  expect_failures = [aws_kms_key.this]
}

run "rejects_rotation_period_below_ninety_days" {
  command = plan
  variables {
    rotation_period_in_days = 30
  }
  expect_failures = [var.rotation_period_in_days]
}

run "rejects_rotation_period_above_seven_years" {
  command = plan
  variables {
    rotation_period_in_days = 2561
  }
  expect_failures = [var.rotation_period_in_days]
}

run "rejects_deletion_window_below_seven_days" {
  command = plan
  variables {
    deletion_window_in_days = 6
  }
  expect_failures = [var.deletion_window_in_days]
}

run "rejects_deletion_window_above_thirty_days" {
  command = plan
  variables {
    deletion_window_in_days = 31
  }
  expect_failures = [var.deletion_window_in_days]
}

run "rejects_policy_override_that_is_not_json" {
  command = plan
  variables {
    policy_json_override = "{not json"
  }
  expect_failures = [var.policy_json_override]
}

run "rejects_policy_override_combined_with_typed_policy_inputs" {
  command = plan
  variables {
    policy_json_override = jsonencode({ Version = "2012-10-17", Statement = [] })
    key_user_arns        = ["arn:aws:iam::123456789012:role/orders-task"]
  }
  expect_failures = [aws_kms_key.this]
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

run "rejects_reserved_alias_prefix" {
  command = plan
  variables {
    aliases = ["aws/orders"]
  }
  expect_failures = [var.aliases]
}

run "rejects_alias_with_invalid_characters" {
  command = plan
  variables {
    aliases = ["orders data"]
  }
  expect_failures = [var.aliases]
}

run "rejects_alias_with_explicit_prefix" {
  command = plan
  variables {
    aliases = ["alias/orders"]
  }
  expect_failures = [var.aliases]
}

run "rejects_grant_with_unknown_operation" {
  command = plan
  variables {
    grants = {
      app = { grantee_principal = "arn:aws:iam::123456789012:role/app", operations = ["Decrypt", "Rotate"] }
    }
  }
  expect_failures = [var.grants]
}

run "rejects_grant_without_operations" {
  command = plan
  variables {
    grants = {
      app = { grantee_principal = "arn:aws:iam::123456789012:role/app", operations = [] }
    }
  }
  expect_failures = [var.grants]
}

run "rejects_grant_with_invalid_name" {
  command = plan
  variables {
    grants = {
      "app grant" = { grantee_principal = "arn:aws:iam::123456789012:role/app", operations = ["Decrypt"] }
    }
  }
  expect_failures = [var.grants]
}

run "rejects_grant_with_non_principal_grantee" {
  command = plan
  variables {
    grants = {
      app = { grantee_principal = "lambda.amazonaws.com", operations = ["Decrypt"] }
    }
  }
  expect_failures = [var.grants]
}

run "rejects_grant_with_empty_constraints" {
  command = plan
  variables {
    grants = {
      app = { grantee_principal = "arn:aws:iam::123456789012:role/app", operations = ["Decrypt"], constraints = {} }
    }
  }
  expect_failures = [var.grants]
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

run "rejects_statement_with_reserved_sid" {
  command = plan
  variables {
    policy_statements = {
      AllowKeyUse = {
        principals = { AWS = ["arn:aws:iam::123456789012:role/reader"] }
        actions    = ["kms:DescribeKey"]
      }
    }
  }
  expect_failures = [var.policy_statements]
}

run "rejects_unconditional_allow_to_wildcard_principal" {
  command = plan
  variables {
    policy_statements = {
      AllowAnyone = {
        principals = { AWS = ["*"] }
        actions    = ["kms:Decrypt"]
      }
    }
  }
  expect_failures = [var.policy_statements]
}
