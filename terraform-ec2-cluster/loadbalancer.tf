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