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
  tags        = { Environment = "test", Owner = "platform" }
}

run "creates_rotating_symmetric_key_with_root_policy" {
  command = plan

  assert {
    condition     = aws_kms_key.this.description == "orders data key" && aws_kms_key.this.key_usage == "ENCRYPT_DECRYPT" && aws_kms_key.this.customer_master_key_spec == "SYMMETRIC_DEFAULT"
    error_message = "The default key must be a symmetric encryption key with the declared description."
  }

  assert {
    condition     = aws_kms_key.this.enable_key_rotation == true && aws_kms_key.this.deletion_window_in_days == 30
    error_message = "Rotation must be on and the deletion window must be the 30-day maximum by default."
  }

  assert {
    condition     = aws_kms_key.this.multi_region == false && aws_kms_key.this.is_enabled == true && aws_kms_key.this.bypass_policy_lockout_safety_check == false && aws_kms_key.this.custom_key_store_id == null
    error_message = "A default key is single-Region, enabled, in the AWS key store, with the policy lockout safety check on."
  }

  assert {
    condition     = length(jsondecode(aws_kms_key.this.policy).Statement) == 1 && jsondecode(aws_kms_key.this.policy).Statement[0].Sid == "EnableRootAccess"
    error_message = "The default policy must contain only the root administration statement."
  }

  assert {
    condition     = jsondecode(aws_kms_key.this.policy).Statement[0].Principal.AWS == ["arn:aws:iam::123456789012:root"] && jsondecode(aws_kms_key.this.policy).Statement[0].Action == ["kms:*"]
    error_message = "The root statement must grant kms:* to the account root looked up when account_id and partition are null."
  }

  assert {
    condition     = length(data.aws_caller_identity.current) == 1 && length(data.aws_partition.current) == 1
    error_message = "The identity and partition lookups must run only as a fallback for null inputs."
  }

  assert {
    condition     = aws_kms_key.this.tags["Name"] == "orders data key" && aws_kms_key.this.tags["Owner"] == "platform"
    error_message = "Caller tags must be preserved and a Name tag added from the description."
  }

  assert {
    condition     = length(aws_kms_alias.this) == 0 && length(aws_kms_grant.this) == 0
    error_message = "No alias or grant may render unless declared."
  }

  assert {
    condition     = output.account_id == "123456789012" && output.partition == "aws" && output.key_usage == "ENCRYPT_DECRYPT" && output.key_spec == "SYMMETRIC_DEFAULT" && output.multi_region == false
    error_message = "Outputs must expose the resolved identity and the key's cryptographic configuration."
  }

  assert {
    condition     = output.policy == aws_kms_key.this.policy && length(output.alias_arns) == 0 && length(output.alias_names) == 0 && length(output.grant_ids) == 0
    error_message = "Outputs must expose the applied policy and empty alias and grant maps."
  }
}

run "uses_declared_account_and_partition_without_lookups" {
  command = plan

  variables {
    account_id = "210987654321"
    partition  = "aws-us-gov"
  }

  assert {
    condition     = length(data.aws_caller_identity.current) == 0 && length(data.aws_partition.current) == 0
    error_message = "No data source may run when account_id and partition are declared."
  }

  assert {
    condition     = jsondecode(aws_kms_key.this.policy).Statement[0].Principal.AWS == ["arn:aws-us-gov:iam::210987654321:root"] && output.account_id == "210987654321" && output.partition == "aws-us-gov"
    error_message = "Declared identity inputs must flow into the policy and the outputs."
  }
}

run "names_the_key_after_the_first_alias" {
  command = plan

  variables {
    aliases = ["orders/data", "app-orders"]
  }

  assert {
    condition     = aws_kms_key.this.tags["Name"] == "app-orders"
    error_message = "The Name tag must be the first alias in sorted order when aliases exist."
  }
}

run "keeps_a_caller_supplied_name_tag" {
  command = plan

  variables {
    tags = { Name = "custom" }
  }

  assert {
    condition     = aws_kms_key.this.tags["Name"] == "custom"
    error_message = "A caller Name tag must never be overridden."
  }
}

run "configures_rotation_period_and_multi_region_primary" {
  command = plan

  variables {
    rotation_period_in_days = 180
    multi_region            = true
    key_administrator_arns  = ["arn:aws:iam::123456789012:role/kms-admin"]
  }

  assert {
    condition     = aws_kms_key.this.rotation_period_in_days == 180 && aws_kms_key.this.multi_region == true && output.multi_region == true
    error_message = "The rotation period and multi-Region flag must be applied and exposed."
  }

  assert {
    condition     = contains(jsondecode(aws_kms_key.this.policy).Statement[1].Action, "kms:ReplicateKey")
    error_message = "Administrators of a multi-Region primary must be able to replicate it."
  }
}

run "warns_when_root_administration_is_disabled_without_administrators" {
  command = plan

  variables {
    enable_root_administration = false
    key_user_arns              = ["arn:aws:iam::123456789012:role/orders-task"]
  }

  expect_failures = [check.root_administration_disabled]
}

run "warns_when_a_symmetric_key_does_not_rotate" {
  command = plan

  variables {
    enable_key_rotation = false
  }

  expect_failures = [check.rotation_disabled_for_symmetric_key]
}
