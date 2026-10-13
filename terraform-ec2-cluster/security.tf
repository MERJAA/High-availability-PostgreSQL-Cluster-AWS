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



#---------------------------------------




# Create a Role assumed by ec2

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
