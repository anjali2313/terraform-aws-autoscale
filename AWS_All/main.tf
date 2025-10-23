terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.17.0"
    }
  }
}

provider "aws" {
  region = "ap-northeast-1"
}

# -------------------------
# 1️⃣ VPC
# -------------------------
resource "aws_vpc" "myvpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "MyVPC"
  }
}

# -------------------------
# 2️⃣ Subnets (Public & Private)
# -------------------------
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.myvpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "ap-northeast-1a"
  tags = {
    Name = "PublicSubnet"
  }
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.myvpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "ap-northeast-1a"
  tags = {
    Name = "PrivateSubnet"
  }
}

# -------------------------
# 3️⃣ Internet Gateway & NAT Gateway
# -------------------------
# Internet Gateway for public subnet
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.myvpc.id
}

# Elastic IP for NAT Gateway
resource "aws_eip" "nat_eip" {
  vpc = true
}

# NAT Gateway in public subnet for private subnet outbound internet access
resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public.id
}

# -------------------------
# 4️⃣ Route Tables
# -------------------------
# Public route table
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.myvpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

# Associate public subnet with public route table
resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public_rt.id
}

# Private route table using NAT Gateway
resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.myvpc.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
}

resource "aws_route_table_association" "private_assoc" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private_rt.id
}

# -------------------------
# 5️⃣ S3 Bucket
# -------------------------
resource "aws_s3_bucket" "my_bucket" {
  bucket = "anjali-demo-bucket-2025"
  acl    = "private" # Deprecated, can use aws_s3_bucket_acl
}

resource "aws_s3_bucket_versioning" "my_bucket_versioning" {
  bucket = aws_s3_bucket.my_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "my_bucket_encryption" {
  bucket = aws_s3_bucket.my_bucket.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "my_bucket_lifecycle" {
  bucket = aws_s3_bucket.my_bucket.id
  rule {
    id     = "expire-old-objects"
    status = "Enabled"
    expiration {
      days = 30
    }
  }
}

# -------------------------
# 6️⃣ IAM Role for EC2
# -------------------------
resource "aws_iam_role" "ec2_s3_role" {
  name = "EC2S3AccessRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { Service = "ec2.amazonaws.com" },
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "ec2_s3_policy" {
  name        = "EC2S3AccessPolicy"
  description = "Allow EC2 to access S3 bucket"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect   = "Allow",
      Action   = ["s3:ListBucket", "s3:GetObject", "s3:PutObject"],
      Resource = [
        aws_s3_bucket.my_bucket.arn,
        "${aws_s3_bucket.my_bucket.arn}/*"
      ]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "attach_s3_policy" {
  role       = aws_iam_role.ec2_s3_role.name
  policy_arn = aws_iam_policy.ec2_s3_policy.arn
}

resource "aws_iam_instance_profile" "ec2_s3_profile" {
  name = "EC2S3InstanceProfile"
  role = aws_iam_role.ec2_s3_role.name
}

# -------------------------
# 7️⃣ EC2 Instance
# -------------------------
resource "aws_instance" "demo" {
  ami                  = "ami-070e0d4707168fc07"
  instance_type        = "t3.micro"
  key_name             = "MyKeyPair"
  subnet_id            = aws_subnet.public.id
  iam_instance_profile = aws_iam_instance_profile.ec2_s3_profile.name

  tags = {
    Name = "DemoInstance"
  }

  # Upload hostname to S3 on startup
  user_data = <<-EOF
              #!/bin/bash
              aws s3 cp /etc/hostname s3://${aws_s3_bucket.my_bucket.bucket}/ec2-hostname.txt
              EOF
}

# -------------------------
# 8️⃣ EBS Volume
# -------------------------
resource "aws_ebs_volume" "my_volume" {
  availability_zone = "ap-northeast-1a"
  size              = 10
  type              = "gp3"
  tags = {
    Name = "MyEBSVolume"
  }
}

resource "aws_volume_attachment" "ebs_att" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.my_volume.id
  instance_id = aws_instance.demo.id
}

# -------------------------
# 9️⃣ EFS File System
# -------------------------
resource "aws_security_group" "efs_sg" {
  name   = "EFSSG"
  vpc_id = aws_vpc.myvpc.id

  ingress {
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"] # allow VPC access
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_efs_file_system" "shared_fs" {
  creation_token = "my-efs"
  encrypted      = true
  tags = {
    Name = "SharedEFS"
  }
}

resource "aws_efs_mount_target" "mount" {
  for_each       = toset([aws_subnet.public.id, aws_subnet.private.id])
  file_system_id = aws_efs_file_system.shared_fs.id
  subnet_id      = each.value
  security_groups = [aws_security_group.efs_sg.id]
}
