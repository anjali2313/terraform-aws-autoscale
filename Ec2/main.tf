terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.17.0"
    }
  }
}

# -------------------------
# AWS Providers
# -------------------------
provider "aws" {
  alias  = "tokyo"
  region = "ap-northeast-1"
}

provider "aws" {
  alias  = "singapore"
  region = "ap-southeast-1"
}

# -------------------------
# VPC
# -------------------------
resource "aws_vpc" "myvpc" {
  provider   = aws.tokyo
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "MyVPC"
  }
}

# -------------------------
# EC2 Instance
# -------------------------
resource "aws_instance" "demo" {
  provider        = aws.tokyo
  ami             = "ami-070e0d4707168fc07"
  instance_type   = "t3.micro"
  key_name        = "MyKeyPair"
  iam_instance_profile = aws_iam_instance_profile.ec2_role_profile.name

  tags = {
    Name = "DemoInstance"
  }
}

# -------------------------
# EBS Volume
# -------------------------
resource "aws_ebs_volume" "my_volume" {
  provider           = aws.tokyo
  availability_zone  = "ap-northeast-1a"
  size               = 10
  type               = "gp3"

  tags = {
    Name = "DemoVolume"
  }
}

# -------------------------
# IAM Role for EC2
# -------------------------
resource "aws_iam_role" "ec2_role" {
  name = "EC2DemoRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Service = "ec2.amazonaws.com"
      },
      Action = "sts:AssumeRole"
    }]
  })
}

# -------------------------
# IAM Policy for Role
# -------------------------
resource "aws_iam_policy" "ec2_policy" {
  name        = "EC2Policy"
  description = "EC2 can access S3"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect   = "Allow",
      Action   = ["s3:ListBucket", "s3:GetObject", "s3:PutObject"],
      Resource = "*"
    }]
  })
}

# Attach policy to role
resource "aws_iam_role_policy_attachment" "attach_role_policy" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.ec2_policy.arn
}

# Instance Profile (attach role to EC2)
resource "aws_iam_instance_profile" "ec2_role_profile" {
  name = "EC2DemoProfile"
  role = aws_iam_role.ec2_role.name
}

# -------------------------
#  🔸 EBS Snapshot
# -------------------------
resource "aws_ebs_snapshot" "my_snapshot" {
  provider    = aws.tokyo
  volume_id   = aws_ebs_volume.my_volume.id
  description = "Daily backup of EC2 EBS volume"

  tags = {
    Name       = "EC2-EBS-Snapshot"
    CreatedBy  = "Terraform"
  }
}

# -------------------------
#  🔸 Create AMI from existing EC2
# -------------------------
resource "aws_ami_from_instance" "my_ami" {
  provider           = aws.tokyo
  name               = "anjali-golden-image-2025"
  source_instance_id = aws_instance.demo.id
  description        = "Golden image created from EC2 instance"
  depends_on         = [aws_ebs_snapshot.my_snapshot]

  tags = {
    Name       = "Golden-AMI-2025"
    CreatedBy  = "Terraform"
  }
}

# -------------------------
#  🔸 Copy AMI to Singapore Region (DR)
# -------------------------
resource "aws_ami_copy" "my_ami_copy" {
  provider          = aws.singapore
  name              = "anjali-golden-image-sg-2025"
  description       = "Copy of golden AMI to Singapore region"
  source_ami_id     = aws_ami_from_instance.my_ami.id
  source_ami_region = "ap-northeast-1"

  tags = {
    Name        = "Golden-AMI-Copy-SG"
    CopiedFrom  = "Tokyo"
  }
}

# -------------------------
# IAM Users and Groups
# -------------------------
resource "aws_iam_group" "dev_group" {
  name = "DevTeam"
}

resource "aws_iam_policy" "dev_group_policy" {
  name        = "DevGroupPolicy"
  description = "Allows EC2 & S3 actions for Dev Team"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect   = "Allow",
      Action   = [
        "ec2:Describe*",
        "ec2:StartInstances",
        "ec2:StopInstances",
        "s3:ListBucket",
        "s3:GetObject",
        "s3:PutObject"
      ],
      Resource = "*"
    }]
  })
}

resource "aws_iam_group_policy_attachment" "attach_group_policy" {
  group      = aws_iam_group.dev_group.name
  policy_arn = aws_iam_policy.dev_group_policy.arn
}

resource "aws_iam_user" "user1" {
  name = "Anjali"
}

resource "aws_iam_user" "user2" {
  name = "Britto"
}

resource "aws_iam_user_group_membership" "dev_membership1" {
  user   = aws_iam_user.user1.name
  groups = [aws_iam_group.dev_group.name]
}

resource "aws_iam_user_group_membership" "dev_membership2" {
  user   = aws_iam_user.user2.name
  groups = [aws_iam_group.dev_group.name]
}
