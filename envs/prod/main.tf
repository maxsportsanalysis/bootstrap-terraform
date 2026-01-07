module "terraform_bucket" {
  source              = "../../modules/s3_bucket"
  bucket_name         = var.terraform_bucket_name
  versioning_enabled  = var.terraform_bucket_versioning_enabled
  object_lock_enabled = var.terraform_bucket_object_lock_enabled
  object_lock_mode    = var.terraform_bucket_object_lock_mode
  object_lock_retention_days = var.terraform_bucket_object_lock_retention_days
}
