# outputs.tf
# Values Terraform prints after `apply` so you can see what got created.

output "uploads_bucket_name" {
  description = "Name of the S3 bucket for image uploads"
  value       = aws_s3_bucket.uploads.id
}
