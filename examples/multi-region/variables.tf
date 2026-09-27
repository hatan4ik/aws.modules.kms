variable "region" {
  description = "AWS region of the primary key."
  type        = string
  default     = "us-east-1"
}

variable "replica_region" {
  description = "AWS region of the replica key. Must differ from region."
  type        = string
  default     = "us-west-2"
}

variable "key_administrator_arns" {
  description = "IAM principal ARNs that administer both keys; they also receive kms:ReplicateKey."
  type        = set(string)
}

variable "key_user_arns" {
  description = "IAM principal ARNs that encrypt and decrypt with either key."
  type        = set(string)
}
