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
# S3 Bucket
# -------------------------
resource "aws_s3_bucket" "my_bucket" {
  bucket = "anjali-demo-bucket-2025"
  acl    = "private"
}

# -------------------------
# Enable Versioning
# -------------------------
resource "aws_s3_bucket_versioning" "my_bucket_versioning" {
  bucket = aws_s3_bucket.my_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

# -------------------------
# Enable Encryption
# -------------------------
resource "aws_s3_bucket_server_side_encryption_configuration" "my_bucket_encryption" {
  bucket = aws_s3_bucket.my_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# -------------------------
# Lifecycle Rule
# -------------------------
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
