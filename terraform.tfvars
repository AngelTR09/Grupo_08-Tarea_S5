aws_region = "us-east-1"

api_throttling_rate = {
  dev  = 10000
  qa   = 10000
  prod = 10000
}

api_throttling_burst = {
  dev  = 5000
  qa   = 5000
  prod = 5000
}
