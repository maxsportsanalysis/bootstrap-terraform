resource "aws_s3_bucket" "terraform_state" {
  bucket = "maxsportsanalysis-terraform-state-bucket"
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_object_lock_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  object_lock_enabled = "Enabled"

  rule {
    default_retention {
      mode = "GOVERNANCE"
      days = 7
    }
  }
}