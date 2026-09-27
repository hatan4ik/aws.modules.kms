provider "aws" {
  region = var.region
}

# One module call is one key. A set of keys is a for_each over the module
# block, so each key keeps its own plan, its own validation errors, and its
# own lifecycle while sharing the account and Region.
module "key" {
  source   = "../../"
  for_each = var.keys

  description = each.value.description
  aliases     = ["${var.alias_prefix}/${each.key}"]
  tags        = merge(var.tags, { Purpose = each.key })

  account_id = var.account_id
  partition  = "aws"

  key_administrator_arns = var.key_administrator_arns
  key_user_arns          = each.value.key_user_arns
  key_service_principals = each.value.key_service_principals
}
