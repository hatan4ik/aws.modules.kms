# ---------------------------------------------------------------------------
# Key
# ---------------------------------------------------------------------------

variable "description" {
  description = "Human-readable purpose of the key. Also the Name tag when no alias is declared."
  type        = string
  nullable    = false

  validation {
    condition     = length(var.description) >= 1 && length(var.description) <= 8192
    error_message = "description must be 1-8192 characters."
  }
}

variable "key_usage" {
  description = "Cryptographic usage: ENCRYPT_DECRYPT, SIGN_VERIFY, GENERATE_VERIFY_MAC, or KEY_AGREEMENT. Must be compatible with key_spec (validated at plan time). Immutable."
  type        = string
  default     = "ENCRYPT_DECRYPT"
  nullable    = false

  validation {
    condition     = contains(["ENCRYPT_DECRYPT", "SIGN_VERIFY", "GENERATE_VERIFY_MAC", "KEY_AGREEMENT"], var.key_usage)
    error_message = "key_usage must be ENCRYPT_DECRYPT, SIGN_VERIFY, GENERATE_VERIFY_MAC, or KEY_AGREEMENT."
  }
}

variable "key_spec" {
  description = "Key material specification (the provider attribute customer_master_key_spec): SYMMETRIC_DEFAULT, RSA_2048/3072/4096, ECC_NIST_P256/P384/P521, ECC_SECG_P256K1, HMAC_224/256/384/512, or ML_DSA_44/65/87. Must be compatible with key_usage. Immutable."
  type        = string
  default     = "SYMMETRIC_DEFAULT"
  nullable    = false

  validation {
    condition = contains([
      "SYMMETRIC_DEFAULT", "RSA_2048", "RSA_3072", "RSA_4096", "ECC_NIST_P256", "ECC_NIST_P384", "ECC_NIST_P521", "ECC_SECG_P256K1",
      "HMAC_224", "HMAC_256", "HMAC_384", "HMAC_512", "ML_DSA_44", "ML_DSA_65", "ML_DSA_87",
    ], var.key_spec)
    error_message = "key_spec must be SYMMETRIC_DEFAULT, RSA_2048, RSA_3072, RSA_4096, ECC_NIST_P256, ECC_NIST_P384, ECC_NIST_P521, ECC_SECG_P256K1, HMAC_224, HMAC_256, HMAC_384, HMAC_512, ML_DSA_44, ML_DSA_65, or ML_DSA_87."
  }
}

variable "enable_key_rotation" {
  description = "Rotate the key material automatically. Supported only for SYMMETRIC_DEFAULT keys outside custom key stores; set false explicitly for every other key."
  type        = bool
  default     = true
  nullable    = false
}

variable "rotation_period_in_days" {
  description = "Days between automatic rotations (90-2560). Null keeps the AWS default of 365. Requires enable_key_rotation."
  type        = number
  default     = null

  validation {
    condition     = var.rotation_period_in_days == null ? true : (var.rotation_period_in_days >= 90 && var.rotation_period_in_days <= 2560)
    error_message = "rotation_period_in_days must be between 90 and 2560."
  }
}

variable "deletion_window_in_days" {
  description = "Days the key stays recoverable after destroy before KMS deletes it (7-30)."
  type        = number
  default     = 30
  nullable    = false

  validation {
    condition     = var.deletion_window_in_days >= 7 && var.deletion_window_in_days <= 30
    error_message = "deletion_window_in_days must be between 7 and 30."
  }
}

variable "multi_region" {
  description = "Create a multi-Region primary key that modules/replica can replicate into other Regions. Not supported in custom key stores. Immutable."
  type        = bool
  default     = false
  nullable    = false
}

variable "is_enabled" {
  description = "Whether the key is enabled for cryptographic operations."
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

variable "custom_key_store_id" {
  description = "ID of the CloudHSM custom key store that holds the key material. Requires SYMMETRIC_DEFAULT, single-Region, and enable_key_rotation = false. Immutable."
  type        = string
  default     = null

  validation {
    condition     = var.custom_key_store_id == null ? true : can(regex("^cks-[0-9a-f]{17}$", var.custom_key_store_id))
    error_message = "custom_key_store_id must look like cks-<17 hex>."
  }
}

variable "tags" {
  description = "Tags applied to the key. The module adds a Name tag (first alias, or the description) unless you set one; caller tags are never overridden. Aliases and grants do not support tags."
  type        = map(string)
  default     = {}
  nullable    = false
}

# ---------------------------------------------------------------------------
# Identity
# ---------------------------------------------------------------------------

variable "account_id" {
  description = "Twelve-digit ID of the account that owns the key, used for the root principal of the policy. Null reads it through aws_caller_identity; pass it to avoid the lookup."
  type        = string
  default     = null

  validation {
    condition     = var.account_id == null ? true : can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be exactly twelve digits."
  }
}

variable "partition" {
  description = "AWS partition of the account (aws, aws-cn, aws-us-gov, ...). Null reads it through aws_partition; pass it to avoid the lookup."
  type        = string
  default     = null

  validation {
    condition     = var.partition == null ? true : can(regex("^aws(-[a-z]+)*$", var.partition))
    error_message = "partition must be aws or an aws-<suffix> partition such as aws-cn or aws-us-gov."
  }
}

# ---------------------------------------------------------------------------
# Key policy
# ---------------------------------------------------------------------------

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
  description = "Render the EnableRootAccess statement that grants kms:* to the account root, which lets IAM policies in the account control the key. Disable it only when key_administrator_arns names who can administer the key; the root_administration_disabled check warns otherwise."
  type        = bool
  default     = true
  nullable    = false
}

variable "key_administrator_arns" {
  description = "IAM principal ARNs that may administer the key (create, describe, enable, list, put, update, revoke, disable, get, delete, tag, schedule and cancel deletion, rotate on demand, replicate when multi-Region) but not use it."
  type        = set(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for arn in var.key_administrator_arns : can(regex("^arn:aws(-[a-z]+)*:(iam|sts)::[0-9]{12}:(root|user/.+|role/.+|assumed-role/.+|federated-user/.+)$", arn))])
    error_message = "Every key_administrator_arns entry must be an IAM or STS principal ARN (root, user, role, assumed-role, or federated-user)."
  }
}

variable "key_user_arns" {
  description = "IAM principal ARNs that may use the key with the actions of its key_usage (for ENCRYPT_DECRYPT: kms:Encrypt, kms:Decrypt, kms:ReEncrypt*, kms:GenerateDataKey*, kms:DescribeKey) and manage grants for AWS resources that integrate with KMS."
  type        = set(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for arn in var.key_user_arns : can(regex("^arn:aws(-[a-z]+)*:(iam|sts)::[0-9]{12}:(root|user/.+|role/.+|assumed-role/.+|federated-user/.+)$", arn))])
    error_message = "Every key_user_arns entry must be an IAM or STS principal ARN (root, user, role, assumed-role, or federated-user)."
  }
}

variable "key_service_principals" {
  description = "AWS service principals that may use the key, keyed by principal (for example logs.us-east-1.amazonaws.com). actions defaults to the use actions of key_usage; conditions restrict the grant, for example an ArnLike on kms:EncryptionContext:aws:logs:arn."
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

  validation {
    condition     = alltrue([for entry in values(var.key_service_principals) : entry.actions == null ? true : length(entry.actions) > 0])
    error_message = "key_service_principals actions, when set, must list at least one action."
  }

  validation {
    condition     = alltrue([for entry in values(var.key_service_principals) : length(distinct([for condition in entry.conditions : "${condition.test}:${condition.variable}"])) == length(entry.conditions) && alltrue([for condition in entry.conditions : length(condition.values) > 0])])
    error_message = "key_service_principals conditions must be unique per test and variable, and every condition must list at least one value."
  }
}

variable "policy_statements" {
  description = "Additional key policy statements keyed by Sid (1-100 alphanumerics, not a generated Sid). principals maps AWS, Service, Federated, or CanonicalUser to identifiers; resources defaults to the key itself; an Allow to a wildcard principal must carry a condition."
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
    condition     = alltrue([for sid in keys(var.policy_statements) : can(regex("^[A-Za-z0-9]{1,100}$", sid))])
    error_message = "Every policy_statements key is a Sid and must be 1-100 letters or digits."
  }

  validation {
    condition     = alltrue([for sid in keys(var.policy_statements) : !contains(["EnableRootAccess", "AllowKeyAdministration", "AllowKeyUse", "AllowAttachmentOfPersistentResources"], sid) && !startswith(sid, "AllowServiceUse")])
    error_message = "policy_statements may not reuse a generated Sid: EnableRootAccess, AllowKeyAdministration, AllowKeyUse, AllowAttachmentOfPersistentResources, or AllowServiceUse*."
  }

  validation {
    condition     = alltrue([for statement in values(var.policy_statements) : contains(["Allow", "Deny"], statement.effect)])
    error_message = "policy_statements effect must be Allow or Deny."
  }

  validation {
    condition     = alltrue([for statement in values(var.policy_statements) : length(statement.principals) > 0 && alltrue([for type, identifiers in statement.principals : contains(["AWS", "Service", "Federated", "CanonicalUser"], type) && length(identifiers) > 0])])
    error_message = "policy_statements principals must map at least one of AWS, Service, Federated, or CanonicalUser to at least one identifier."
  }

  validation {
    condition     = alltrue([for statement in values(var.policy_statements) : length(statement.actions) > 0 && length(statement.resources) > 0])
    error_message = "policy_statements actions and resources must each list at least one entry."
  }

  validation {
    condition     = alltrue([for statement in values(var.policy_statements) : length(distinct([for condition in statement.conditions : "${condition.test}:${condition.variable}"])) == length(statement.conditions) && alltrue([for condition in statement.conditions : length(condition.values) > 0])])
    error_message = "policy_statements conditions must be unique per test and variable, and every condition must list at least one value."
  }

  validation {
    condition     = alltrue([for statement in values(var.policy_statements) : statement.effect == "Deny" ? true : (anytrue([for identifiers in values(statement.principals) : contains(identifiers, "*")]) ? length(statement.conditions) > 0 : true)])
    error_message = "An Allow statement whose principals include * must carry at least one condition, otherwise anyone could use the key."
  }
}

# ---------------------------------------------------------------------------
# Aliases
# ---------------------------------------------------------------------------

variable "aliases" {
  description = "Alias names without the alias/ prefix (letters, digits, /, _, -; not starting with aws/). Each becomes aws_kms_alias.this[<name>]; the first in sorted order is the key's Name tag."
  type        = set(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for alias in var.aliases : can(regex("^[a-zA-Z0-9/_-]{1,250}$", alias)) && !startswith(alias, "aws/") && !startswith(alias, "alias/")])
    error_message = "Every alias must be 1-250 characters of letters, digits, /, _, or -, without the alias/ prefix, and must not start with aws/ (reserved for AWS managed keys)."
  }
}

# ---------------------------------------------------------------------------
# Grants
# ---------------------------------------------------------------------------

variable "grants" {
  description = "Grants keyed by grant name. grantee_principal receives operations (KMS grant operations such as Decrypt, Encrypt, GenerateDataKey, CreateGrant); constraints limit them to an encryption context; retiring_principal may retire the grant; retire_on_delete retires instead of revoking on destroy."
  type = map(object({
    grantee_principal  = string
    operations         = set(string)
    retiring_principal = optional(string)
    constraints = optional(object({
      encryption_context_equals = optional(map(string))
      encryption_context_subset = optional(map(string))
    }))
    grant_creation_tokens = optional(set(string))
    retire_on_delete      = optional(bool, false)
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for name in keys(var.grants) : can(regex("^[a-zA-Z0-9:/_-]{1,256}$", name))])
    error_message = "Every grants key is the grant name and must be 1-256 characters of letters, digits, :, /, _, or -."
  }

  validation {
    condition = alltrue([for grant in values(var.grants) : length(grant.operations) > 0 && alltrue([for operation in grant.operations : contains([
      "CreateGrant", "Decrypt", "DeriveSharedSecret", "DescribeKey", "Encrypt", "GenerateDataKey", "GenerateDataKeyPair", "GenerateDataKeyPairWithoutPlaintext",
      "GenerateDataKeyWithoutPlaintext", "GenerateMac", "GetPublicKey", "ReEncryptFrom", "ReEncryptTo", "RetireGrant", "Sign", "Verify", "VerifyMac",
    ], operation)])])
    error_message = "grants operations must list at least one KMS grant operation: CreateGrant, Decrypt, DeriveSharedSecret, DescribeKey, Encrypt, GenerateDataKey, GenerateDataKeyPair, GenerateDataKeyPairWithoutPlaintext, GenerateDataKeyWithoutPlaintext, GenerateMac, GetPublicKey, ReEncryptFrom, ReEncryptTo, RetireGrant, Sign, Verify, or VerifyMac."
  }

  validation {
    condition     = alltrue([for grant in values(var.grants) : can(regex("^arn:aws(-[a-z]+)*:(iam|sts)::[0-9]{12}:(root|user/.+|role/.+|assumed-role/.+|federated-user/.+)$", grant.grantee_principal)) && (grant.retiring_principal == null ? true : can(regex("^arn:aws(-[a-z]+)*:(iam|sts)::[0-9]{12}:(root|user/.+|role/.+|assumed-role/.+|federated-user/.+)$", grant.retiring_principal)))])
    error_message = "grants grantee_principal and retiring_principal must be IAM or STS principal ARNs (root, user, role, assumed-role, or federated-user)."
  }

  validation {
    condition     = alltrue([for grant in values(var.grants) : grant.constraints == null ? true : ((grant.constraints.encryption_context_equals == null ? 0 : length(grant.constraints.encryption_context_equals)) + (grant.constraints.encryption_context_subset == null ? 0 : length(grant.constraints.encryption_context_subset)) > 0)])
    error_message = "grants constraints, when set, must declare at least one encryption_context_equals or encryption_context_subset pair."
  }
}
