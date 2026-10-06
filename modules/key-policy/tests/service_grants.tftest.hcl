# service_grants presets. Each rendered statement is compared with the
# AWS-documented grant it implements (sources in docs/DESIGN.md, "Service
# grant presets").

variables {
  account_id = "123456789012"
  dns_suffix = "amazonaws.com"
}

run "renders_the_cloudwatch_logs_preset_for_one_log_group" {
  command = plan

  variables {
    service_grants = {
      OrdersLogs = { service = "cloudwatch-logs", resource_arn = "arn:aws:logs:eu-west-1:123456789012:log-group:/aws/ecs/orders" }
    }
  }

  assert {
    condition     = output.statement_count == 2 && jsondecode(output.json).Statement[1].Sid == "OrdersLogs" && jsondecode(output.json).Statement[1].Effect == "Allow"
    error_message = "A service grant must render one Allow statement whose Sid is the map key, after the root statement."
  }

  assert {
    condition     = jsondecode(output.json).Statement[1].Principal == { Service = ["logs.eu-west-1.amazonaws.com"] }
    error_message = "The CloudWatch Logs preset must name the regional principal logs.<region>.<dns_suffix>, with the Region read from the log group ARN."
  }

  assert {
    condition     = jsondecode(output.json).Statement[1].Action == ["kms:Decrypt", "kms:Describe*", "kms:Encrypt", "kms:GenerateDataKey*", "kms:ReEncrypt*"] && jsondecode(output.json).Statement[1].Resource == ["*"]
    error_message = "The CloudWatch Logs preset must grant exactly the documented actions: kms:Encrypt, kms:Decrypt, kms:ReEncrypt*, kms:GenerateDataKey*, kms:Describe*."
  }

  assert {
    condition     = jsondecode(output.json).Statement[1].Condition == { ArnEquals = { "kms:EncryptionContext:aws:logs:arn" = ["arn:aws:logs:eu-west-1:123456789012:log-group:/aws/ecs/orders"] } }
    error_message = "A CloudWatch Logs grant for one log group must be scoped with ArnEquals on kms:EncryptionContext:aws:logs:arn and nothing else."
  }
}

run "uses_arnlike_for_a_wildcard_log_group_and_the_partition_dns_suffix" {
  command = plan

  variables {
    partition  = "aws-cn"
    dns_suffix = "amazonaws.com.cn"
    service_grants = {
      EcsLogs = { service = "cloudwatch-logs", resource_arn = "arn:aws-cn:logs:cn-north-1:123456789012:log-group:/aws/ecs/*" }
    }
  }

  assert {
    condition     = jsondecode(output.json).Statement[1].Principal.Service == ["logs.cn-north-1.amazonaws.com.cn"]
    error_message = "The CloudWatch Logs principal must use the partition's DNS suffix (amazonaws.com.cn in aws-cn)."
  }

  assert {
    condition     = jsondecode(output.json).Statement[1].Condition == { ArnLike = { "kms:EncryptionContext:aws:logs:arn" = ["arn:aws-cn:logs:cn-north-1:123456789012:log-group:/aws/ecs/*"] } }
    error_message = "A log group ARN with a wildcard must render ArnLike, not ArnEquals."
  }
}

run "renders_the_cloudfront_preset_identical_to_aws_modules_cloudfront" {
  command = plan

  variables {
    service_grants = {
      AllowCloudFrontServicePrincipalSSEKMSDecrypt = { service = "cloudfront", resource_arn = "arn:aws:cloudfront::123456789012:distribution/E2QWRUHAPOMQZL" }
    }
  }

  # aws.modules.cloudfront's required_kms_key_policy_json, with single values
  # as one-element lists (the AWS provider treats them as equivalent).
  assert {
    condition = jsondecode(output.json).Statement[1] == {
      Sid       = "AllowCloudFrontServicePrincipalSSEKMSDecrypt"
      Effect    = "Allow"
      Principal = { Service = ["cloudfront.amazonaws.com"] }
      Action    = ["kms:Decrypt"]
      Resource  = ["*"]
      Condition = { StringEquals = { "AWS:SourceArn" = ["arn:aws:cloudfront::123456789012:distribution/E2QWRUHAPOMQZL"] } }
    }
    error_message = "The CloudFront preset must grant cloudfront.amazonaws.com only kms:Decrypt, scoped by AWS:SourceArn to the one distribution."
  }
}

run "renders_the_secretsmanager_preset_for_an_exact_secret" {
  command = plan

  variables {
    service_grants = {
      OrdersDbSecret = {
        service        = "secretsmanager"
        resource_arn   = "arn:aws:secretsmanager:us-east-1:123456789012:secret:orders/db-AbCdEf"
        principal_arns = ["arn:aws:iam::123456789012:role/orders-task", "arn:aws:iam::123456789012:role/db-rotation"]
      }
    }
  }

  assert {
    condition     = jsondecode(output.json).Statement[1].Principal == { AWS = ["arn:aws:iam::123456789012:role/db-rotation", "arn:aws:iam::123456789012:role/orders-task"] }
    error_message = "Secrets Manager calls KMS with the caller's identity: the grantees must be the sorted principal_arns, never a service principal."
  }

  assert {
    condition     = jsondecode(output.json).Statement[1].Action == ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey"]
    error_message = "The Secrets Manager preset must grant exactly the operations Secrets Manager calls with a secret's encryption context: Decrypt, Encrypt, GenerateDataKey."
  }

  assert {
    condition = jsondecode(output.json).Statement[1].Condition == {
      StringEquals = {
        "kms:EncryptionContext:SecretARN" = ["arn:aws:secretsmanager:us-east-1:123456789012:secret:orders/db-AbCdEf"]
        "kms:ViaService"                  = ["secretsmanager.us-east-1.amazonaws.com"]
      }
    }
    error_message = "An exact secret ARN must be scoped with StringEquals on kms:ViaService (the secret's Region) and kms:EncryptionContext:SecretARN."
  }
}

run "uses_stringlike_for_a_secret_arn_pattern" {
  command = plan

  variables {
    service_grants = {
      OrdersDbSecret = {
        service        = "secretsmanager"
        resource_arn   = "arn:aws:secretsmanager:us-east-1:123456789012:secret:orders/db-??????"
        principal_arns = ["arn:aws:iam::123456789012:role/orders-task"]
      }
    }
  }

  assert {
    condition = jsondecode(output.json).Statement[1].Condition == {
      StringEquals = { "kms:ViaService" = ["secretsmanager.us-east-1.amazonaws.com"] }
      StringLike   = { "kms:EncryptionContext:SecretARN" = ["arn:aws:secretsmanager:us-east-1:123456789012:secret:orders/db-??????"] }
    }
    error_message = "A secret ARN with ? or * must move only the SecretARN condition to StringLike; kms:ViaService stays StringEquals."
  }
}

run "orders_presets_after_service_principals_and_before_statements" {
  command = plan

  variables {
    key_service_principals = { "cloudtrail.amazonaws.com" = {} }
    statements = {
      AAAFirstDeclared = {
        principals = { AWS = ["arn:aws:iam::123456789012:role/reader"] }
        actions    = ["kms:DescribeKey"]
      }
    }
    service_grants = {
      ZLogs = { service = "cloudwatch-logs", resource_arn = "arn:aws:logs:us-east-1:123456789012:log-group:z" }
      ALogs = { service = "cloudwatch-logs", resource_arn = "arn:aws:logs:us-east-1:123456789012:log-group:a" }
    }
  }

  assert {
    condition     = [for statement in jsondecode(output.json).Statement : statement.Sid] == ["EnableRootAccess", "AllowServiceUseCloudtrailAmazonawsCom", "ALogs", "ZLogs", "AAAFirstDeclared"]
    error_message = "service_grants must render after key_service_principals and before statements, sorted by Sid."
  }
}

run "renders_nothing_without_service_grants" {
  command = plan

  variables {
    dns_suffix = null
  }

  assert {
    condition     = output.statement_count == 1
    error_message = "No service grant may render when service_grants is empty, and dns_suffix is then not required."
  }
}

run "rejects_unknown_service" {
  command = plan

  variables {
    service_grants = {
      Lambda = { service = "lambda", resource_arn = "arn:aws:lambda:us-east-1:123456789012:function:orders" }
    }
  }

  expect_failures = [var.service_grants]
}

run "rejects_reserved_sid" {
  command = plan

  variables {
    service_grants = {
      AllowServiceUseLogs = { service = "cloudwatch-logs", resource_arn = "arn:aws:logs:us-east-1:123456789012:log-group:a" }
    }
  }

  expect_failures = [var.service_grants]
}

run "rejects_non_alphanumeric_sid" {
  command = plan

  variables {
    service_grants = {
      "orders-logs" = { service = "cloudwatch-logs", resource_arn = "arn:aws:logs:us-east-1:123456789012:log-group:a" }
    }
  }

  expect_failures = [var.service_grants]
}

run "rejects_log_group_arn_with_trailing_wildcard_suffix" {
  command = plan

  variables {
    service_grants = {
      Logs = { service = "cloudwatch-logs", resource_arn = "arn:aws:logs:us-east-1:123456789012:log-group:/aws/ecs/orders:*" }
    }
  }

  expect_failures = [var.service_grants]
}

run "rejects_cloudwatch_logs_grant_with_a_non_log_group_arn" {
  command = plan

  variables {
    service_grants = {
      Logs = { service = "cloudwatch-logs", resource_arn = "arn:aws:s3:::orders-logs" }
    }
  }

  expect_failures = [var.service_grants]
}

run "rejects_wildcard_cloudfront_distribution" {
  command = plan

  variables {
    service_grants = {
      Cdn = { service = "cloudfront", resource_arn = "arn:aws:cloudfront::123456789012:distribution/*" }
    }
  }

  expect_failures = [var.service_grants]
}

run "rejects_cloudfront_outside_the_aws_partition" {
  command = plan

  variables {
    service_grants = {
      Cdn = { service = "cloudfront", resource_arn = "arn:aws-cn:cloudfront::123456789012:distribution/E2QWRUHAPOMQZL" }
    }
  }

  expect_failures = [var.service_grants]
}

run "rejects_secretsmanager_without_principal_arns" {
  command = plan

  variables {
    service_grants = {
      Secret = { service = "secretsmanager", resource_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:orders-AbCdEf" }
    }
  }

  expect_failures = [var.service_grants]
}

run "rejects_secretsmanager_with_a_non_principal_arn" {
  command = plan

  variables {
    service_grants = {
      Secret = {
        service        = "secretsmanager"
        resource_arn   = "arn:aws:secretsmanager:us-east-1:123456789012:secret:orders-AbCdEf"
        principal_arns = ["*"]
      }
    }
  }

  expect_failures = [var.service_grants]
}

run "rejects_principal_arns_on_a_service_principal_preset" {
  command = plan

  variables {
    service_grants = {
      Logs = {
        service        = "cloudwatch-logs"
        resource_arn   = "arn:aws:logs:us-east-1:123456789012:log-group:a"
        principal_arns = ["arn:aws:iam::123456789012:role/orders-task"]
      }
    }
  }

  expect_failures = [var.service_grants]
}

run "rejects_secretsmanager_with_a_non_secret_arn" {
  command = plan

  variables {
    service_grants = {
      Secret = {
        service        = "secretsmanager"
        resource_arn   = "arn:aws:ssm:us-east-1:123456789012:parameter/orders"
        principal_arns = ["arn:aws:iam::123456789012:role/orders-task"]
      }
    }
  }

  expect_failures = [var.service_grants]
}

run "requires_dns_suffix_for_a_regional_preset" {
  command = plan

  variables {
    dns_suffix = null
    service_grants = {
      Logs = { service = "cloudwatch-logs", resource_arn = "arn:aws:logs:us-east-1:123456789012:log-group:a" }
    }
  }

  expect_failures = [output.json]
}

run "does_not_require_dns_suffix_for_cloudfront" {
  command = plan

  variables {
    dns_suffix = null
    service_grants = {
      Cdn = { service = "cloudfront", resource_arn = "arn:aws:cloudfront::123456789012:distribution/E2QWRUHAPOMQZL" }
    }
  }

  assert {
    condition     = output.statement_count == 2
    error_message = "The CloudFront preset uses a global principal and must not need dns_suffix."
  }
}

run "rejects_resource_arn_in_another_partition" {
  command = plan

  variables {
    partition = "aws-us-gov"
    service_grants = {
      Logs = { service = "cloudwatch-logs", resource_arn = "arn:aws:logs:us-east-1:123456789012:log-group:a" }
    }
  }

  expect_failures = [output.json]
}

run "rejects_presets_on_a_non_encryption_key" {
  command = plan

  variables {
    key_usage = "SIGN_VERIFY"
    service_grants = {
      Logs = { service = "cloudwatch-logs", resource_arn = "arn:aws:logs:us-east-1:123456789012:log-group:a" }
    }
  }

  expect_failures = [output.json]
}

run "rejects_a_sid_shared_with_statements" {
  command = plan

  variables {
    statements = {
      Logs = {
        principals = { AWS = ["arn:aws:iam::123456789012:role/reader"] }
        actions    = ["kms:DescribeKey"]
      }
    }
    service_grants = {
      Logs = { service = "cloudwatch-logs", resource_arn = "arn:aws:logs:us-east-1:123456789012:log-group:a" }
    }
  }

  expect_failures = [output.json]
}

run "rejects_malformed_dns_suffix" {
  command = plan

  variables {
    dns_suffix = "amazonaws"
  }

  expect_failures = [var.dns_suffix]
}
