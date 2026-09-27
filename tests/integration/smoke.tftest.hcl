# Integration suite: real apply in the caller's own account.
#
# Requires AWS credentials and a region from the environment (for example
# AWS_PROFILE and AWS_REGION, or the OIDC role assumed by the integration
# workflow). Nothing is hard-coded: the setup module resolves the caller's
# identity and a random suffix, the key is created with two aliases, the caller
# as administrator and user, one grant, and the shortest deletion window, the
# results are asserted against the real API, and everything is destroyed at
# the end of the file.
#
# KMS cannot delete a key immediately: on destroy it is scheduled for deletion
# and stays visible as PendingDeletion for deletion_window_in_days (7 here)
# before AWS removes it. Aliases and the grant are removed at once, and every
# alias carries the random suffix, so re-runs never collide with a pending key.
#
# Run: terraform init -backend=false -test-directory=tests/integration
#      terraform test -test-directory=tests/integration -filter=tests/integration/smoke.tftest.hcl

provider "aws" {}

run "setup" {
  module {
    source = "./tests/integration/setup"
  }

  variables {
    name_prefix = "ksm-it"
  }
}

run "smoke" {
  variables {
    description             = "aws.modules.ksm integration ${run.setup.name}"
    aliases                 = ["${run.setup.name}/data", "${run.setup.name}/data-v2"]
    deletion_window_in_days = 7
    tags                    = run.setup.tags

    # account_id and partition stay null on purpose: the suite proves the
    # module's lookup fallback against the real APIs and asserts below that it
    # resolved to the caller's account.

    # The caller's own identity administers and uses the key, so the suite
    # never names a principal it did not resolve at run time.
    key_administrator_arns = [run.setup.principal_arn]
    key_user_arns          = [run.setup.principal_arn]

    grants = {
      reader = {
        grantee_principal = run.setup.principal_arn
        operations        = ["Decrypt", "DescribeKey"]
      }
    }
  }

  assert {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", output.key_id))
    error_message = "KMS must have returned a single-Region key ID."
  }

  assert {
    condition     = output.arn == "arn:${run.setup.partition}:kms:${run.setup.region}:${run.setup.account_id}:key/${output.key_id}"
    error_message = "The key ARN must be in the caller's partition, Region, and account."
  }

  assert {
    condition     = output.account_id == run.setup.account_id && output.partition == run.setup.partition
    error_message = "With account_id and partition null, the lookup fallback must resolve to the caller's account and partition."
  }

  assert {
    condition     = aws_kms_key.this.enable_key_rotation == true && aws_kms_key.this.deletion_window_in_days == 7 && aws_kms_key.this.key_usage == "ENCRYPT_DECRYPT" && aws_kms_key.this.customer_master_key_spec == "SYMMETRIC_DEFAULT"
    error_message = "The key must be a rotating symmetric encryption key with the 7-day deletion window."
  }

  assert {
    condition     = [for statement in jsondecode(output.policy).Statement : statement.Sid] == ["EnableRootAccess", "AllowKeyAdministration", "AllowKeyUse", "AllowAttachmentOfPersistentResources"]
    error_message = "KMS must have accepted the composed policy with the root, administration, use, and grant-management statements."
  }

  assert {
    condition     = output.alias_names["${run.setup.name}/data"] == "alias/${run.setup.name}/data" && output.alias_names["${run.setup.name}/data-v2"] == "alias/${run.setup.name}/data-v2"
    error_message = "Both aliases must exist under their declared names."
  }

  assert {
    condition     = length(output.alias_arns) == 2 && alltrue([for arn in values(output.alias_arns) : startswith(arn, "arn:${run.setup.partition}:kms:${run.setup.region}:${run.setup.account_id}:alias/")])
    error_message = "Both alias ARNs must be in the caller's partition, Region, and account."
  }

  assert {
    condition     = keys(output.grant_ids) == ["reader"] && length(output.grant_ids["reader"]) > 0
    error_message = "The grant must have been created and its ID exposed under the declared name."
  }

  assert {
    condition     = aws_kms_key.this.tags["Name"] == "${run.setup.name}/data" && aws_kms_key.this.tags["Disposable"] == "true"
    error_message = "The Name tag must be the first alias and the fixture tags must be preserved."
  }
}
