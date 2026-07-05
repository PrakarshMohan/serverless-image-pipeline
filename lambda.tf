# lambda.tf
# Packages the Python code into a zip and deploys it as a Lambda that the
# queue triggers.

# --- Package the code at apply time (no manual zipping needed) ---
data "archive_file" "processor" {
  type        = "zip"
  source_dir  = "${path.module}/lambda_src"
  output_path = "${path.module}/build/processor.zip"
}

# --- The function itself ---
resource "aws_lambda_function" "processor" {
  function_name = "${var.project_name}-processor"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "lambda_function.lambda_handler" # <file>.<function>
  runtime       = "python3.12"
  timeout       = 30  # seconds. The queue's 300s visibility timeout is >6x this.
  memory_size   = 256 # MB. Modest; bump up later if we add real image processing.

  filename         = data.archive_file.processor.output_path
  source_code_hash = data.archive_file.processor.output_base64sha256 # redeploy when code changes

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.images.name
    }
  }
}

# --- Connect the queue to the function ---
# Lambda polls the queue and invokes the function on new messages, in batches.
resource "aws_lambda_event_source_mapping" "queue_to_lambda" {
  event_source_arn = aws_sqs_queue.image_queue.arn
  function_name    = aws_lambda_function.processor.arn
  batch_size       = 10
}

output "processor_function_name" {
  description = "Name of the image-processing Lambda"
  value       = aws_lambda_function.processor.function_name
}
