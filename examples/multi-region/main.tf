provider "aws" {
  region = var.region
}

# The replica lives in another Region, so it needs its own provider
# configuration, passed to the replica module explicitly.
provider "aws" {
  alias  = "replica"
  region = var.replica_region
}

# A multi-Region primary and each of its replicas carry independent key
# policies: KMS never copies or compares them. Every policy input is declared
# once here and passed to both modules, so a principal that can use the key in
# one Region can use it in the other. Changing access means changing these
# locals, never one module call alone.
locals {
  # A replica inherits the primary's real key usage; the replica module needs
  # it only to grant the matching use actions, so it must come from the same
  # value as the primary's.
  key_usage = "ENCRYPT_DECRYPT"

  key_policy = {
    enable_root_administration = true
    key_administrator_arns     = var.key_administrator_arns
    key_user_arns              = var.key_user_arns
    key_service_principals     = {}
    policy_statements          = {}
  }
}

module "primary" {
  source = "../../"

  description  = "Orders data key (multi-Region primary)"
  key_usage    = local.key_usage
  multi_region = true
  aliases      = ["orders/data"]

  enable_root_administration = local.key_policy.enable_root_administration
  key_administrator_arns     = local.key_policy.key_administrator_arns
  key_user_arns              = local.key_policy.key_user_arns
  key_service_principals     = local.key_policy.key_service_principals
  policy_statements          = local.key_policy.policy_statements
}

module "replica" {
  source = "../../modules/replica"

  providers = { aws = aws.replica }

  primary_key_arn = module.primary.arn
  description     = "Orders data key (${var.replica_region} replica)"
  key_usage       = local.key_usage

  # Aliases are Regional: declare the same name so applications address the
  # key identically in both Regions.
  aliases = ["orders/data"]

  enable_root_administration = local.key_policy.enable_root_administration
  key_administrator_arns     = local.key_policy.key_administrator_arns
  key_user_arns              = local.key_policy.key_user_arns
  key_service_principals     = local.key_policy.key_service_principals
  policy_statements          = local.key_policy.policy_statements
}
