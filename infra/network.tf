locals {
  name = "${var.project}-${var.environment}"
}

# R1: rede virtual
# ACEITO (AVD-AWS-0178 / CKV2_AWS_11): flow logs geram custo por volume; previstos na proposta de HA.
#trivy:ignore:AVD-AWS-0178
resource "aws_vpc" "main" {
  #checkov:skip=CKV2_AWS_11:Flow logs geram custo de ingestao e armazenamento; previstos na proposta de HA (docs/alta-disponibilidade.md).
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${local.name}-vpc" }
}

# Sem regras no SG padrão: nenhum recurso deve usá-lo por engano.
resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${local.name}-default-bloqueado" }
}

# R2: sub-redes
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = false

  tags = { Name = "${local.name}-publica-a", camada = "publica" }
}

resource "aws_subnet" "private" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.private_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = false

  tags = { Name = "${local.name}-privada-a", camada = "privada" }
}

# R3: saída da sub-rede pública
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${local.name}-igw" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${local.name}-rt-publica" }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# R4: NAT gerenciado com IP público; rota padrão da privada aponta para ele
resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = { Name = "${local.name}-eip-nat" }

  depends_on = [aws_internet_gateway.main]
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id
  tags          = { Name = "${local.name}-nat-a" }

  depends_on = [aws_internet_gateway.main]
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${local.name}-rt-privada" }
}

resource "aws_route" "private_nat" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main.id
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}
