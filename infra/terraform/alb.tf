# ── Application Load Balancer ─────────────────────────────────────────────
resource "aws_lb" "main" {
  name               = "${var.project}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  # Access logs can be enabled here by pointing at an S3 bucket.
  # Omitted for cost reasons on a student account.
  enable_deletion_protection = false

  tags = { Name = "${var.project}-alb" }
}

# ── Target group (EC2 port 8080) ──────────────────────────────────────────
resource "aws_lb_target_group" "ide" {
  name        = "${var.project}-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"

  health_check {
    path                = "/api/files"
    protocol            = "HTTP"
    matcher             = "200,401"   # 401 is fine — auth is required
    interval            = 30
    timeout             = 10
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = { Name = "${var.project}-tg" }
}

# ── Register EC2 instance with the target group ───────────────────────────
resource "aws_lb_target_group_attachment" "ide" {
  target_group_arn = aws_lb_target_group.ide.arn
  target_id        = aws_instance.ide.id
  port             = 8080
}

# ── HTTP listener on port 80 ──────────────────────────────────────────────
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ide.arn
  }
}
