provider "aws" {
  region = "us-east-1"
}

data "aws_region" "current" {}

variable "instance_type" {
  default = "t3.micro"
}

# --- VPC & SUBNETS ---
resource "aws_vpc" "vpc_lab" {
  cidr_block           = "10.10.0.0/16"
  enable_dns_hostnames = true 
  tags = { Name = "vpc_lab" }
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
EOF
}

