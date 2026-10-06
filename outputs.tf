output "workspace" {
  description = "El entorno se a desplegado."
  value       = terraform.workspace
}

output "account_id" {
  description = "La cuenta de AWS donde se desplego el entorno."
  value       = data.aws_caller_identity.current.account_id
}

output "upload_url" {
  description = "URL para subir imágenes."
  value       = "${aws_apigatewayv2_api.main.api_endpoint}/upload"
}

output "bucket_name" {
  description = "Bucket con las carpetas uploads/ y processed/."
  value       = aws_s3_bucket.images.bucket
}

output "queue_url" {
  description = "URL de la cola de mensajes pendientes"
  value       = aws_sqs_queue.main.url
}

output "dlq_url" {
  description = "URL de la cola de mensajes fallidos"
  value       = aws_sqs_queue.dlq.url
}
