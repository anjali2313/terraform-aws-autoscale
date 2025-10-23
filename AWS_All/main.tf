terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.17.0"
    }
  }
}

# -------------------------
# AWS Providers (Tokyo + Singapore)
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
# 1️⃣ VPC
# -------------------------
resource "aws_vpc" "myvpc" {
  provider   = aws.tokyo
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "MyVPC"
  }
}

# -------------------------
# 2️⃣ Subnets
# -------------------------
resource "aws_subnet" "public" {
  provider                = aws.tokyo
  vpc_id                  = aws_vpc.myvpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "ap-northeast-1a"
  map_public_ip_on_launch = true
  tags = { Name = "PublicSubnet" }
}

resource "aws_subnet" "private" {
  provider          = aws.tokyo
  vpc_id            = aws_vpc.myvpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "ap-northeast-1a"
  tags = { Name = "PrivateSubnet" }
}

# -------------------------
# 3️⃣ Internet Gateway & NAT
# -------------------------
resource "aws_internet_gateway" "igw" {
  provider = aws.tokyo
  vpc_id   = aws_vpc.myvpc.id
}

resource "aws_eip" "nat_eip" {
  provider = aws.tokyo
  vpc      = true
}

resource "aws_nat_gateway" "nat" {
  provider     = aws.tokyo
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public.id
}

# -------------------------
# 4️⃣ Route Tables
# -------------------------
resource "aws_route_table" "public_rt" {
  provider = aws.tokyo
  vpc_id   = aws_vpc.myvpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "public_assoc" {
  provider       = aws.tokyo
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public_rt.id
}

# -------------------------
# 5️⃣ S3 Bucket
# -------------------------
resource "aws_s3_bucket" "my_bucket" {
  provider = aws.tokyo
  bucket   = "anjali-complete-demo-bucket-2025"
}

resource "aws_s3_bucket_acl" "bucket_acl" {
  provider = aws.tokyo
  bucket   = aws_s3_bucket.my_bucket.id
  acl      = "private"
}

resource "aws_s3_bucket_versioning" "bucket_versioning" {
  provider = aws.tokyo
  bucket   = aws_s3_bucket.my_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "bucket_enc" {
  provider = aws.tokyo
  bucket   = aws_s3_bucket.my_bucket.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
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
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "ec2_s3_policy" {
  name        = "EC2S3AccessPolicy"
  description = "Allow EC2 to access S3"
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

resource "aws_iam_role_policy_attachment" "attach_policy" {
  role       = aws_iam_role.ec2_s3_role.name
  policy_arn = aws_iam_policy.ec2_s3_policy.arn
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "EC2S3Profile"
  role = aws_iam_role.ec2_s3_role.name
}

# -------------------------
# 7️⃣ EC2 Instance
# -------------------------
resource "aws_instance" "demo" {
  provider             = aws.tokyo
  ami                  = "ami-070e0d4707168fc07"
  instance_type        = "t3.micro"
  key_name             = "MyKeyPair"
  subnet_id            = aws_subnet.public.id
  iam_instance_profile = aws_iam_instance_profile.ec2_profile.name
  tags = { Name = "DemoInstance" }

  user_data = <<-EOF
              #!/bin/bash
              aws s3 cp /etc/hostname s3://${aws_s3_bucket.my_bucket.bucket}/ec2-hostname.txt
              EOF
}

# -------------------------
# 8️⃣ EBS Volume + Snapshot
# -------------------------
resource "aws_ebs_volume" "my_volume" {
  provider          = aws.tokyo
  availability_zone = "ap-northeast-1a"
  size              = 10
  type              = "gp3"
  tags = { Name = "DemoEBSVolume" }
}

resource "aws_volume_attachment" "ebs_attach" {
  provider    = aws.tokyo
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.my_volume.id
  instance_id = aws_instance.demo.id
}

resource "aws_ebs_snapshot" "snapshot" {
  provider    = aws.tokyo
  volume_id   = aws_ebs_volume.my_volume.id
  description = "Daily backup of EC2 EBS volume"
  tags = { Name = "EC2-EBS-Snapshot", CreatedBy = "Terraform" }
}

# -------------------------
# 9️⃣ EFS File System
# -------------------------
resource "aws_security_group" "efs_sg" {
  provider = aws.tokyo
  name     = "EFSSG"
  vpc_id   = aws_vpc.myvpc.id

  ingress {
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_efs_file_system" "shared_fs" {
  provider  = aws.tokyo
  encrypted = true
  tags = { Name = "SharedEFS" }
}

resource "aws_efs_mount_target" "mount" {
  provider        = aws.tokyo
  for_each        = toset([aws_subnet.public.id, aws_subnet.private.id])
  file_system_id  = aws_efs_file_system.shared_fs.id
  subnet_id       = each.value
  security_groups = [aws_security_group.efs_sg.id]
}

# -------------------------
# 🔟 AMI from Instance + Cross-region Copy
# -------------------------
resource "aws_ami_from_instance" "golden" {
  provider           = aws.tokyo
  name               = "anjali-golden-image-2025"
  source_instance_id = aws_instance.demo.id
  description        = "Golden image from EC2 instance"
  depends_on         = [aws_ebs_snapshot.snapshot]
  tags = { Name = "GoldenAMI", CreatedBy = "Terraform" }
}

resource "aws_ami_copy" "ami_copy" {
  provider          = aws.singapore
  name              = "anjali-golden-image-sg-2025"
  source_ami_id     = aws_ami_from_instance.golden.id
  source_ami_region = "ap-northeast-1"
  description       = "Copy of AMI to Singapore for DR"
  tags = { Name = "AMI-Copy-Singapore", CopiedFrom = "Tokyo" }
}

# -------------------------
# 11️⃣ IAM Users and Group
# -------------------------
resource "aws_iam_group" "dev_group" {
  name = "DevTeam"
}

resource "aws_iam_policy" "dev_group_policy" {
  name        = "DevGroupPolicy"
  description = "Allow EC2 & S3 actions"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect   = "Allow",
      Action   = ["ec2:Describe*", "ec2:StartInstances", "ec2:StopInstances", "s3:*"],
      Resource = "*"
    }]
  })
}

resource "aws_iam_group_policy_attachment" "group_attach" {
  group      = aws_iam_group.dev_group.name
  policy_arn = aws_iam_policy.dev_group_policy.arn
}

resource "aws_iam_user" "anjali" {
  name = "Anjali"
}

resource "aws_iam_user" "britto" {
  name = "Britto"
}

resource "aws_iam_user_group_membership" "anjali_group" {
  user   = aws_iam_user.anjali.name
  groups = [aws_iam_group.dev_group.name]
}

resource "aws_iam_user_group_membership" "britto_group" {
  user   = aws_iam_user.britto.name
  groups = [aws_iam_group.dev_group.name]
}
