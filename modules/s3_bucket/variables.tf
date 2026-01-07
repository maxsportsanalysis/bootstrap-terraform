variable "bucket_name" {
  description = "AWS S3 bucket name storing the terraform state"
  type        = string
}

variable "versioning_enabled" {
  description = "Enable versioning for the S3 bucket"
  type        = bool
  default     = true
}

variable "object_lock_enabled" {
  description = "Enable object lock configuration"
  type        = bool
  default     = false
}

variable "object_lock_mode" {
  description = "Object lock retention mode (e.g., GOVERNANCE or COMPLIANCE)"
  type        = string
  default     = "GOVERNANCE"
}

variable "object_lock_retention_days" {
  description = "Number of days for default object lock retention"
  type        = number
  default     = 7
}
