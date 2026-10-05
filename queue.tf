resource "aws_sqs_queue" "dlq" {
  name                      = "image-processor-${terraform.workspace}-image-dlq"
  message_retention_seconds = 1209600 # 14 días
}

resource "aws_sqs_queue" "main" {
  name                       = "image-processor-${terraform.workspace}-image-queue"
  visibility_timeout_seconds = 360   # 6 x timeout de crop-lambda (60 s)
  message_retention_seconds  = 86400 # 1 día
  receive_wait_time_seconds  = 20    # long polling

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 3
  })
}

# Permite que el bucket (y solo ese bucket) envíe mensajes a la cola.
resource "aws_sqs_queue_policy" "allow_s3" {
  queue_url = aws_sqs_queue.main.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "s3.amazonaws.com" }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.main.arn
      Condition = {
        ArnEquals = { "aws:SourceArn" = aws_s3_bucket.images.arn }
      }
    }]
  })
}

# Paso 4 del diagrama: S3 avisa a SQS cuando se crea un objeto.
# El filtro "uploads/" es OBLIGATORIO: sin él, cada imagen que crop-lambda
# guarda en processed/ volvería a disparar el proceso en un bucle infinito.
resource "aws_s3_bucket_notification" "uploads" {
  bucket = aws_s3_bucket.images.id

  queue {
    queue_arn     = aws_sqs_queue.main.arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "uploads/"
  }

  depends_on = [aws_sqs_queue_policy.allow_s3]
}
