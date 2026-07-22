# -----------------------------
# Get Latest Amazon Linux 2 AMI
# -----------------------------
data "aws_ami" "amazon_linux" {
  most_recent = true                           # Get latest AMI

  owners = ["amazon"]                          # Official Amazon AMIs

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# -----------------------------
# Create Security Group
# -----------------------------
resource "aws_security_group" "this" {
  name        = "${var.environment}-web-security-group" # Security Group Name
  description = "Security Group for Web Server"         # Security Group Description
  vpc_id      = var.vpc_id                              # VPC ID

  # Allow SSH
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_ip]
  }

  # Allow HTTP
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.environment}-web-security-group" # Security Group Name
    Environment = var.environment                         # Environment
    Project = var.project_name                            # Project Name
    Owner       = "Jagadeesh"                             # Resource Owner
  }
}

# -----------------------------
# Launch EC2 Instance
# -----------------------------
resource "aws_instance" "this" {
  count = var.instance_count                     # Number of EC2 instances

  ami                         = data.aws_ami.amazon_linux.id # Latest Amazon Linux 2
  instance_type               = var.instance_type            # Instance Type
  subnet_id                   = var.subnet_id               # Public Subnet
  vpc_security_group_ids      = [aws_security_group.this.id] # Security Group
  associate_public_ip_address = true                        # Assign Public IP
  key_name                    = var.key_name               # Key Pair
  user_data                   = file("${path.module}/user_data.sh") # Apache Script

  tags = {
    Name        = "${var.environment}-web-server-${count.index + 1}" # EC2 Name
    Environment = var.environment
    Project = var.project_name
    Owner       = "Jagadeesh"
  }
}