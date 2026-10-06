mock_provider "aws" {}

variables {
  primary_key_arn = "arn:aws:kms:us-east-1:123456789012:key/mrk-0123456789abcdef0123456789abcdef"
  description     = "orders data key replica"
  key_usage       = "ENCRYPT_DECRYPT"
  tags            = { Environment = "test", Owner = "platform" }
}

run "replicates_with_safe_defaults_and_derived_identity" {
  command = plan

  assert {
    condition     = aws_kms_replica_key.this.primary_key_arn == "arn:aws:kms:us-east-1:123456789012:key/mrk-0123456789abcdef0123456789abcdef" && aws_kms_replica_key.this.description == "orders data key replica"
    error_message = "The replica must point at the declared primary key and carry the declared description."
  }

  assert {
    condition     = aws_kms_replica_key.this.deletion_window_in_days == 30 && aws_kms_replica_key.this.enabled == true && aws_kms_replica_key.this.bypass_policy_lockout_safety_check == false
    error_message = "A replica must default to a 30-day deletion window, enabled, with the policy lockout safety check on."
  }

  assert {
    condition     = length(jsondecode(aws_kms_replica_key.this.policy).Statement) == 1 && jsondecode(aws_kms_replica_key.this.policy).Statement[0].Sid == "EnableRootAccess"
    error_message = "The default replica policy must contain only the root administration statement."
  }

  assert {
    condition     = jsondecode(aws_kms_replica_key.this.policy).Statement[0].Principal.AWS == ["arn:aws:iam::123456789012:root"]
    error_message = "The account and partition of the root principal must be parsed from primary_key_arn, not looked up."
  }

  assert {
    condition     = aws_kms_replica_key.this.tags["Name"] == "orders data key replica" && aws_kms_replica_key.this.tags["Owner"] == "platform"
    error_message = "Caller tags must be preserved and a Name tag added from the description."
  }

  assert {
    condition     = length(aws_kms_alias.this) == 0 && length(output.alias_arns) == 0 && length(output.alias_names) == 0
    error_message = "No alias may render unless declared."
  }

  assert {
    condition     = output.account_id == "123456789012" && output.partition == "aws" && output.policy == aws_kms_replica_key.this.policy
    error_message = "Outputs must expose the derived account, partition, and the applied policy."
  }
}

run "derives_partition_from_a_govcloud_primary" {
  command = plan

  variables {
    primary_key_arn = "arn:aws-us-gov:kms:us-gov-west-1:210987654321:key/mrk-0123456789abcdef0123456789abcdef"
  }

  assert {
    condition     = jsondecode(aws_kms_replica_key.this.policy).Statement[0].Principal.AWS == ["arn:aws-us-gov:iam::210987654321:root"] && output.partition == "aws-us-gov" && output.account_id == "210987654321"
    error_message = "The partition and account must follow the primary key ARN."
  }
}

run "composes_policy_with_replication_aware_administrators" {
  command = plan

  variables {
    key_usage              = "SIGN_VERIFY"
    key_administrator_arns = ["arn:aws:iam::123456789012:role/kms-admin"]
    key_user_arns          = ["arn:aws:iam::123456789012:role/signer"]
    key_service_principals = {
      "lambda.amazonaws.com" = { conditions = [{ test = "StringEquals", variable = "aws:SourceAccount", values = ["123456789012"] }] }
    }
    policy_statements = {
      AllowCrossAccountVerify = {
        principals = { AWS = ["arn:aws:iam::210987654321:root"] }
        actions    = ["kms:Verify", "kms:GetPublicKey"]
      }
    }
  }

  assert {
    condition     = length(jsondecode(aws_kms_replica_key.this.policy).Statement) == 6
    error_message = "Root, administration, use, grant management, the service principal, and the declared statement must all render."
  }

  assert {
    condition     = contains(jsondecode(aws_kms_replica_key.this.policy).Statement[1].Action, "kms:ReplicateKey")
    error_message = "Administrators of a replica must be able to replicate the multi-Region key."
  }

  assert {
    condition     = jsondecode(aws_kms_replica_key.this.policy).Statement[2].Action == ["kms:DescribeKey", "kms:GetPublicKey", "kms:Sign", "kms:Verify"]
    error_message = "Users must receive the use actions of the declared key_usage."
  }

  assert {
    condition     = jsondecode(aws_kms_replica_key.this.policy).Statement[4].Principal.Service == ["lambda.amazonaws.com"] && jsondecode(aws_kms_replica_key.this.policy).Statement[5].Sid == "AllowCrossAccountVerify"
    error_message = "Service principals and declared statements must render after the built-in statements."
  }
}

run "creates_one_alias_per_name_and_names_the_key_after_the_first" {
  command = plan

  variables {
    aliases = ["orders/data", "app-orders"]
  }

  assert {
    condition     = aws_kms_alias.this["orders/data"].name == "alias/orders/data" && aws_kms_alias.this["app-orders"].name == "alias/app-orders"
    error_message = "Every alias must render with the alias/ prefix under its own key."
  }

  assert {
    condition     = output.alias_names == { "app-orders" = "alias/app-orders", "orders/data" = "alias/orders/data" } && keys(output.alias_arns) == ["app-orders", "orders/data"]
    error_message = "Alias outputs must be keyed by the declared alias name."
  }

  assert {
    condition     = aws_kms_replica_key.this.tags["Name"] == "app-orders"
    error_message = "The Name tag must be the first alias in sorted order when aliases exist."
  }
}

run "keeps_a_caller_supplied_name_tag" {
  command = plan

  variables {
    tags = { Name = "custom" }
  }

  assert {
    condition     = aws_kms_replica_key.this.tags["Name"] == "custom"
    error_message = "A caller Name tag must never be overridden."
  }
}

run "applies_a_caller_policy_verbatim" {
  command = plan

  variables {
    enable_root_administration = false
    policy_json_override = jsonencode({
      Version   = "2012-10-17"
      Statement = [{ Sid = "Custom", Effect = "Allow", Principal = { AWS = "arn:aws:iam::123456789012:role/owner" }, Action = "kms:*", Resource = "*" }]
    })
  }

  assert {
    condition     = aws_kms_replica_key.this.policy == var.policy_json_override && output.policy == var.policy_json_override
    error_message = "A supplied policy document must be applied unchanged."
  }
}

run "rejects_policy_override_combined_with_typed_policy_inputs" {
  command = plan

  variables {
    policy_json_override = jsonencode({ Version = "2012-10-17", Statement = [] })
    key_user_arns        = ["arn:aws:iam::123456789012:role/orders-task"]
  }

  expect_failures = [aws_kms_replica_key.this]
}

run "rejects_policy_override_that_is_not_json" {
  command = plan

  variables {
    policy_json_override = "{not json"
  }

  expect_failures = [var.policy_json_override]
}

run "rejects_single_region_primary_key_arn" {
  command = plan

  variables {
    primary_key_arn = "arn:aws:kms:us-east-1:123456789012:key/0123456789abcdef0123456789abcdef"
  }

  expect_failures = [var.primary_key_arn]
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

run "rejects_deletion_window_outside_kms_range" {
  command = plan

  variables {
    deletion_window_in_days = 6
  }

  expect_failures = [var.deletion_window_in_days]
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

run "rejects_policy_override_without_statement_element" {
  command = plan

  variables {
    policy_json_override = jsonencode({ Version = "2012-10-17" })
  }

  expect_failures = [var.policy_json_override]
}

run "warns_when_the_policy_lockout_safety_check_is_bypassed" {
  command = plan

  variables {
    bypass_policy_lockout_safety_check = true
  }

  expect_failures = [check.policy_lockout_safety_check_bypassed]
}

run "truncates_a_long_description_to_the_tag_value_limit" {
  command = plan

  variables {
    description = join("", [for i in range(300) : "d"])
  }

  assert {
    condition     = length(aws_kms_replica_key.this.tags["Name"]) == 256 && length(aws_kms_replica_key.this.description) == 300
    error_message = "A description longer than 256 characters must be truncated in the Name tag (the AWS tag value limit) and kept whole as the replica description."
  }
}

run "grants_the_use_actions_of_the_declared_key_usage" {
  command = plan

  variables {
    key_usage     = "GENERATE_VERIFY_MAC"
    key_user_arns = ["arn:aws:iam::123456789012:role/mac"]
  }

  assert {
    condition     = jsondecode(aws_kms_replica_key.this.policy).Statement[1].Action == ["kms:DescribeKey", "kms:GenerateMac", "kms:VerifyMac"]
    error_message = "The replica policy must grant the use actions of the declared key_usage, which must match the primary's."
  }
}

run "renders_service_grants_with_the_provider_dns_suffix" {
  command = plan

  override_data {
    target = data.aws_partition.current[0]
    values = {
      partition  = "aws"
      dns_suffix = "amazonaws.com"
    }
  }

  variables {
    service_grants = {
      OrdersLogs = { service = "cloudwatch-logs", resource_arn = "arn:aws:logs:eu-west-1:123456789012:log-group:/aws/ecs/orders" }
    }
  }

  assert {
    condition     = jsondecode(aws_kms_replica_key.this.policy).Statement[1].Sid == "OrdersLogs" && jsondecode(aws_kms_replica_key.this.policy).Statement[1].Principal.Service == ["logs.eu-west-1.amazonaws.com"]
    error_message = "The replica must render service_grants through the shared renderer with the DNS suffix of its provider's partition."
  }

  assert {
    condition     = length(data.aws_partition.current) == 1
    error_message = "A regional preset must trigger the replica's aws_partition lookup."
  }
}

run "performs_no_lookup_without_regional_service_grants" {
  command = plan

  variables {
    service_grants = {
      OrdersCdn = { service = "cloudfront", resource_arn = "arn:aws:cloudfront::123456789012:distribution/E2QWRUHAPOMQZL" }
    }
  }

  assert {
    condition     = length(data.aws_partition.current) == 0
    error_message = "The replica must perform no lookup unless a regional preset needs the DNS suffix."
  }
}

run "rejects_a_provider_in_another_partition_than_the_primary" {
  command = plan

  override_data {
    target = data.aws_partition.current[0]
    values = {
      partition  = "aws-cn"
      dns_suffix = "amazonaws.com.cn"
    }
  }

  variables {
    service_grants = {
      OrdersLogs = { service = "cloudwatch-logs", resource_arn = "arn:aws:logs:eu-west-1:123456789012:log-group:/aws/ecs/orders" }
    }
  }

  expect_failures = [aws_kms_replica_key.this]
}

run "rejects_policy_override_combined_with_service_grants" {
  command = plan

  variables {
    policy_json_override = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    service_grants = {
      OrdersCdn = { service = "cloudfront", resource_arn = "arn:aws:cloudfront::123456789012:distribution/E2QWRUHAPOMQZL" }
    }
  }

  expect_failures = [aws_kms_replica_key.this]
}
