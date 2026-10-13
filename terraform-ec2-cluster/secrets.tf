# ==========================================
# SECRETS MANAGEMENT (AWS SECRETS MANAGER)
# ==========================================

# 1. Generate highly secure random passwords
resource "random_password" "postgres_pass" { 
    length = 16
    special = false 
  }
resource "random_password" "rewind_pass" { 
    length = 16
    special = false 
  }
resource "random_password" "replicator_pass" { 
    length = 16
    special = false
  
  }

# 2. Create the Secret Vault
resource "aws_secretsmanager_secret" "patroni_secrets" {
  # Using the random suffix ensures no naming collisions if you destroy/recreate
  name                    = "patroni-cluster-secrets-${random_id.bucket_suffix.hex}"
  recovery_window_in_days = 0 
}

# 3. Store the passwords as a single JSON object inside the Vault
resource "aws_secretsmanager_secret_version" "patroni_secrets_version" {
  secret_id     = aws_secretsmanager_secret.patroni_secrets.id
  secret_string = jsonencode({
    POSTGRES_PASS   = random_password.postgres_pass.result
    REPLICATOR_PASS = random_password.replicator_pass.result
    REWIND_PASS     = random_password.rewind_pass.result  
  })
}

# 4. THE MAGIC PERMISSION: Allow EC2 to read ONLY this specific secret
resource "aws_iam_role_policy" "ec2_secrets_policy" {
  name = "ec2-read-patroni-secrets"
  role = aws_iam_role.ec2_ssm_role.name # Attaches to your existing EC2 SSM Role

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "secretsmanager:GetSecretValue"
        Resource = aws_secretsmanager_secret.patroni_secrets.arn
      }
    ]
  })
}
