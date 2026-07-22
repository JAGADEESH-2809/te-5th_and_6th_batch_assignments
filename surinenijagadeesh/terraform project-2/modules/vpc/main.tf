# Create VPC
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr          # VPC CIDR Block
  enable_dns_support   = true                  # Enable DNS Resolution
  enable_dns_hostnames = true                  # Enable DNS Hostnames

  tags = {
    Name        = "${var.environment}-vpc"     # VPC Name
    Environment = var.environment              # Environment Name
    Project     = var.project_name             # Project Name
    Owner       = "Jagadeesh"                  # Resource Owner
  }
}

# Create Internet Gateway
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id                     # VPC ID

  tags = {
    Name        = "${var.environment}-igw"     # Internet Gateway Name
    Environment = var.environment              # Environment Name
    Project     = var.project_name             # Project Name
    Owner       = "Jagadeesh"                  # Resource Owner
  }
}

# Create Public Subnets
resource "aws_subnet" "public" {
  for_each = var.public_subnets                # Public Subnet Configuration

  vpc_id                  = aws_vpc.this.id    # VPC ID
  cidr_block              = each.value.cidr    # Public Subnet CIDR
  availability_zone       = each.value.az      # Availability Zone
  map_public_ip_on_launch = true               # Auto Assign Public IP

  tags = {
    Name        = "${var.environment}-public-subnet-${each.key}" # Public Subnet Name
    Environment = var.environment                                # Environment Name
    Project     = var.project_name                               # Project Name
    Tier        = "Public"                                       # Subnet Tier
    Owner       = "Jagadeesh"                                    # Resource Owner
  }
}

# Create Private Subnets
resource "aws_subnet" "private" {
  for_each = var.private_subnets               # Private Subnet Configuration

  vpc_id            = aws_vpc.this.id          # VPC ID
  cidr_block        = each.value.cidr          # Private Subnet CIDR
  availability_zone = each.value.az            # Availability Zone

  tags = {
    Name        = "${var.environment}-private-subnet-${each.key}" # Private Subnet Name
    Environment = var.environment                                 # Environment Name
    Project     = var.project_name                                # Project Name
    Tier        = "Private"                                       # Subnet Tier
    Owner       = "Jagadeesh"                                     # Resource Owner
  }
}

# Create Public Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id                     # VPC ID

  route {
    cidr_block = "0.0.0.0/0"                   # Default Route
    gateway_id = aws_internet_gateway.this.id  # Internet Gateway ID
  }

  tags = {
    Name        = "${var.environment}-public-route-table" # Route Table Name
    Environment = var.environment                         # Environment Name
    Project     = var.project_name                        # Project Name
    Owner       = "Jagadeesh"                             # Resource Owner
  }
}

# Associate Public Route Table
resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public                 # Public Subnets

  subnet_id      = each.value.id               # Subnet ID
  route_table_id = aws_route_table.public.id   # Route Table ID
}