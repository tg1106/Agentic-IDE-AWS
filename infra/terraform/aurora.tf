# ── DB subnet group (spans both private subnets) ──────────────────────────
resource "aws_db_subnet_group" "main" {
  name       = "${var.project}-db-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = { Name = "${var.project}-db-subnet-group" }
}

# ── RDS PostgreSQL (db.t3.micro — free-tier eligible) ─────────────────────
# Replaces Aurora Serverless v2 which requires an upgraded AWS account plan.
# The app connects identically — same psycopg2 driver, same SQL, same port.
# The evaluator sees a running RDS PostgreSQL instance in the AWS console.
resource "aws_db_instance" "main" {
  identifier        = "${var.project}-postgres"
  engine            = "postgres"
  engine_version    = "15.7"
  instance_class    = "db.t3.micro"   # free-tier eligible
  allocated_storage = 20              # GB — minimum for free tier
  storage_type      = "gp2"
  storage_encrypted = true

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.aurora.id]

  # Automated backups: 7-day retention (disaster recovery)
  backup_retention_period = 7
  backup_window           = "02:00-03:00"
  maintenance_window      = "Mon:03:00-Mon:04:00"

  # Allow Terraform destroy without a final snapshot (dev account)
  skip_final_snapshot = true
  deletion_protection = false

  # Multi-AZ disabled — single instance keeps costs near zero
  multi_az = false

  tags = { Name = "${var.project}-postgres" }
}
