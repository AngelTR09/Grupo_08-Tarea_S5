# Aqui se utiliza el  ID de la cuenta como sufijo ya que  el nombre de un bucket debe ser  único en todo AWS.

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "images" {
  bucket = "image-processor-${terraform.workspace}-images-${data.aws_caller_identity.current.account_id}"

  # en este punto se permite que `terraform destroy` borre el bucket aunque tenga imágenes y todas sus versiones.

  force_destroy = true

  tags = {
    Name = "image-processor-${terraform.workspace}-images"
  }
}

resource "aws_s3_bucket_versioning" "images" {
  bucket = aws_s3_bucket.images.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "images" {
  bucket = aws_s3_bucket.images.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "images" {
  bucket = aws_s3_bucket.images.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "images" {
  bucket = aws_s3_bucket.images.id

  rule {
    id     = "expirar-uploads"
    status = "Enabled"

    filter {
      prefix = "uploads/"
    }

    expiration {
      days = 30
    }

    # en este punto con el versionado activo, "expirar" solo deja una marca de borrado; ademas de que la version vieja 
    #seguiria ocupando espacio y generando costos
    noncurrent_version_expiration {
      noncurrent_days = 1
    }
  }

  rule {
    id     = "expirar-processed"
    status = "Enabled"

    filter {
      prefix = "processed/"
    }

    expiration {
      days = 90
    }

    noncurrent_version_expiration {
      noncurrent_days = 1
    }
  }
}
