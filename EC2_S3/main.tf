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
# 2️⃣ S3 Bucket
# -------------------------
resource "aws_s3_bucket" "my_bucket" {
  bucket = "anjali-demo-bucket-2025"
  acl    = "private"
}

# Versioning
resource "aws_s3_bucket_versioning" "my_bucket_versioning" {
  bucket = aws_s3_bucket.my_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "my_bucket_encryption" {
  bucket = aws_s3_bucket.my_bucket.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Lifecycle
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
# 3️⃣ IAM Role for EC2
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

# -------------------------
# IAM Policy to Access S3
# -------------------------
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

# Attach policy to role
resource "aws_iam_role_policy_attachment" "attach_s3_policy" {
  role       = aws_iam_role.ec2_s3_role.name
  policy_arn = aws_iam_policy.ec2_s3_policy.arn
}

# -------------------------
# Instance Profile
# -------------------------
resource "aws_iam_instance_profile" "ec2_s3_profile" {
  name = "EC2S3InstanceProfile"
  role = aws_iam_role.ec2_s3_role.name
}

# -------------------------
# 4️⃣ EC2 Instance
# -------------------------
resource "aws_instance" "demo" {
  ami                    = "ami-070e0d4707168fc07"
  instance_type          = "t3.micro"
  key_name               = "MyKeyPair"
  iam_instance_profile   = aws_iam_instance_profile.ec2_s3_profile.name

  tags = {
    Name = "DemoInstance"
  }

  # Optional: test S3 upload from EC2 during creation
  user_data = <<-EOF
              #!/bin/bash
              aws s3 cp /etc/hostname s3://${aws_s3_bucket.my_bucket.bucket}/ec2-hostname.txt
              EOF
}
