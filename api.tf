# api.tf
# A public HTTP API for reading results back out of the pipeline:
#   GET /images/{id}  ->  API Gateway  ->  query Lambda  ->  DynamoDB  ->  JSON

# --- Package the query function ---
data "archive_file" "query" {
  type        = "zip"
  source_dir  = "${path.module}/query_src"
  output_path = "${path.module}/build/query.zip"
}

# --- Read-only execution role for the query Lambda ---
# Reuses the same "only Lambda may assume this" trust policy from iam.tf.
resource "aws_iam_role" "query_exec" {
  name               = "${var.project_name}-query-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "query_logs" {
  role       = aws_iam_role.query_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# This function only READS from DynamoDB — note GetItem, not PutItem.
data "aws_iam_policy_document" "query_permissions" {
  statement {
    sid       = "ReadMetadata"
    effect    = "Allow"
    actions   = ["dynamodb:GetItem"]
    resources = [aws_dynamodb_table.images.arn]
  }
}

resource "aws_iam_role_policy" "query_permissions" {
  name   = "${var.project_name}-query-permissions"
  role   = aws_iam_role.query_exec.id
  policy = data.aws_iam_policy_document.query_permissions.json
}

# --- The query function ---
resource "aws_lambda_function" "query" {
  function_name = "${var.project_name}-query"
  role          = aws_iam_role.query_exec.arn
  handler       = "query_function.lambda_handler"
  runtime       = "python3.12"
  timeout       = 10
  memory_size   = 128

  filename         = data.archive_file.query.output_path
  source_code_hash = data.archive_file.query.output_base64sha256

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.images.name
    }
  }
}

# --- The HTTP API in front of the function ---
resource "aws_apigatewayv2_api" "http_api" {
  name          = "${var.project_name}-api"
  protocol_type = "HTTP"
}

# Connects the API to the Lambda (proxy: pass the whole request through).
resource "aws_apigatewayv2_integration" "query_integration" {
  api_id                 = aws_apigatewayv2_api.http_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.query.invoke_arn
  payload_format_version = "2.0"
}

# The route. {id+} is a GREEDY variable so it captures keys containing slashes.
resource "aws_apigatewayv2_route" "get_image" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "GET /images/{id+}"
  target    = "integrations/${aws_apigatewayv2_integration.query_integration.id}"
}

# The stage. $default + auto_deploy means changes go live automatically and the
# stage name doesn't appear in the URL path.
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http_api.id
  name        = "$default"
  auto_deploy = true
}

# Allow API Gateway to invoke the query Lambda.
resource "aws_lambda_permission" "api_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.query.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}

output "api_base_url" {
  description = "Base URL of the query API. Append /images/<image_id> to fetch a record."
  value       = aws_apigatewayv2_api.http_api.api_endpoint
}
