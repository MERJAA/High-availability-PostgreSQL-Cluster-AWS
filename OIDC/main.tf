terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.65.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}


# 1. Create the GitHub OIDC Provider in AWS
resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = ["sts.amazonaws.com"]
}

# 2. Create the TERRAFORM OIDC Role 
resource "aws_iam_role" "github_terraform_role" {
  name = "github-actions-terraform-role"

  assume_role_policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
        {
        "Effect": "Allow",
        "Principal": {
            "Federated": aws_iam_openid_connect_provider.github.arn
        },
        "Action": "sts:AssumeRoleWithWebIdentity",
        "Condition": {
            "StringEquals": {
            "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
            "token.actions.githubusercontent.com:sub": "repo:MERJAA/High-availability-PostgreSQL-Cluster-AWS:ref:refs/heads/main"
            }
        }
        }
    ]
    
  })
}


# 3. Create the ANSIBLE OIDC Role 
resource "aws_iam_role" "github_ansible_role" {
  name = "github-actions-ansible-role"

  assume_role_policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
        {
        "Effect": "Allow",
        "Principal": {
            "Federated": aws_iam_openid_connect_provider.github.arn
        },
        "Action": "sts:AssumeRoleWithWebIdentity",
        "Condition": {
            "StringEquals": {
            "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
            "token.actions.githubusercontent.com:sub": "repo:MERJAA/High-availability-PostgreSQL-Cluster-AWS:ref:refs/heads/main"
            }
        }
        }
    ]
    
  })
}


# ==========================================
# TERRAFORM ROLE POLICIES (Scoped Down)
# ==========================================

# 1. EC2 Full Access (Allows building VPCs, Subnets, NLB, Security Groups, and EC2s)
resource "aws_iam_role_policy_attachment" "tf_ec2" {
  role       = aws_iam_role.github_terraform_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2FullAccess"
}

# 2. S3 Full Access (Allows creating the Ansible payload transfer bucket)
resource "aws_iam_role_policy_attachment" "tf_s3" {
  role       = aws_iam_role.github_terraform_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

# 3. IAM Full Access (Allows creating the EC2 Instance Profile and Secrets Policy)
resource "aws_iam_role_policy_attachment" "tf_iam" {
  role       = aws_iam_role.github_terraform_role.name
  policy_arn = "arn:aws:iam::aws:policy/IAMFullAccess"
}

# 4. Secrets Manager Read/Write (Allows generating and storing the Patroni passwords)
resource "aws_iam_role_policy_attachment" "tf_secrets" {
  role       = aws_iam_role.github_terraform_role.name
  policy_arn = "arn:aws:iam::aws:policy/SecretsManagerReadWrite"
}


# ==========================================
# ANSIBLE ROLE POLICIES (Strict Least Privilege)
# ==========================================

# 1. EC2 Read Only (Allows Ansible dynamic inventory to find the 'node1', 'node2' tags)
resource "aws_iam_role_policy_attachment" "ansible_ec2_read" {
  role       = aws_iam_role.github_ansible_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess"
}

# 2. S3 Full Access (Allows Ansible to temporarily upload scripts >24KB)
resource "aws_iam_role_policy_attachment" "ansible_s3" {
  role       = aws_iam_role.github_ansible_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

# 3. SSM Full Access (Allows Ansible to tunnel into the private EC2 instances natively)
resource "aws_iam_role_policy_attachment" "ansible_ssm" {
  role       = aws_iam_role.github_ansible_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMFullAccess"
}



# ==========================================
# OUTPUTS (For GitHub Actions Variables)
# ==========================================

output "TF_ROLE_ARN" {
  description = "Copy this value into your GitHub Actions Variables as TF_ROLE_ARN"
  value       = aws_iam_role.github_terraform_role.arn
}

output "ANSIBLE_ROLE_ARN" {
  description = "Copy this value into your GitHub Actions Variables as ANSIBLE_ROLE_ARN"
  value       = aws_iam_role.github_ansible_role.arn
}
