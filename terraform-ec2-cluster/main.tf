terraform {
  backend "s3" {
    bucket       = "patroni-tf-state-my-name-12345" 
    key          = "database/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true   # <--- THE NEW MODERN STANDARD
  }
}


provider "aws" {
  region = "us-east-1"
}

data "aws_region" "current" {}

variable "instance_type" {
  default = "t3.micro"
}



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



# --- VPC & SUBNETS ---
resource "aws_vpc" "vpc_lab" {
  cidr_block           = "10.10.0.0/16"
  enable_dns_hostnames = true 
  tags = { 
    Name = "vpc_lab" 
    }
}

resource "aws_subnet" "primary" {
  vpc_id            = aws_vpc.vpc_lab.id
  cidr_block        = "10.10.1.0/24"
  availability_zone = "us-east-1a"
  tags = { Name = "Primary_Private" }
}

resource "aws_subnet" "replica_1" {
  vpc_id            = aws_vpc.vpc_lab.id
  cidr_block        = "10.10.2.0/24"
  availability_zone = "us-east-1b"
  tags = { Name = "Replica_1_Private" }
}

resource "aws_subnet" "replica_2" {
  vpc_id            = aws_vpc.vpc_lab.id
  cidr_block        = "10.10.3.0/24"
  availability_zone = "us-east-1c"
  tags = { Name = "Replica_2_Private" }
}

resource "aws_subnet" "Public_NAT" {
  vpc_id            = aws_vpc.vpc_lab.id
  cidr_block        = "10.10.4.0/24"
  availability_zone = "us-east-1a"
  tags = { Name = "Public_NAT_Subnet" }
}

# --- GATEWAYS & EIP ---
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.vpc_lab.id
  tags = { Name = "IGW" }
}

# FIX: Removed the invalid "instance =" line
resource "aws_eip" "NAT" {
  domain = "vpc"
}

resource "aws_nat_gateway" "DB_NAT" {
  allocation_id = aws_eip.NAT.id
  subnet_id     = aws_subnet.Public_NAT.id
  tags = { Name = "gw NAT" }
  depends_on    = [aws_internet_gateway.gw] # Brilliant use of depends_on!
}

# --- ROUTE TABLES ---

# 1. Private Route Table (Points to NAT)
resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.vpc_lab.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.DB_NAT.id # Correctly points to NAT
  }
  tags = { Name = "Private_RT_To_NAT" }
}

# 2. Public Route Table (Points to IGW) - FIX: Added this back!
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.vpc_lab.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
  tags = { Name = "Public_RT_To_IGW" }
}

# --- ROUTE TABLE ASSOCIATIONS ---
resource "aws_route_table_association" "primary_assoc" {
  subnet_id      = aws_subnet.primary.id
  route_table_id = aws_route_table.private_rt.id
}
resource "aws_route_table_association" "replica_1_assoc" {
  subnet_id      = aws_subnet.replica_1.id
  route_table_id = aws_route_table.private_rt.id
}
resource "aws_route_table_association" "replica_2_assoc" {
  subnet_id      = aws_subnet.replica_2.id
  route_table_id = aws_route_table.private_rt.id
}

# FIX: Attached the Public Subnet to the Public Route Table
resource "aws_route_table_association" "Public_assoc" {
  subnet_id      = aws_subnet.Public_NAT.id
  route_table_id = aws_route_table.public_rt.id 
}


# ==========================================
# NETWORK LOAD BALANCER (NLB) FOR HAPROXY
# ==========================================

resource "aws_lb" "haproxy_nlb" {
  name               = "patroni-haproxy-nlb"
  internal           = true   # Keep it secure inside the private VPC!
  load_balancer_type = "network"
  subnets            = [
    aws_subnet.primary.id,
    aws_subnet.replica_1.id,
    aws_subnet.replica_2.id
  ]

  enable_cross_zone_load_balancing = true
  tags = { Name = "Patroni_HAProxy_NLB" }
}

# --- TARGET GROUPS ---

# 1. Target Group for Primary (Write) Traffic
resource "aws_lb_target_group" "tg_primary" {
  name     = "haproxy-primary-tg"
  port     = 5000
  protocol = "TCP"
  vpc_id   = aws_vpc.vpc_lab.id

  # Simple TCP health check to ensure HAProxy is running on the node
  health_check {
    protocol = "TCP"
    port     = "5000"
    interval = 10
  }
}

# 2. Target Group for Replica (Read) Traffic
resource "aws_lb_target_group" "tg_replicas" {
  name     = "haproxy-replicas-tg"
  port     = 5001
  protocol = "TCP"
  vpc_id   = aws_vpc.vpc_lab.id

  health_check {
    protocol = "TCP"
    port     = "5001"
    interval = 10
  }
}

# --- LISTENERS ---

# Listen on 5000 and send to Primary Target Group
resource "aws_lb_listener" "listener_primary" {
  load_balancer_arn = aws_lb.haproxy_nlb.arn
  port              = 5000
  protocol          = "TCP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg_primary.arn
  }
}

# Listen on 5001 and send to Replica Target Group
resource "aws_lb_listener" "listener_replicas" {
  load_balancer_arn = aws_lb.haproxy_nlb.arn
  port              = 5001
  protocol          = "TCP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg_replicas.arn
  }
}

# --- ATTACH INSTANCES TO PRIMARY TARGET GROUP ---
resource "aws_lb_target_group_attachment" "primary_node1" {
  target_group_arn = aws_lb_target_group.tg_primary.arn
  target_id        = aws_instance.primary_db.id
}
resource "aws_lb_target_group_attachment" "primary_node2" {
  target_group_arn = aws_lb_target_group.tg_primary.arn
  target_id        = aws_instance.replica_1_db.id
}
resource "aws_lb_target_group_attachment" "primary_node3" {
  target_group_arn = aws_lb_target_group.tg_primary.arn
  target_id        = aws_instance.replica_2_db.id
}

# --- ATTACH INSTANCES TO REPLICA TARGET GROUP ---
resource "aws_lb_target_group_attachment" "replica_node1" {
  target_group_arn = aws_lb_target_group.tg_replicas.arn
  target_id        = aws_instance.primary_db.id
}
resource "aws_lb_target_group_attachment" "replica_node2" {
  target_group_arn = aws_lb_target_group.tg_replicas.arn
  target_id        = aws_instance.replica_1_db.id
}
resource "aws_lb_target_group_attachment" "replica_node3" {
  target_group_arn = aws_lb_target_group.tg_replicas.arn
  target_id        = aws_instance.replica_2_db.id
}

# --- OUTPUT THE DNS NAME ---
output "database_endpoint" {
  value       = aws_lb.haproxy_nlb.dns_name
  description = "The single DNS endpoint your applications will use to connect to the database."
}


# --- SECURITY GROUPS ---
resource "aws_security_group" "sg_ha_db_cluster" {
  name        = "ha-db-cluster-sg"
  description = "Unified Security Group for PostgreSQL HA Cluster (Patroni/etcd)"
  vpc_id      = aws_vpc.vpc_lab.id

  # ==========================================
  # PART 1: INTERNAL CLUSTER COMMUNICATION
  # (Nodes talking to each other)
  # ==========================================

  ingress {
    description = "Intra-cluster: PostgreSQL Replication"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    self        = true  # <--- The magic wand!
  }

  ingress {
    description = "Intra-cluster: etcd Leader Election & State"
    from_port   = 2379
    to_port     = 2380
    protocol    = "tcp"
    self        = true 
  }

  ingress {
    description = "Intra-cluster: Patroni API / Health Checks"
    from_port   = 8008
    to_port     = 8008
    protocol    = "tcp"
    self        = true 
  }

  # ==========================================
  # PART 2: EXTERNAL CLIENT COMMUNICATION
  # (Applications talking to the Database)
  # ==========================================

  ingress {
    description = "Client Access: Apps connecting to Haproxy"
    from_port   = 5000
    to_port     = 5001
    protocol    = "tcp"
    # Allow other servers in the VPC (like web servers) to query the DB
    cidr_blocks = ["10.10.0.0/16"] 
  }

  # (Optional) If you have a Load Balancer checking Patroni health from outside the cluster
  # ingress {
  #   description = "Load Balancer Health Checks to Patroni"
  #   from_port   = 8008
  #   to_port     = 8008
  #   protocol    = "tcp"
  #   cidr_blocks = ["10.10.0.0/16"] 
  # }

  # ==========================================
  # PART 3: OUTBOUND TRAFFIC
  # ==========================================
  egress {
    description = "Allow all outbound traffic (to NAT Gateway / SSM)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- INSTANCES ---
data "aws_ami" "ubuntu" {
  most_recent = true
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-resolute-26.04-amd64-server-*"]
  }
  owners = ["099720109477"] 
}

resource "aws_instance" "primary_db" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.primary.id
  iam_instance_profile   = aws_iam_instance_profile.ec2_ssm_profile.name
  vpc_security_group_ids = [aws_security_group.sg_ha_db_cluster.id]
  user_data = <<-EOF
              #!/bin/bash
              # Create a dedicated entry for ssm-user automation
              echo "ssm-user ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/99-ansible-ssm
              
              # Set strict file permissions required by sudo
              chmod 0440 /etc/sudoers.d/99-ansible-ssm
              EOF
  
 
  
  # FIX: Removed associate_public_ip_address = true. It doesn't work behind a NAT anyway!

  tags = { 
           Name = "node1"
           Project = "Patroni"
           Role = "etcd"
           EtcdName = "etcd-1"		  
   }
}

resource "aws_instance" "replica_1_db" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.replica_1.id
  iam_instance_profile   = aws_iam_instance_profile.ec2_ssm_profile.name
  vpc_security_group_ids = [aws_security_group.sg_ha_db_cluster.id]
  user_data = <<-EOF
              #!/bin/bash
              # Create a dedicated entry for ssm-user automation
              echo "ssm-user ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/99-ansible-ssm
              
              # Set strict file permissions required by sudo
              chmod 0440 /etc/sudoers.d/99-ansible-ssm
              EOF
  
  
  tags = { 
           Name = "node2"
           Project = "Patroni"
           Role = "etcd"
           EtcdName = "etcd-2"		  
   }
}

resource "aws_instance" "replica_2_db" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.replica_2.id
  iam_instance_profile   = aws_iam_instance_profile.ec2_ssm_profile.name
  vpc_security_group_ids = [aws_security_group.sg_ha_db_cluster.id]
  user_data = <<-EOF
              #!/bin/bash
              # Create a dedicated entry for ssm-user automation
              echo "ssm-user ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/99-ansible-ssm
              
              # Set strict file permissions required by sudo
              chmod 0440 /etc/sudoers.d/99-ansible-ssm
              EOF
  
  
  tags = { 
           Name = "node3"
           Project = "Patroni"
           Role = "etcd"
           EtcdName = "etcd-3"		  
   }
}


#Create a Role assumed by ec2
resource "aws_iam_role" "ec2_ssm_role" {
  name = "ec2-ssm-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

# IAM POLICY ATTACHMENT: Attach the AWS-managed SSM policy to the role
resource "aws_iam_role_policy_attachment" "ssm_policy_attach" {
  role       = aws_iam_role.ec2_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}



#INSTANCE PROFILE: Required to attach the IAM role to an EC2 instance
resource "aws_iam_instance_profile" "ec2_ssm_profile" {
  name = "ec2-ssm-instance-profile"
  role = aws_iam_role.ec2_ssm_role.name
}



#Ansible
#-----------------------------------------------


# Create a random suffix so the bucket name is globally unique
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# Create the S3 bucket for Ansible SSM payload transfers
resource "aws_s3_bucket" "ansible_ssm_bucket" {
  bucket        = "ansible-ssm-transfer-${random_id.bucket_suffix.hex}"
  force_destroy = true
}

# Output the bucket name so you can copy it easily!
output "ansible_ssm_bucket_name" {
  value = aws_s3_bucket.ansible_ssm_bucket.bucket
}


# Let Terraform automatically write your Ansible group_vars file!
resource "local_file" "ansible_group_vars" {
  filename = abspath("${path.module}/../ansible/group_vars/all.yml")
  content  = <<-EOF
---
# This file is dynamically generated by Terraform! Do not edit manually.
ansible_connection: aws_ssm
ansible_aws_ssm_region: "${data.aws_region.current.region}"
ansible_aws_ssm_bucket_name: "${aws_s3_bucket.ansible_ssm_bucket.bucket}"
patroni_aws_secret_name: "${aws_secretsmanager_secret.patroni_secrets.name}"
EOF
}





