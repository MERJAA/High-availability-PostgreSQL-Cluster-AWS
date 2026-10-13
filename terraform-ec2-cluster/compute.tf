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