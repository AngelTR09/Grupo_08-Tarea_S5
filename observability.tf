# Los log groups se crean ANTES que las Lambdas para fijar la retención.
# Si Lambda los creara sola, guardaría logs para siempre (y cobraría).
resource "aws_cloudwatch_log_group" "upload_lambda" {
  name              = "/aws/lambda/image-processor-${terraform.workspace}-upload"
  retention_in_days = var.log_retention_days
}

resource "aws_cloudwatch_log_group" "crop_lambda" {
  name              = "/aws/lambda/image-processor-${terraform.workspace}-crop"
  retention_in_days = var.log_retention_days
}

resource "aws_cloudwatch_log_group" "api" {
  name              = "/aws/apigateway/image-processor-${terraform.workspace}"
  retention_in_days = var.log_retention_days
}

resource "aws_sns_topic" "alarms" {
  name = "image-processor-${terraform.workspace}-alarms"
}

resource "aws_cloudwatch_metric_alarm" "dlq_messages" {
  alarm_name          = "image-processor-${terraform.workspace}-dlq-messages-alarm"
  alarm_description   = "Hay imágenes que fallaron 3 veces y llegaron a la DLQ."
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = [aws_sns_topic.alarms.arn]

  dimensions = {
    QueueName = aws_sqs_queue.dlq.name
  }
}
