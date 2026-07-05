# s3.tf
# The bucket where users will upload raw images.

# Looks up your AWS account ID so we can build a globally-unique bucket name.
# (S3 bucket names must be unique across ALL of AWS, worldwide.)
data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "uploads" {
  bucket = "${var.project_name}-uploads-${data.aws_caller_identity.current.account_id}"
}

# Security: block ALL forms of public access to this bucket.
# This is the setting that prevents the classic "leaked S3 bucket" headline.
resource "aws_s3_bucket_public_access_block" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Security: encrypt everything stored in the bucket at rest.
resource "aws_s3_bucket_server_side_encryption_configuration" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
