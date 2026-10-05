# Applies examples/multi-region against mock providers (nothing is created) and asserts that the
# primary and the replica end up with the same key policy. KMS keeps an
# independent policy per Region and never compares them; a divergence lets a
# principal use the key in one Region but not the other, which only surfaces
# during a failover. This guards the example's own wiring so it keeps
# demonstrating the shared-locals pattern.

mock_provider "aws" {
  mock_resource "aws_kms_key" {
    defaults = {
      arn = "arn:aws:kms:us-east-1:123456789012:key/mrk-0123456789abcdef0123456789abcdef"
    }
  }

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

mock_provider "aws" {
  alias = "replica"
}

run "primary_and_replica_policies_are_identical" {
  # apply, not plan: the replica's policy depends on the primary's ARN, which
  # is known only after the (mocked) primary is created.
  command = apply

  module {
    source = "./examples/multi-region"
  }

  variables {
    key_administrator_arns = ["arn:aws:iam::123456789012:role/kms-admin"]
    key_user_arns          = ["arn:aws:iam::123456789012:role/orders-task"]
  }

  assert {
    condition     = jsondecode(output.primary_policy) == jsondecode(output.replica_policy)
    error_message = "The multi-Region example must render the same key policy for the primary and the replica; wire every replica policy input from the shared locals."
  }

  assert {
    condition     = [for statement in jsondecode(output.replica_policy).Statement : statement.Sid] == ["EnableRootAccess", "AllowKeyAdministration", "AllowKeyUse", "AllowAttachmentOfPersistentResources"]
    error_message = "The example policy must grant root, administration, use, and grant management in both Regions."
  }
}
