variable "region" {
  description = "AWS region every key is created in."
  type        = string
  default     = "us-east-1"
}

variable "account_id" {
  description = "Twelve-digit ID of the account that owns the keys; passed so no lookup runs per key."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be exactly twelve digits."
  }
}

variable "alias_prefix" {
  description = "Alias namespace every key is filed under (<prefix>/<key>)."
  type        = string
  default     = "platform"
}

variable "key_administrator_arns" {
  description = "IAM principal ARNs that administer every key."
  type        = set(string)
}

variable "keys" {
  description = "Keys to create, keyed by a short purpose that becomes the alias suffix. Each declares its description, its users, and the service principals that may use it."
  type = map(object({
    description   = string
    key_user_arns = optional(set(string), [])
    key_service_principals = optional(map(object({
      actions = optional(set(string))
      conditions = optional(list(object({
        test     = string
        variable = string
        values   = set(string)
      })), [])
    })), {})
  }))
}

variable "tags" {
  description = "Tags applied to every key."
  type        = map(string)
  default     = {}
}
