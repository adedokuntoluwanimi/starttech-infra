locals {
  public_subnet_cidrs   = ["10.0.0.0/24", "10.0.1.0/24"]
  private_subnet_cidrs  = ["10.0.10.0/24", "10.0.11.0/24"]
  database_subnet_cidrs = ["10.0.20.0/24", "10.0.21.0/24"]
}

resource "aws_vpc" "starttech_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.tags, {
    Name = "starttech-vpc"
  })
}

resource "aws_internet_gateway" "starttech" {
  vpc_id = aws_vpc.starttech_vpc.id

  tags = merge(var.tags, {
    Name = "starttech-igw"
  })
}

resource "aws_subnet" "public" {
  count = 2

  vpc_id                  = aws_vpc.starttech_vpc.id
  availability_zone       = var.availability_zones[count.index]
  cidr_block              = local.public_subnet_cidrs[count.index]
  map_public_ip_on_launch = true

  tags = merge(var.tags, {
    Name                                        = "starttech-public-${count.index + 1}"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                    = "1"
  })
}

resource "aws_subnet" "private" {
  count = 2

  vpc_id            = aws_vpc.starttech_vpc.id
  availability_zone = var.availability_zones[count.index]
  cidr_block        = local.private_subnet_cidrs[count.index]

  tags = merge(var.tags, {
    Name                                        = "starttech-private-${count.index + 1}"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"           = "1"
  })
}

resource "aws_subnet" "database" {
  count = 2

  vpc_id            = aws_vpc.starttech_vpc.id
  availability_zone = var.availability_zones[count.index]
  cidr_block        = local.database_subnet_cidrs[count.index]

  tags = merge(var.tags, {
    Name = "starttech-database-${count.index + 1}"
  })
}

resource "aws_eip" "nat" {
  count = 2

  domain = "vpc"

  tags = merge(var.tags, {
    Name = "starttech-nat-eip-${count.index + 1}"
  })

  depends_on = [aws_internet_gateway.starttech]
}

resource "aws_nat_gateway" "starttech" {
  count = 2

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(var.tags, {
    Name = "starttech-nat-${count.index + 1}"
  })

  depends_on = [aws_internet_gateway.starttech]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.starttech_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.starttech.id
  }

  tags = merge(var.tags, {
    Name = "starttech-public-rt"
  })
}

resource "aws_route_table_association" "public" {
  count = 2

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  count = 2

  vpc_id = aws_vpc.starttech_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.starttech[count.index].id
  }

  tags = merge(var.tags, {
    Name = "starttech-private-rt-${count.index + 1}"
  })
}

resource "aws_route_table_association" "private" {
  count = 2

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

resource "aws_route_table_association" "database" {
  count = 2

  subnet_id      = aws_subnet.database[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}
