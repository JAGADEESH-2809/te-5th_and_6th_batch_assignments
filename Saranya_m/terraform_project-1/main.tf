
# Latest Amazon Linux 2
# AMI ID

data "aws_ami" "amazon_linux" {

  most_recent = true

  owners = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}


# VPC


resource "aws_vpc" "main" {

  cidr_block = var.vpc_cidr

  tags = {
    Name        = "project1-vpc"
    Environment = var.environment
    Owner       = var.owner
  }
}


# Public Subnet


resource "aws_subnet" "public" {

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = true

  tags = {
    Name        = "public-subnet"
    Environment = var.environment
    Owner       = var.owner
  }
}


# Private Subnet


resource "aws_subnet" "private" {

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidr
  availability_zone = var.availability_zone

  tags = {
    Name        = "private-subnet"
    Environment = var.environment
    Owner       = var.owner
  }
}


# Internet Gateway


resource "aws_internet_gateway" "igw" {

  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "igw"
    Environment = var.environment
    Owner       = var.owner
  }
}


# Route Table


resource "aws_route_table" "public" {

  vpc_id = aws_vpc.main.id

  route {

    cidr_block = "0.0.0.0/0"

    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name        = "public-rt"
    Environment = var.environment
    Owner       = var.owner
  }
}
# Route Table Association

resource "aws_route_table_association" "public" {

  subnet_id = aws_subnet.public.id

  route_table_id = aws_route_table.public.id
}


# Security Groups for EC2

resource "aws_security_group" "web" {

  name = "web-sg"

  vpc_id = aws_vpc.main.id

  ingress {

    from_port = 22

    to_port = 22

    protocol = "tcp"

    cidr_blocks = [var.my_ip]
  }

  ingress {

    from_port = 80

    to_port = 80

    protocol = "tcp"

    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {

    from_port = 0

    to_port = 0

    protocol = "-1"

    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "web-sg"
    Environment = var.environment
    Owner       = var.owner
  }
}

resource "aws_security_group" "db" {

  name = "db-sg"

  vpc_id = aws_vpc.main.id

  ingress {

    from_port = 3306

    to_port = 3306

    protocol = "tcp"

    security_groups = [aws_security_group.web.id]
  }

  egress {

    from_port = 0

    to_port = 0

    protocol = "-1"

    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "db-sg"
    Environment = var.environment
    Owner       = var.owner
  }
}


# Web EC2


resource "aws_instance" "web" {

  ami = data.aws_ami.amazon_linux.id

  instance_type = var.instance_type

  subnet_id = aws_subnet.public.id

  vpc_security_group_ids = [aws_security_group.web.id]

  key_name = var.key_name

  user_data = file("userdata.sh")

  tags = {
    Name        = "web-server"
    Environment = var.environment
    Owner       = var.owner
  }
}


# Database EC2


resource "aws_instance" "db" {

  ami = data.aws_ami.amazon_linux.id

  instance_type = var.instance_type

  subnet_id = aws_subnet.private.id

  associate_public_ip_address = false

  vpc_security_group_ids = [aws_security_group.db.id]

  tags = {
    Name        = "db-server"
    Environment = var.environment
    Owner       = var.owner
  }
}


# Elastic IP (Stretch Goal)


resource "aws_eip" "web" {

  instance = aws_instance.web.id

  domain = "vpc"

  tags = {
    Name        = "web-eip"
    Environment = var.environment
    Owner       = var.owner
  }
}