data "aws_vpc" "vpc-Quant-Tokyo" {
  #   id = "vpc-ec184a8b"
  tags = {
    Name = "Quant-Tokyo"
  }
}

data "aws_subnets" "vpc-Quant-Tokyo_subnets" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.vpc-Quant-Tokyo.id]
  }

  tags = {
    Tier = "Public"
  }
}