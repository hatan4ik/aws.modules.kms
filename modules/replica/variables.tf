# ---------------------------------------------------------------------------
# Replica key
# ---------------------------------------------------------------------------

variable "primary_key_arn" {
  description = "ARN of the multi-Region primary key to replicate (key ID starts with mrk-). The module derives the partition and account from it and performs no lookups."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^arn:aws(-[a-z]+)*:kms:[a-z0-9-]+:[0-9]{12}:key/mrk-[0-9a-f]{32}$", var.primary_key_arn))
    error_message = "primary_key_arn must be the ARN of a multi-Region KMS key (arn:<partition>:kms:<region>:<account>:key/mrk-<32 hex>)."
  }
}

variable "description" {
  description = "Human-readable purpose of the replica key. A replica does not inherit the primary's description."
  type        = string
  nullable    = false

  validation {
    condition     = length(var.description) >= 1 && length(var.description) <= 8192
    error_message = "description must be 1-8192 characters."
  }
}

variable "deletion_window_in_days" {
  description = "Days the replica stays recoverable after destroy before KMS deletes it (7-30)."
  type        = number
  default     = 30
  nullable    = false

  validation {
    condition     = var.deletion_window_in_days >= 7 && var.deletion_window_in_days <= 30
    error_message = "deletion_window_in_days must be between 7 and 30."
  }
}

variable "enabled" {
  description = "Whether the replica is enabled for cryptographic operations."
  type        = bool
  default     = true
  nullable    = false
}

variable "bypass_policy_lockout_safety_check" {
  description = "Skip the KMS check that the caller can still administer the key under the new policy. Leave false; a policy that locks the key out needs AWS Support to recover."
  type        = bool
  default     = false
  nullable    = false
}

variable "tags" {
  description = "Tags applied to the replica key. The module adds a Name tag (first alias, or the description) unless you set one; caller tags are never overridden."
  type        = map(string)
  default     = {}
  nullable    = false
}

# ---------------------------------------------------------------------------
# Aliases
# ---------------------------------------------------------------------------

variable "aliases" {
  description = "Alias names for the replica without the alias/ prefix (letters, digits, /, _, -; not starting with aws/). Each becomes aws_kms_alias.this[<name>] in the replica Region."
  type        = set(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for alias in var.aliases : can(regex("^[a-zA-Z0-9/_-]{1,250}$", alias)) && !startswith(alias, "aws/") && !startswith(alias, "alias/")])
    error_message = "Every alias must be 1-250 characters of letters, digits, /, _, or -, without the alias/ prefix, and must not start with aws/ (reserved for AWS managed keys)."
  }
}

# ---------------------------------------------------------------------------
# Key policy
# ---------------------------------------------------------------------------

variable "key_usage" {
  description = "Cryptographic usage of the primary key: ENCRYPT_DECRYPT, SIGN_VERIFY, GENERATE_VERIFY_MAC, or KEY_AGREEMENT. A replica inherits it from the primary; the module uses it only to select the use actions granted in the policy."
  type        = string
  default     = "ENCRYPT_DECRYPT"
  nullable    = false

  validation {
    condition     = contains(["ENCRYPT_DECRYPT", "SIGN_VERIFY", "GENERATE_VERIFY_MAC", "KEY_AGREEMENT"], var.key_usage)
    error_message = "key_usage must be ENCRYPT_DECRYPT, SIGN_VERIFY, GENERATE_VERIFY_MAC, or KEY_AGREEMENT."
  }
}

variable "policy_json_override" {
  description = "Complete key policy JSON applied verbatim instead of the composed policy. Exclusive with key_administrator_arns, key_user_arns, key_service_principals, and policy_statements."
  type        = string
  default     = null

  validation {
    condition     = var.policy_json_override == null ? true : can(jsondecode(var.policy_json_override))
    error_message = "policy_json_override must be a valid JSON document."
  }
}

variable "enable_root_administration" {
  description = "Render the EnableRootAccess statement that grants kms:* to the account root of the primary key's account. Disable it only when key_administrator_arns names who can administer the replica."
  type        = bool
  default     = true
  nullable    = false
}

variable "key_administrator_arns" {
  description = "IAM principal ARNs that may administer the replica but not use it. See modules/key-policy for the action list."
  type        = set(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for arn in var.key_administrator_arns : can(regex("^arn:aws(-[a-z]+)*:(iam|sts)::[0-9]{12}:(root|user/.+|role/.+|assumed-role/.+|federated-user/.+)$", arn))])
    error_message = "Every key_administrator_arns entry must be an IAM or STS principal ARN (root, user, role, assumed-role, or federated-user)."
  }
}

variable "key_user_arns" {
  description = "IAM principal ARNs that may use the replica with the actions of key_usage and manage grants for AWS resources."
  type        = set(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for arn in var.key_user_arns : can(regex("^arn:aws(-[a-z]+)*:(iam|sts)::[0-9]{12}:(root|user/.+|role/.+|assumed-role/.+|federated-user/.+)$", arn))])
    error_message = "Every key_user_arns entry must be an IAM or STS principal ARN (root, user, role, assumed-role, or federated-user)."
  }
}

variable "key_service_principals" {
  description = "AWS service principals that may use the replica, keyed by principal, with optional actions and conditions. Same shape as the root module."
  type = map(object({
    actions = optional(set(string))
    conditions = optional(list(object({
      test     = string
      variable = string
      values   = set(string)
    })), [])
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for principal in keys(var.key_service_principals) : can(regex("^[a-z0-9][a-z0-9.-]*\\.amazonaws\\.com(\\.cn)?$", principal))])
    error_message = "Every key_service_principals key must be an AWS service principal such as logs.amazonaws.com or logs.<region>.amazonaws.com."
  }
}

variable "policy_statements" {
  description = "Additional key policy statements keyed by Sid. Same shape as the root module; see modules/key-policy."
  type = map(object({
    effect     = optional(string, "Allow")
    principals = map(set(string))
    actions    = set(string)
    resources  = optional(set(string), ["*"])
    conditions = optional(list(object({
      test     = string
      variable = string
      values   = set(string)
    })), [])
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for sid in keys(var.policy_statements) : can(regex("^[A-Za-z0-9]{1,100}$", sid)) && !contains(["EnableRootAccess", "AllowKeyAdministration", "AllowKeyUse", "AllowAttachmentOfPersistentResources"], sid) && !startswith(sid, "AllowServiceUse")])
    error_message = "Every policy_statements key is a Sid: 1-100 letters or digits, not one of the generated Sids."
  }
}
