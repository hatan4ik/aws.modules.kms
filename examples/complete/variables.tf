variable "region" {
  description = "AWS region the key is created in."
  type        = string
  default     = "us-east-1"
}

variable "account_id" {
  description = "Twelve-digit ID of the account that owns the key; used for the root principal and the log-group condition."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be exactly twelve digits."
  }
}

variable "key_administrator_arns" {
  description = "IAM principal ARNs that administer the key but cannot use it."
  type        = set(string)
}

variable "key_user_arns" {
  description = "IAM principal ARNs that encrypt and decrypt with the key."
  type        = set(string)
}

variable "log_group_prefix" {
  description = "CloudWatch log group name prefix the key may encrypt, for example /aws/ecs/."
  type        = string
}

variable "consumer_account_id" {
  description = "Twelve-digit ID of the account that may decrypt objects through S3."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.consumer_account_id))
    error_message = "consumer_account_id must be exactly twelve digits."
  }
}

variable "organization_id" {
  description = "AWS Organizations ID (o-...) outside of which every use of the key is denied."
  type        = string

  validation {
    condition     = can(regex("^o-[a-z0-9]{10,32}$", var.organization_id))
    error_message = "organization_id must look like o-<10 to 32 lowercase alphanumerics>."
  }
}

variable "autoscaling_role_arn" {
  description = "ARN of the Auto Scaling service-linked role that receives the volume grant."
  type        = string
}

variable "volume_id_prefix" {
  description = "Encryption-context value (aws:ebs:id) the grant is limited to; a volume ID or a prefix such as vol-."
  type        = string
}

variable "tags" {
  description = "Tags applied to the key."
  type        = map(string)
  default = {
    Environment = "production"
    Team        = "orders"
  }
}
