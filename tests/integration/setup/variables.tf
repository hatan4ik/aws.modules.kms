variable "name_prefix" {
  description = "Prefix for the unique fixture name; a random suffix is appended so concurrent runs never collide. The name becomes the alias namespace of the key under test."
  type        = string
  default     = "ksm-it"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,38}[a-z0-9])?$", var.name_prefix))
    error_message = "name_prefix must be 1-40 lowercase alphanumeric characters or hyphens."
  }
}

variable "tags" {
  description = "Tags applied to the key under test in addition to the identifying defaults."
  type        = map(string)
  default     = {}
}
