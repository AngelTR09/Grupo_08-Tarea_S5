

# output_file_mode establece permisos de lectura para todos en los archivos

data "archive_file" "upload_lambda" {
  type             = "zip"
  source_dir       = "${path.module}/lambda_src/upload"
  output_path      = "${path.module}/build/upload-${terraform.workspace}.zip"
  output_file_mode = "0666"
}

data "archive_file" "crop_lambda" {
  type             = "zip"
  source_dir       = "${path.module}/lambda_src/crop"
  output_path      = "${path.module}/build/crop-${terraform.workspace}.zip"
  output_file_mode = "0666"
}


# upload-lambda 
resource "aws_lambda_function" "upload" {
  function_name    = "image-processor-${terraform.workspace}-upload"
  role             = aws_iam_role.upload_lambda.arn
  handler          = "index.handler"
  runtime          = "nodejs20.x"
  memory_size      = 256
  timeout          = 30
  filename         = data.archive_file.upload_lambda.output_path
  source_code_hash = data.archive_file.upload_lambda.output_base64sha256

  vpc_config {
    subnet_ids         = [aws_subnet.private_a.id, aws_subnet.private_b.id]
    security_group_ids = [aws_security_group.upload_lambda.id]
  }

  environment {
    variables = {
      S3_BUCKET     = aws_s3_bucket.images.bucket
      UPLOAD_PREFIX = "uploads/"
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.upload_lambda,
    aws_iam_role_policy_attachment.upload_basic,
    aws_iam_role_policy_attachment.upload_vpc,
  ]
}


# crop-lambda 
resource "aws_lambda_function" "crop" {
  function_name    = "image-processor-${terraform.workspace}-crop"
  role             = aws_iam_role.crop_lambda.arn
  handler          = "index.handler"
  runtime          = "nodejs20.x"
  memory_size      = 512
  timeout          = 60
  filename         = data.archive_file.crop_lambda.output_path
  source_code_hash = data.archive_file.crop_lambda.output_base64sha256

  vpc_config {
    subnet_ids         = [aws_subnet.private_a.id, aws_subnet.private_b.id]
    security_group_ids = [aws_security_group.crop_lambda.id]
  }

  environment {
    variables = {
      S3_BUCKET        = aws_s3_bucket.images.bucket
      PROCESSED_PREFIX = "processed/"
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.crop_lambda,
    aws_iam_role_policy_attachment.crop_basic,
    aws_iam_role_policy_attachment.crop_vpc,
  ]
}

# SQS dispara crop-lambda en lotes de 5 mensajes
resource "aws_lambda_event_source_mapping" "crop_from_sqs" {
  event_source_arn        = aws_sqs_queue.main.arn
  function_name           = aws_lambda_function.crop.arn
  batch_size              = 5
  function_response_types = ["ReportBatchItemFailures"]

  depends_on = [aws_iam_role_policy.crop_s3_sqs]
}
