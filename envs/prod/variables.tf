variable "terraform_bucket_name" {
  description = "AWS S3 bucket name storing the terraform state"
  type        = string
  default     = true
}

variable "terraform_bucket_versioning_enabled" {
  description = "Enable versioning for the terraform state S3 bucket"
  type        = bool
  default     = true
}

variable "terraform_bucket_object_lock_enabled" {
  description = "Enable object lock configuration"
  type        = bool
  default     = false
}

variable "terraform_bucket_object_lock_mode" {
  description = "Object lock retention mode (e.g., GOVERNANCE or COMPLIANCE)"
  type        = string
  default     = "GOVERNANCE"
}

variable "terraform_bucket_object_lock_retention_days" {
  description = "Number of days for default object lock retention"
  type        = number
  default     = 7
}