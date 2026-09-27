provider "aws" {
  region = var.region
}

module "key" {
  source = "../../"

  description = "Application data key for the orders service"
  aliases     = ["orders/data"]
}
