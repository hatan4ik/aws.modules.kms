# Disposable prerequisites for the integration suites. A KMS key needs no
# fixture infrastructure, only principals to name in its policy and a unique
# name for its aliases: the caller's own identity, resolved at run time, is the
# key's administrator, user, and grantee, and a random suffix keeps concurrent
# runs apart. Nothing here is shared, long-lived, or tied to an account; the
# key under test is the only cloud resource and `terraform test` destroys it.

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_region" "current" {}

resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  name = "${var.name_prefix}-${random_id.suffix.hex}"

  tags = merge(var.tags, {
    IntegrationTest = "aws.modules.ksm"
    Disposable      = "true"
  })
}
