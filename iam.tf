# iam.tf
# The Lambda's execution role: the identity the function runs as, granted
# ONLY the specific access it needs (least privilege).

# --- Trust policy: who is allowed to assume this role ---
# Only the Lambda service can assume it. This is the "trust" half of a role.
data "aws_iam_policy_document" "lambda_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_exec" {
  name               = "${var.project_name}-processor-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

# --- Boilerplate: let the function write logs to CloudWatch ---
# AWS's managed policy for exactly this. Every Lambda needs it.
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# --- The least-privilege permissions this specific Lambda needs ---
data "aws_iam_policy_document" "lambda_permissions" {
  # Pull messages off the main queue (required for the SQS trigger to work).
  statement {
    sid    = "ReadFromQueue"
    effect = "Allow"
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
    ]
    resources = [aws_sqs_queue.image_queue.arn]
  }

  # Read the uploaded object's metadata. Note the "/*": this is an OBJECT-level
  # ARN (bucket ARN + /*), scoping access to items INSIDE the bucket, not the
  # bucket itself — the bucket-vs-object ARN distinction in action.
  statement {
    sid       = "ReadUploadedImages"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.uploads.arn}/*"]
  }

  # Write the metadata record to the DynamoDB table (and nothing else).
  statement {
    sid       = "WriteMetadata"
    effect    = "Allow"
    actions   = ["dynamodb:PutItem"]
    resources = [aws_dynamodb_table.images.arn]
  }
}

resource "aws_iam_role_policy" "lambda_permissions" {
  name   = "${var.project_name}-processor-permissions"
  role   = aws_iam_role.lambda_exec.id
  policy = data.aws_iam_policy_document.lambda_permissions.json
}
