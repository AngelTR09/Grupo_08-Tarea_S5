terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.7"
    }
  }
}

# Las credenciales NO van aquí: se leen de ~/.aws/credentials
# (creadas con `aws configure`), tal como indica la documentación del provider.
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "image-processor"
      Environment = terraform.workspace
      ManagedBy   = "terraform"
    }
  }
}

provider "archive" {}
