# monitoring.tf
# The "I watch for failures" layer. Anything that fails processing 3 times
# lands in the DLQ. This alarm watches the DLQ and emails you the instant a
# message appears there — so a broken image never fails silently.

variable "alert_email" {
  description = "Email address that receives pipeline failure alerts"
  type        = string
}

# --- SNS topic: the notification channel the alarm publishes to ---
resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-alerts"
}

# --- Email subscription ---
# After apply, AWS emails you a confirmation link. You MUST click it once,
# or no alerts will be delivered.
resource "aws_sns_topic_subscription" "alerts_email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# --- The alarm: fire if ANY message is sitting in the dead-letter queue ---
resource "aws_cloudwatch_metric_alarm" "dlq_not_empty" {
  alarm_name        = "${var.project_name}-dlq-not-empty"
  alarm_description = "A message landed in the DLQ — an image failed processing."

  namespace   = "AWS/SQS"
  metric_name = "ApproximateNumberOfMessagesVisible"
  dimensions = {
    QueueName = aws_sqs_queue.image_dlq.name
  }

  statistic           = "Maximum"
  period              = 300 # SQS publishes these metrics every 5 minutes
  evaluation_periods  = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0              # more than 0 messages = something failed
  treat_missing_data  = "notBreaching" # "no data" (empty queue) is not an alarm

  alarm_actions = [aws_sns_topic.alerts.arn] # notify when it goes into ALARM
  ok_actions    = [aws_sns_topic.alerts.arn] # and again when it recovers
}

output "alerts_topic_arn" {
  description = "SNS topic that receives pipeline alerts"
  value       = aws_sns_topic.alerts.arn
}
