# sqs.tf
# The reliability layer. Instead of S3 triggering the Lambda directly, an
# upload drops a message onto a queue. The Lambda (Phase 4) reads from the
# queue. Anything that fails repeatedly lands in a dead-letter queue (DLQ)
# instead of vanishing, so you can inspect and retry it.

# --- Dead-Letter Queue (DLQ) ---
# The safety net. Failed messages end up here after too many failed attempts.
resource "aws_sqs_queue" "image_dlq" {
  name                      = "${var.project_name}-image-dlq"
  message_retention_seconds = 1209600 # 14 days (max) — keep failures around to investigate

  tags = {
    Name = "${var.project_name}-image-dlq"
  }
}

# --- Main processing queue ---
# S3 sends "an image was uploaded" messages here; the Lambda consumes them.
resource "aws_sqs_queue" "image_queue" {
  name                       = "${var.project_name}-image-queue"
  visibility_timeout_seconds = 300    # how long a message is hidden while being processed
  message_retention_seconds  = 345600 # 4 days

  # Redrive policy: after 3 failed processing attempts, move the message to the DLQ.
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.image_dlq.arn
    maxReceiveCount     = 3
  })

  tags = {
    Name = "${var.project_name}-image-queue"
  }
}

# --- Queue policy: allow S3 to send messages to the main queue ---
# SQS uses a resource-based policy. We allow the S3 *service* to SendMessage,
# but ONLY for events originating from our specific bucket (the SourceArn
# condition). That scoping is least privilege in action.
resource "aws_sqs_queue_policy" "image_queue_policy" {
  queue_url = aws_sqs_queue.image_queue.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "s3.amazonaws.com" }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.image_queue.arn
      Condition = {
        ArnEquals = {
          "aws:SourceArn" = aws_s3_bucket.uploads.arn
        }
      }
    }]
  })
}

# --- S3 notification: tell the bucket to message the queue on new uploads ---
# The prefix filter (uploads/) matters: later the Lambda writes thumbnails
# back to the bucket, and we don't want those writes to re-trigger processing.
resource "aws_s3_bucket_notification" "uploads_to_queue" {
  bucket = aws_s3_bucket.uploads.id

  queue {
    queue_arn     = aws_sqs_queue.image_queue.arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "uploads/"
  }

  # The queue policy must exist first, or S3 is not yet allowed to send here.
  depends_on = [aws_sqs_queue_policy.image_queue_policy]
}

output "image_queue_url" {
  description = "URL of the main image-processing queue"
  value       = aws_sqs_queue.image_queue.url
}

output "image_dlq_url" {
  description = "URL of the dead-letter queue"
  value       = aws_sqs_queue.image_dlq.url
}
