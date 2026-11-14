# ---------------------------------------------------------------
# VPC (R1)
# ---------------------------------------------------------------
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "vpc-${var.projeto}" }
}

# Security group padrão da VPC sem nenhuma regra: nenhum recurso deve usá-lo
resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "sg-default-${var.projeto}-sem-regras" }
}

# ---------------------------------------------------------------
# Sub-redes (R2)
# ---------------------------------------------------------------
resource "aws_subnet" "pub_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.pub_a_cidr
  availability_zone = var.az_a

  # Nada recebe IP público automaticamente; o único IP público é o Elastic IP do NAT
  map_public_ip_on_launch = false

  tags = { Name = "pub-a" }
}

resource "aws_subnet" "priv_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.priv_a_cidr
  availability_zone = var.az_a

  tags = { Name = "priv-a" }
}

resource "aws_subnet" "priv_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.priv_b_cidr
  availability_zone = var.az_b

  tags = { Name = "priv-b" }
}

# ---------------------------------------------------------------
# Internet Gateway e NAT Gateway (R3, R4, ADR-002)
# ---------------------------------------------------------------
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "igw-${var.projeto}" }
}

resource "aws_eip" "nat" {
  count  = var.enable_nat ? 1 : 0
  domain = "vpc"

  tags = { Name = "eip-nat-${var.projeto}" }

  depends_on = [aws_internet_gateway.main]
}

resource "aws_nat_gateway" "main" {
  count         = var.enable_nat ? 1 : 0
  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.pub_a.id

  tags = { Name = "nat-${var.projeto}" }

  depends_on = [aws_internet_gateway.main]
}

# ---------------------------------------------------------------
# Tabelas de rota (seção 5.4)
# ---------------------------------------------------------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "rt-public" }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "rt-private" }
}

# A rota de saída existe só junto com o NAT, evitando uma rota em estado "blackhole"
resource "aws_route" "private_nat" {
  count                  = var.enable_nat ? 1 : 0
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main[0].id
}

resource "aws_route_table_association" "pub_a" {
  subnet_id      = aws_subnet.pub_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "priv_a" {
  subnet_id      = aws_subnet.priv_a.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "priv_b" {
  subnet_id      = aws_subnet.priv_b.id
  route_table_id = aws_route_table.private.id
}
