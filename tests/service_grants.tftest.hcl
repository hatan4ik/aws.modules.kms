# service_grants through the root module: the DNS suffix comes from
# aws_partition (as in aws.modules.ecs), the lookup runs only when a regional
# preset needs it, and the root-only rules (symmetric key, override
# exclusivity, partition agreement) fail at plan.

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition  = "aws"
      dns_suffix = "amazonaws.com"
    }
  }
}

variables {
  description = "orders data key"
  account_id  = "123456789012"
  partition   = "aws"
}

run "renders_all_three_presets_on_the_key" {
  command = plan

  variables {
    service_grants = {
      OrdersLogs = { service = "cloudwatch-logs", resource_arn = "arn:aws:logs:us-east-1:123456789012:log-group:/aws/ecs/orders" }
      OrdersCdn  = { service = "cloudfront", resource_arn = "arn:aws:cloudfront::123456789012:distribution/E2QWRUHAPOMQZL" }
      OrdersDb = {
        service        = "secretsmanager"
        resource_arn   = "arn:aws:secretsmanager:us-east-1:123456789012:secret:orders/db-??????"
        principal_arns = ["arn:aws:iam::123456789012:role/orders-task"]
      }
    }
  }

  assert {
    condition     = [for statement in jsondecode(aws_kms_key.this.policy).Statement : statement.Sid] == ["EnableRootAccess", "OrdersCdn", "OrdersDb", "OrdersLogs"]
    error_message = "Each service grant must render one statement, sorted by Sid, after the root statement."
  }

  assert {
    condition     = jsondecode(aws_kms_key.this.policy).Statement[3].Principal.Service == ["logs.us-east-1.amazonaws.com"] && jsondecode(aws_kms_key.this.policy).Statement[2].Condition.StringEquals["kms:ViaService"] == ["secretsmanager.us-east-1.amazonaws.com"]
    error_message = "The regional presets must use the DNS suffix read from aws_partition."
  }

  assert {
    condition     = length(data.aws_partition.current) == 1 && length(data.aws_caller_identity.current) == 0
    error_message = "aws_partition must run for the DNS suffix of a regional preset even when partition is declared; aws_caller_identity must not."
  }
}

run "skips_the_partition_lookup_for_cloudfront_only" {
  command = plan

  variables {
    service_grants = {
      OrdersCdn = { service = "cloudfront", resource_arn = "arn:aws:cloudfront::123456789012:distribution/E2QWRUHAPOMQZL" }
    }
  }

  assert {
    condition     = length(data.aws_partition.current) == 0 && length(jsondecode(aws_kms_key.this.policy).Statement) == 2
    error_message = "A cloudfront-only service_grants needs no DNS suffix and must not trigger the aws_partition lookup."
  }
}

run "rejects_service_grants_on_an_asymmetric_encryption_key" {
  command = plan

  variables {
    key_spec            = "RSA_2048"
    enable_key_rotation = false
    service_grants = {
      OrdersCdn = { service = "cloudfront", resource_arn = "arn:aws:cloudfront::123456789012:distribution/E2QWRUHAPOMQZL" }
    }
  }

  expect_failures = [aws_kms_key.this]
}

run "rejects_policy_override_combined_with_service_grants" {
  command = plan

  variables {
    policy_json_override = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    service_grants = {
      OrdersCdn = { service = "cloudfront", resource_arn = "arn:aws:cloudfront::123456789012:distribution/E2QWRUHAPOMQZL" }
    }
  }

  expect_failures = [aws_kms_key.this]
}

run "rejects_a_declared_partition_that_disagrees_with_the_provider" {
  command = plan

  variables {
    partition = "aws-us-gov"
    service_grants = {
      Logs = { service = "cloudwatch-logs", resource_arn = "arn:aws-us-gov:logs:us-gov-west-1:123456789012:log-group:a" }
    }
  }

  expect_failures = [aws_kms_key.this]
}
