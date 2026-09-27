provider "aws" {
  region = var.region
}

# The replica lives in another Region, so it needs its own provider
# configuration, passed to the replica module explicitly.
provider "aws" {
  alias  = "replica"
  region = var.replica_region
}

module "primary" {
  source = "../../"

  description  = "Orders data key (multi-Region primary)"
  multi_region = true
  aliases      = ["orders/data"]

  key_administrator_arns = var.key_administrator_arns
  key_user_arns          = var.key_user_arns
}

module "replica" {
  source = "../../modules/replica"

  providers = { aws = aws.replica }

  primary_key_arn = module.primary.arn
  description     = "Orders data key (${var.replica_region} replica)"

  # Aliases are Regional: declare the same name so applications address the
  # key identically in both Regions.
  aliases = ["orders/data"]

  key_administrator_arns = var.key_administrator_arns
  key_user_arns          = var.key_user_arns
}
