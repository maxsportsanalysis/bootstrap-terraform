resource "aws_s3_bucket" "terraform_state" {
  bucket = "maxsportsanalysis-terraform-state-bucket"
  object_lock_enabled = true
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }

  depends_on = [aws_s3_bucket.terraform_state]
}

resource "aws_s3_bucket_object_lock_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    default_retention {
      mode = "GOVERNANCE"
      days = 7
    }
  }
  depends_on = [aws_s3_bucket_versioning.terraform_state]
}