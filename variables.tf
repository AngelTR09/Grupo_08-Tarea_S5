variable "aws_region" {
  description = "Región de AWS donde se despliega la arquitectura (según el diagrama)."
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR de la VPC (según el diagrama)."
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidrs" {
  description = "CIDR de cada subred (según el diagrama)."
  type        = map(string)

  default = {
    public_a  = "10.0.1.0/24"
    public_b  = "10.0.2.0/24"
    private_a = "10.0.11.0/24"
    private_b = "10.0.12.0/24"
  }
}

variable "availability_zone_ids" {
  description = "IDs de zona de disponibilidad. Se usan IDs (use1-azX) y no nombres (us-east-1a) porque Lambda no admite subredes en use1-az3."
  type        = map(string)

  default = {
    a = "use1-az1"
    b = "use1-az2"
  }
}

variable "api_throttling_rate" {
  description = "Peticiones por segundo permitidas en el API por workspace (según el diagrama)."
  type        = map(number)

  default = {
    dev  = 10000
    qa   = 10000
    prod = 10000
  }
}

variable "api_throttling_burst" {
  description = "Ráfaga máxima de peticiones en el API por workspace."
  type        = map(number)

  default = {
    dev  = 5000
    qa   = 5000
    prod = 5000
  }
}

variable "log_retention_days" {
  description = "Días que se guardan los logs en CloudWatch (según el diagrama)."
  type        = number
  default     = 14
}
