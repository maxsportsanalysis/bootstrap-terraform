resource "aws_s3_bucket" "terraform_state" {
  bucket = var.bucket_name
  object_lock_enabled = var.object_lock_enabled ? true : null
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = var.versioning_enabled ? "Enabled" : "Suspended"
  }

  depends_on = [aws_s3_bucket.terraform_state]
}

resource "aws_s3_bucket_object_lock_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    default_retention {
      mode = var.object_lock_mode
      days = var.object_lock_retention_days
    }
  }
  depends_on = [aws_s3_bucket_versioning.terraform_state]
}