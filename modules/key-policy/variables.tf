variable "partition" {
  description = "AWS partition of the account that owns the key (aws, aws-cn, aws-us-gov, ...). Used to build the account root ARN."
  type        = string
  default     = "aws"
  nullable    = false

  validation {
    condition     = can(regex("^aws(-[a-z]+)*$", var.partition))
    error_message = "partition must be aws or an aws-<suffix> partition such as aws-cn or aws-us-gov."
  }
}

variable "account_id" {
  description = "Twelve-digit ID of the account that owns the key. Used to build the account root ARN."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be exactly twelve digits."
  }
}

variable "key_usage" {
  description = "Cryptographic usage of the key the policy is for: ENCRYPT_DECRYPT, SIGN_VERIFY, GENERATE_VERIFY_MAC, or KEY_AGREEMENT. Selects the use actions granted to key_user_arns and, by default, to key_service_principals."
  type        = string
  default     = "ENCRYPT_DECRYPT"
  nullable    = false

  validation {
    condition     = contains(["ENCRYPT_DECRYPT", "SIGN_VERIFY", "GENERATE_VERIFY_MAC", "KEY_AGREEMENT"], var.key_usage)
    error_message = "key_usage must be ENCRYPT_DECRYPT, SIGN_VERIFY, GENERATE_VERIFY_MAC, or KEY_AGREEMENT."
  }
}

variable "multi_region" {
  description = "Whether the key is multi-Region. Adds kms:ReplicateKey to the administrator actions so administrators can create replicas."
  type        = bool
  default     = false
  nullable    = false
}

variable "enable_root_administration" {
  description = "Render the EnableRootAccess statement that grants kms:* to the account root, which lets IAM policies in the account control the key. Disable it only when key_administrator_arns names who can administer the key, otherwise the key is locked."
  type        = bool
  default     = true
  nullable    = false
}

variable "key_administrator_arns" {
  description = "IAM principal ARNs that may administer the key (create, describe, enable, list, put, update, revoke, disable, get, delete, tag, schedule and cancel deletion, rotate on demand) but not use it."
  type        = set(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for arn in var.key_administrator_arns : can(regex("^arn:aws(-[a-z]+)*:(iam|sts)::[0-9]{12}:(root|user/.+|role/.+|assumed-role/.+|federated-user/.+)$", arn))])
    error_message = "Every key_administrator_arns entry must be an IAM or STS principal ARN (root, user, role, assumed-role, or federated-user)."
  }
}

variable "key_user_arns" {
  description = "IAM principal ARNs that may use the key with the actions of its key_usage, and manage grants for AWS resources that integrate with KMS."
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

variable "statements" {
  description = "Additional statements keyed by Sid (1-100 alphanumerics, not one of the generated Sids). principals maps a principal type (AWS, Service, Federated, CanonicalUser) to its identifiers; resources defaults to the key itself. An Allow to a wildcard principal must carry a condition."
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
    condition     = alltrue([for sid in keys(var.statements) : can(regex("^[A-Za-z0-9]{1,100}$", sid))])
    error_message = "Every statements key (policy_statements in the root and replica modules) is a Sid and must be 1-100 letters or digits."
  }

  validation {
    condition     = alltrue([for sid in keys(var.statements) : !contains(["EnableRootAccess", "AllowKeyAdministration", "AllowKeyUse", "AllowAttachmentOfPersistentResources"], sid) && !startswith(sid, "AllowServiceUse")])
    error_message = "statements (policy_statements in the root and replica modules) may not reuse a generated Sid: EnableRootAccess, AllowKeyAdministration, AllowKeyUse, AllowAttachmentOfPersistentResources, or AllowServiceUse*."
  }

  validation {
    condition     = alltrue([for statement in values(var.statements) : contains(["Allow", "Deny"], statement.effect)])
    error_message = "statements (policy_statements in the root and replica modules) effect must be Allow or Deny."
  }

  validation {
    condition     = alltrue([for statement in values(var.statements) : length(statement.principals) > 0 && alltrue([for type, identifiers in statement.principals : contains(["AWS", "Service", "Federated", "CanonicalUser"], type) && length(identifiers) > 0])])
    error_message = "statements (policy_statements in the root and replica modules) principals must map at least one of AWS, Service, Federated, or CanonicalUser to at least one identifier."
  }

  validation {
    condition     = alltrue([for statement in values(var.statements) : length(statement.actions) > 0 && length(statement.resources) > 0])
    error_message = "statements (policy_statements in the root and replica modules) actions and resources must each list at least one entry."
  }

  validation {
    condition     = alltrue([for statement in values(var.statements) : length(distinct([for condition in statement.conditions : "${condition.test}:${condition.variable}"])) == length(statement.conditions) && alltrue([for condition in statement.conditions : length(condition.values) > 0])])
    error_message = "statements (policy_statements in the root and replica modules) conditions must be unique per test and variable, and every condition must list at least one value."
  }

  validation {
    condition     = alltrue([for statement in values(var.statements) : statement.effect == "Deny" ? true : (anytrue([for identifiers in values(statement.principals) : contains(identifiers, "*")]) ? length(statement.conditions) > 0 : true)])
    error_message = "An Allow statement in statements (policy_statements in the root and replica modules) whose principals include * must carry at least one condition, otherwise anyone could use the key."
  }
}

variable "dns_suffix" {
  description = "DNS suffix of the partition (amazonaws.com, amazonaws.com.cn, ...), the value of data.aws_partition's dns_suffix. Builds the regional CloudWatch Logs service principal and the Secrets Manager kms:ViaService endpoint for service_grants. Required only when service_grants contains a cloudwatch-logs or secretsmanager entry; the root and replica modules pass it from aws_partition."
  type        = string
  default     = null

  validation {
    condition     = var.dns_suffix == null ? true : can(regex("^[a-z0-9-]+(\\.[a-z0-9-]+)+$", var.dns_suffix))
    error_message = "dns_suffix must be a DNS suffix such as amazonaws.com or amazonaws.com.cn."
  }
}

variable "service_grants" {
  description = "Pre-built statements for the AWS-documented minimum grant of a common KMS integration, keyed by Sid (1-100 alphanumerics, not a generated Sid, not a statements key). service is cloudwatch-logs (resource_arn: log group ARN), cloudfront (resource_arn: distribution ARN, S3 origin with SSE-KMS through OAC), or secretsmanager (resource_arn: secret ARN, principal_arns: the IAM principals that read or write the secret). The region, account, and partition are read from resource_arn. See docs/DESIGN.md for the exact actions and conditions of each preset and the AWS documentation they follow."
  type = map(object({
    service        = string
    resource_arn   = string
    principal_arns = optional(set(string))
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for sid in keys(var.service_grants) : can(regex("^[A-Za-z0-9]{1,100}$", sid))])
    error_message = "Every service_grants key is a Sid and must be 1-100 letters or digits."
  }

  validation {
    condition     = alltrue([for sid in keys(var.service_grants) : !contains(["EnableRootAccess", "AllowKeyAdministration", "AllowKeyUse", "AllowAttachmentOfPersistentResources"], sid) && !startswith(sid, "AllowServiceUse")])
    error_message = "service_grants may not reuse a generated Sid: EnableRootAccess, AllowKeyAdministration, AllowKeyUse, AllowAttachmentOfPersistentResources, or AllowServiceUse*."
  }

  validation {
    condition     = alltrue([for grant in values(var.service_grants) : contains(["cloudwatch-logs", "cloudfront", "secretsmanager"], grant.service)])
    error_message = "service_grants service must be cloudwatch-logs, cloudfront, or secretsmanager."
  }

  # A log group ARN as CloudWatch Logs puts it in the encryption context:
  # no trailing :* (DescribeLogGroups adds one; aws_cloudwatch_log_group.arn
  # strips it).
  # A * in the name selects ArnLike instead of ArnEquals.
  validation {
    condition     = alltrue([for grant in values(var.service_grants) : grant.service != "cloudwatch-logs" ? true : can(regex("^arn:aws(-[a-z]+)*:logs:[a-z]{2}(-[a-z]+)+-[0-9]+:[0-9]{12}:log-group:[A-Za-z0-9_/.#*-]{1,512}$", grant.resource_arn))])
    error_message = "A cloudwatch-logs service_grants resource_arn must be a log group ARN, arn:<partition>:logs:<region>:<account>:log-group:<name>, without a trailing :* (the encryption context carries the bare log group ARN). A * in the name is allowed and renders ArnLike."
  }

  # No wildcard: the distribution ID is what stops every other distribution
  # in every account from decrypting through the same service principal.
  validation {
    condition     = alltrue([for grant in values(var.service_grants) : grant.service != "cloudfront" ? true : can(regex("^arn:aws:cloudfront::[0-9]{12}:distribution/[A-Z0-9]+$", grant.resource_arn))])
    error_message = "A cloudfront service_grants resource_arn must be one distribution ARN, arn:aws:cloudfront::<account>:distribution/<ID>, without wildcards. CloudFront origin access control exists only in the aws partition."
  }

  # The secret ARN ends in a random six-character suffix that is unknown
  # until the secret exists; ? and * allow name-?????? so the key policy does
  # not depend on the secret that depends on the key.
  validation {
    condition     = alltrue([for grant in values(var.service_grants) : grant.service != "secretsmanager" ? true : can(regex("^arn:aws(-[a-z]+)*:secretsmanager:[a-z]{2}(-[a-z]+)+-[0-9]+:[0-9]{12}:secret:[A-Za-z0-9/_+=.@*?-]{1,512}$", grant.resource_arn))])
    error_message = "A secretsmanager service_grants resource_arn must be a secret ARN, arn:<partition>:secretsmanager:<region>:<account>:secret:<name>-<suffix>. ? and * are allowed (for example name-??????) and render StringLike."
  }

  validation {
    condition     = alltrue([for grant in values(var.service_grants) : grant.service == "secretsmanager" ? (grant.principal_arns == null ? false : length(grant.principal_arns) > 0 && alltrue([for arn in grant.principal_arns : can(regex("^arn:aws(-[a-z]+)*:(iam|sts)::[0-9]{12}:(root|user/.+|role/.+|assumed-role/.+|federated-user/.+)$", arn))])) : grant.principal_arns == null])
    error_message = "service_grants principal_arns is required for secretsmanager (at least one IAM or STS principal ARN: Secrets Manager calls KMS with the caller's identity, not a service principal) and must be omitted for cloudwatch-logs and cloudfront (their service principal is the grantee)."
  }
}
