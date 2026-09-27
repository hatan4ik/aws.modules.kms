variable "region" {
  description = "AWS region the key is created in."
  type        = string
  default     = "us-east-1"
}

variable "signer_role_arns" {
  description = "IAM role ARNs of the release pipelines that sign artifacts."
  type        = set(string)
}

variable "verifier_account_id" {
  description = "Twelve-digit ID of the account whose principals may verify signatures and fetch the public key."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.verifier_account_id))
    error_message = "verifier_account_id must be exactly twelve digits."
  }
}
