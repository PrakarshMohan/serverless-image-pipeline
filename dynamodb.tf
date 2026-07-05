# dynamodb.tf
# Stores metadata for each processed image (filename, size, dimensions,
# thumbnail location, labels, etc.). One record per image.

resource "aws_dynamodb_table" "images" {
  name         = "${var.project_name}-images"
  billing_mode = "PAY_PER_REQUEST" # on-demand: pay per request, no capacity to manage
  hash_key     = "image_id"        # the partition key

  # Only KEY attributes are declared here. Everything else (size, labels,
  # timestamps, ...) is schemaless and added by the Lambda when it writes
  # a record. This is a core DynamoDB idea: schemaless except for keys.
  attribute {
    name = "image_id"
    type = "S" # S = String
  }

  # Production touch: continuous backups. Lets you restore the table to any
  # point in time within the retention window. Cost is negligible at this
  # table's tiny size. To turn it off, set enabled = false.
  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name = "${var.project_name}-images"
  }
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB table storing image metadata"
  value       = aws_dynamodb_table.images.name
}
