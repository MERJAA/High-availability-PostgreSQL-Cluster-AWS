# --- VPC & SUBNETS ---
resource "aws_vpc" "vpc_lab" {
  cidr_block           = "10.10.0.0/16"
  enable_dns_hostnames = true 
  tags = { 
    Name = "vpc_lab" 
    }
}

resource "aws_subnet" "primary" {
  vpc_id            = aws_vpc.vpc_lab.id
  cidr_block        = "10.10.1.0/24"
  availability_zone = "us-east-1a"
  tags = { Name = "Primary_Private" }
}

resource "aws_subnet" "replica_1" {
  vpc_id            = aws_vpc.vpc_lab.id
  cidr_block        = "10.10.2.0/24"
  availability_zone = "us-east-1b"
  tags = { Name = "Replica_1_Private" }
}

resource "aws_subnet" "replica_2" {
  vpc_id            = aws_vpc.vpc_lab.id
  cidr_block        = "10.10.3.0/24"
  availability_zone = "us-east-1c"
  tags = { Name = "Replica_2_Private" }
}

resource "aws_subnet" "Public_NAT" {
  vpc_id            = aws_vpc.vpc_lab.id
  cidr_block        = "10.10.4.0/24"
  availability_zone = "us-east-1a"
  tags = { Name = "Public_NAT_Subnet" }
}

# --- GATEWAYS & EIP ---
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.vpc_lab.id
  tags = { Name = "IGW" }
}

resource "aws_eip" "NAT" {
  domain = "vpc"
}

resource "aws_nat_gateway" "DB_NAT" {
  allocation_id = aws_eip.NAT.id
  subnet_id     = aws_subnet.Public_NAT.id
  tags = { Name = "gw NAT" }
  depends_on    = [aws_internet_gateway.gw] # Brilliant use of depends_on!
}

# --- ROUTE TABLES ---

# 1. Private Route Table (Points to NAT)
resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.vpc_lab.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.DB_NAT.id # Correctly points to NAT
  }
  tags = { Name = "Private_RT_To_NAT" }
}

# 2. Public Route Table (Points to IGW) - FIX: Added this back!
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.vpc_lab.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
  tags = { Name = "Public_RT_To_IGW" }
}

# --- ROUTE TABLE ASSOCIATIONS ---
resource "aws_route_table_association" "primary_assoc" {
  subnet_id      = aws_subnet.primary.id
  route_table_id = aws_route_table.private_rt.id
}
resource "aws_route_table_association" "replica_1_assoc" {
  subnet_id      = aws_subnet.replica_1.id
  route_table_id = aws_route_table.private_rt.id
}
resource "aws_route_table_association" "replica_2_assoc" {
  subnet_id      = aws_subnet.replica_2.id
  route_table_id = aws_route_table.private_rt.id
}

# FIX: Attached the Public Subnet to the Public Route Table
resource "aws_route_table_association" "Public_assoc" {
  subnet_id      = aws_subnet.Public_NAT.id
  route_table_id = aws_route_table.public_rt.id 
}
