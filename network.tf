
# VPC

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "image-processor-${terraform.workspace}-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "image-processor-${terraform.workspace}-igw"
  }
}


# Subredes públicas (AZ-a y AZ-b)

resource "aws_subnet" "public_a" {
  vpc_id               = aws_vpc.main.id
  cidr_block           = var.subnet_cidrs["public_a"]
  availability_zone_id = var.availability_zone_ids["a"]

  tags = {
    Name = "image-processor-${terraform.workspace}-public-a"
  }
}

resource "aws_subnet" "public_b" {
  vpc_id               = aws_vpc.main.id
  cidr_block           = var.subnet_cidrs["public_b"]
  availability_zone_id = var.availability_zone_ids["b"]

  tags = {
    Name = "image-processor-${terraform.workspace}-public-b"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "image-processor-${terraform.workspace}-public-rt"
  }
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}


# NAT Gateways: no se crearán (decisión del issue #1)



# Subredes privadas

resource "aws_subnet" "private_a" {
  vpc_id               = aws_vpc.main.id
  cidr_block           = var.subnet_cidrs["private_a"]
  availability_zone_id = var.availability_zone_ids["a"]

  tags = {
    Name = "image-processor-${terraform.workspace}-private-a"
  }
}

resource "aws_subnet" "private_b" {
  vpc_id               = aws_vpc.main.id
  cidr_block           = var.subnet_cidrs["private_b"]
  availability_zone_id = var.availability_zone_ids["b"]

  tags = {
    Name = "image-processor-${terraform.workspace}-private-b"
  }
}

# Sin ruta 0.0.0.0/0: al no existir los NAT, las subredes privadas no salen a
# internet. El endpoint de S3 agrega su propia ruta a estas tablas.
resource "aws_route_table" "private_a" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "image-processor-${terraform.workspace}-private-rt-a"
  }
}

resource "aws_route_table" "private_b" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "image-processor-${terraform.workspace}-private-rt-b"
  }
}

resource "aws_route_table_association" "private_a" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private_a.id
}

resource "aws_route_table_association" "private_b" {
  subnet_id      = aws_subnet.private_b.id
  route_table_id = aws_route_table.private_b.id
}


# VPC Endpoints

# S3 Gateway Endpoint: gratuito, se coloca en las tablas de rutas privadas.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private_a.id, aws_route_table.private_b.id]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = "*"
      Action    = ["s3:GetObject", "s3:PutObject"]
      Resource  = "${aws_s3_bucket.images.arn}/*"
    }]
  })

  tags = {
    Name = "image-processor-${terraform.workspace}-vpce-s3"
  }
}

# SQS Interface Endpoint: una interfaz de red en cada subred privada.
resource "aws_vpc_endpoint" "sqs" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.sqs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private_a.id, aws_subnet.private_b.id]
  security_group_ids  = [aws_security_group.vpce_sqs.id]
  private_dns_enabled = true

  tags = {
    Name = "image-processor-${terraform.workspace}-vpce-sqs"
  }
}


# Security Groups

resource "aws_security_group" "upload_lambda" {
  name        = "image-processor-${terraform.workspace}-sg-upload-lambda"
  description = "upload-lambda: sin entrada, salida 443 solo a endpoints S3 y SQS"
  vpc_id      = aws_vpc.main.id

  egress {
    description     = "HTTPS hacia S3 por el Gateway Endpoint"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    prefix_list_ids = [aws_vpc_endpoint.s3.prefix_list_id]
  }

  egress {
    description = "HTTPS hacia el Interface Endpoint de SQS (dentro de la VPC)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = {
    Name = "image-processor-${terraform.workspace}-sg-upload-lambda"
  }
}

resource "aws_security_group" "crop_lambda" {
  name        = "image-processor-${terraform.workspace}-sg-crop-lambda"
  description = "crop-lambda: sin entrada, salida 443 solo a endpoints S3 y SQS"
  vpc_id      = aws_vpc.main.id

  egress {
    description     = "HTTPS hacia S3 por el Gateway Endpoint"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    prefix_list_ids = [aws_vpc_endpoint.s3.prefix_list_id]
  }

  egress {
    description = "HTTPS hacia el Interface Endpoint de SQS (dentro de la VPC)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = {
    Name = "image-processor-${terraform.workspace}-sg-crop-lambda"
  }
}

resource "aws_security_group" "vpce_sqs" {
  name        = "image-processor-${terraform.workspace}-sg-vpce-sqs"
  description = "Endpoint SQS: solo acepta 443 desde las dos Lambdas"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "HTTPS desde las Lambdas"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.upload_lambda.id, aws_security_group.crop_lambda.id]
  }

  tags = {
    Name = "image-processor-${terraform.workspace}-sg-vpce-sqs"
  }
}
