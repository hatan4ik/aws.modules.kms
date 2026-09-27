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

run "creates_one_alias_per_name" {
  command = plan

  variables {
    aliases = ["orders/data", "app-orders_v1"]
  }

  assert {
    condition     = aws_kms_alias.this["orders/data"].name == "alias/orders/data" && aws_kms_alias.this["app-orders_v1"].name == "alias/app-orders_v1"
    error_message = "Every alias must render with the alias/ prefix under its own key."
  }

  assert {
    condition     = output.alias_names == { "app-orders_v1" = "alias/app-orders_v1", "orders/data" = "alias/orders/data" } && keys(output.alias_arns) == ["app-orders_v1", "orders/data"]
    error_message = "Alias outputs must be keyed by the declared alias name."
  }
}

run "creates_one_grant_per_entry_with_constraints" {
  command = plan

  variables {
    grants = {
      ebs = {
        grantee_principal  = "arn:aws:iam::123456789012:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"
        operations         = ["Decrypt", "Encrypt", "GenerateDataKeyWithoutPlaintext", "ReEncryptFrom", "ReEncryptTo", "CreateGrant", "DescribeKey"]
        retiring_principal = "arn:aws:iam::123456789012:role/kms-admin"
        constraints        = { encryption_context_subset = { "aws:ebs:id" = "vol-0123456789abcdef0" } }
        retire_on_delete   = true
      }
      lambda = {
        grantee_principal = "arn:aws:iam::123456789012:role/orders-lambda"
        operations        = ["Decrypt"]
        constraints       = { encryption_context_equals = { "aws:lambda:FunctionArn" = "arn:aws:lambda:us-east-1:123456789012:function:orders" } }
      }
    }
  }

  assert {
    condition     = aws_kms_grant.this["ebs"].name == "ebs" && aws_kms_grant.this["ebs"].grantee_principal == "arn:aws:iam::123456789012:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling" && aws_kms_grant.this["ebs"].retiring_principal == "arn:aws:iam::123456789012:role/kms-admin" && aws_kms_grant.this["ebs"].retire_on_delete == true
    error_message = "Grants must be named by their key and carry their principals and retirement setting."
  }

  assert {
    condition     = aws_kms_grant.this["ebs"].operations == toset(["CreateGrant", "Decrypt", "DescribeKey", "Encrypt", "GenerateDataKeyWithoutPlaintext", "ReEncryptFrom", "ReEncryptTo"])
    error_message = "Grant operations must be applied as declared."
  }

  assert {
    condition     = tolist(aws_kms_grant.this["ebs"].constraints)[0].encryption_context_subset["aws:ebs:id"] == "vol-0123456789abcdef0" && tolist(aws_kms_grant.this["lambda"].constraints)[0].encryption_context_equals["aws:lambda:FunctionArn"] == "arn:aws:lambda:us-east-1:123456789012:function:orders"
    error_message = "Encryption-context constraints must render as subset or equals as declared."
  }

  assert {
    condition     = aws_kms_grant.this["lambda"].retire_on_delete == false && aws_kms_grant.this["lambda"].retiring_principal == null
    error_message = "A grant without a retiring principal must default to revocation on destroy."
  }

  assert {
    condition     = keys(output.grant_ids) == ["ebs", "lambda"] && keys(output.grant_tokens) == ["ebs", "lambda"]
    error_message = "Grant outputs must be keyed by the declared grant name."
  }
}
