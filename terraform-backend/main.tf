provider "aws" {
  region = "us-east-1"
}

# 1. Create the S3 Bucket (The Safe)
resource "aws_s3_bucket" "terraform_state" {
  bucket = "patroni-tf-state-my-name-12345" # <-- CHANGE THIS TO BE UNIQUE
  force_destroy = true
}

# 2. Enable Versioning (Crucial for State History & Recovery)
resource "aws_s3_bucket_versioning" "terraform_state_versioning" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

# 3. Enable Encryption (To protect your Database Passwords!)
resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state_crypto" {
  bucket = aws_s3_bucket.terraform_state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}