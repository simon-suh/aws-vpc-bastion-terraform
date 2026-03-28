
# tells Terraform which cloud provider to use and where to deploy
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"  # official AWS provider from HashiCorp
      version = "~> 5.0"         # use any version 5.x, but not 6.0 or higher
    }
  }
}

# configures AWS provider with the region to deploy resources in
provider "aws" {
  region = "us-east-1"  # N. Virginia region, closest to Las Vegas with most services
}

# VPC
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"  # private IP range, 65,536 possible IPs
  enable_dns_support   = true            # allows AWS DNS to work inside VPC
  enable_dns_hostnames = true            # assigns DNS names to EC2 instances

  tags = {
    Name = "vpc-bastion-vpc"             # label visible in AWS console
  }
}

# public subnet - where the bastion host will live, accessible from internet
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id        # attaches subnet to our VPC
  cidr_block              = "10.0.1.0/24"          # smaller slice of VPC range, 256 IPs
  availability_zone       = "us-east-1a"           # which AWS data center to use
  map_public_ip_on_launch = true                   # auto assigns public IP to instances launched here

  tags = {
    Name = "vpc-bastion-public-subnet"             # label visible in AWS console
  }
}

# private subnet - where the nginx EC2 will live, no direct internet access
resource "aws_subnet" "private" {
  vpc_id                  = aws_vpc.main.id        # attaches subnet to our VPC
  cidr_block              = "10.0.2.0/24"          # different slice of VPC range, 256 IPs
  availability_zone       = "us-east-1a"           # same data center as public subnet
  map_public_ip_on_launch = false                  # no public IP, keeps instances private

  tags = {
    Name = "vpc-bastion-private-subnet"            # label visible in AWS console
  }
}

# internet gateway - connects the VPC to the public internet
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id  # attaches internet gateway to our VPC

  tags = {
    Name = "vpc-bastion-igw"  # label visible in AWS console
  }
}

# route table for public subnet - directs internet traffic through the internet gateway
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id  # attaches route table to our VPC

  route {
    cidr_block = "0.0.0.0/0"                    # all internet traffic (any IP address)
    gateway_id = aws_internet_gateway.igw.id     # send it through the internet gateway
  }

  tags = {
    Name = "vpc-bastion-public-rt"  # label visible in AWS console
  }
}

# associates the public route table with the public subnet
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id           # the public subnet
  route_table_id = aws_route_table.public.id      # the route table we just created
}

# elastic IP for NAT gateway - NAT gateway requires a static public IP
resource "aws_eip" "nat" {
  domain = "vpc"  # allocates a public IP address for use in our VPC

  tags = {
    Name = "vpc-bastion-nat-eip"  # label visible in AWS console
  }
}

# NAT gateway - allows private EC2 to reach internet for downloading packages
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id        # attach the elastic IP we just created
  subnet_id     = aws_subnet.public.id  # NAT gateway lives in public subnet

  tags = {
    Name = "vpc-bastion-nat-gw"  # label visible in AWS console
  }
}

# route table for private subnet - directs outbound traffic through NAT gateway
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id  # attaches route table to our VPC

  route {
    cidr_block     = "0.0.0.0/0"                 # all outbound traffic
    nat_gateway_id = aws_nat_gateway.main.id      # send through NAT gateway
  }

  tags = {
    Name = "vpc-bastion-private-rt"  # label visible in AWS console
  }
}

# associates private route table with private subnet
resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id        # the private subnet
  route_table_id = aws_route_table.private.id   # the private route table
}

# security group for bastion host - controls what traffic can reach the bastion
resource "aws_security_group" "bastion" {
  name        = "bastion-sg"                # name visible in AWS console
  description = "Security group for bastion host"
  vpc_id      = aws_vpc.main.id             # attaches security group to our VPC

  ingress {
    description = "SSH from my computer"
    from_port   = 22                        # SSH port
    to_port     = 22                        # SSH port
    protocol    = "tcp"                     # transmission protocol
    cidr_blocks = ["0.0.0.0/0"]            # allows SSH from any IP, we'll lock this down later
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0                         # all ports
    to_port     = 0                         # all ports
    protocol    = "-1"                      # all protocols
    cidr_blocks = ["0.0.0.0/0"]            # to any destination
  }

  tags = {
    Name = "vpc-bastion-bastion-sg"         # label visible in AWS console
  }
}

# security group for private EC2 - only allows SSH from bastion, nothing else
resource "aws_security_group" "private" {
  name        = "private-sg"               # name visible in AWS console
  description = "Security group for private EC2"
  vpc_id      = aws_vpc.main.id            # attaches security group to our VPC

  ingress {
    description     = "SSH from bastion only"
    from_port       = 22                   # SSH port
    to_port         = 22                   # SSH port
    protocol        = "tcp"               # transmission protocol
    security_groups = [aws_security_group.bastion.id]  # only allow traffic from bastion security group
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0                        # all ports
    to_port     = 0                        # all ports
    protocol    = "-1"                     # all protocols
    cidr_blocks = ["0.0.0.0/0"]           # to any destination
  }

  tags = {
    Name = "vpc-bastion-private-sg"        # label visible in AWS console
  }
}

# key pair - allows us to SSH into EC2 instances securely without a password
resource "aws_key_pair" "bastion_key" {
  key_name   = "bastion-key"                        # name visible in AWS console
  public_key = file("~/.ssh/bastion-key.pub")       # reads public key file from your machine

  tags = {
    Name = "vpc-bastion-key"                        # label visible in AWS console
  }
}

# bastion host - public facing EC2 instance used to SSH into private EC2
resource "aws_instance" "bastion" {
  ami                    = "ami-0cb5cf49019e79c51"          # Amazon Linux 2023 AMI
  instance_type          = "t3.micro"                       # cheap, enough for a bastion host
  subnet_id              = aws_subnet.public.id             # place in public subnet
  key_name               = aws_key_pair.bastion_key.key_name # attach our SSH key pair
  vpc_security_group_ids = [aws_security_group.bastion.id]  # attach bastion security group

  tags = {
    Name = "vpc-bastion-bastion-host"                       # label visible in AWS console
  }
}

# private EC2 - runs nginx docker container, not directly accessible from internet
resource "aws_instance" "private" {
  ami                    = "ami-0cb5cf49019e79c51"          # Amazon Linux 2023 AMI
  instance_type          = "t3.micro"                       # cheap, enough for nginx container
  subnet_id              = aws_subnet.private.id            # place in private subnet
  key_name               = aws_key_pair.bastion_key.key_name # same SSH key pair as bastion
  vpc_security_group_ids = [aws_security_group.private.id]  # attach private security group

  /*
    user_data - script that runs automatically when EC2 first boots up
    <<-EOF - a way to write multi-line scripts in Terraform
    -d in docker run - runs the container in the background
    -p 80:80 - maps port 80 on the EC2 to port 80 on the nginx container
  */
  user_data = <<-EOF
    #!/bin/bash
    dnf update -y                          # update all packages
    dnf install -y docker                  # install docker
    systemctl start docker                 # start docker service
    systemctl enable docker                # start docker on every reboot
    docker run -d -p 80:80 nginx           # run nginx container on port 80
  EOF

  tags = {
    Name = "vpc-bastion-private-ec2"                        # label visible in AWS console
  }
}