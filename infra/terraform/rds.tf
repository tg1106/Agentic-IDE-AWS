# ── RDS PostgreSQL ────────────────────────────────────────────────────────
# Lives in the private subnets and accepts connections only from the EC2
# security group. The Free plan only allows Aurora via "express configuration"
# (no VPC, IAM-token auth), which does not fit this VPC design, so the prototype
# uses single-AZ RDS PostgreSQL. The production target in the report is Aurora
# Serverless v2 (Multi-AZ, 7-day PITR, cross-region replica).
resource "aws_db_instance" "main" {
  identifier        = "${var.project}-postgres"
  engine            = "postgres"   # engine_version not pinned: AWS uses its current default
  instance_class    = "db.t4g.micro"
  allocated_storage = 20           # GB
  storage_encrypted = true

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.aurora.id]
  publicly_accessible    = false
  multi_az               = false   # single AZ on the Free plan; Multi-AZ in production

  # Automated backups with point-in-time recovery. The Free plan caps retention
  # at 1 day; raise to 7 after upgrading the plan.
  backup_retention_period = 1
  backup_window           = "02:00-03:00"   # UTC, off-peak for ap-southeast-2

  auto_minor_version_upgrade = true

  # Easy teardown during development
  skip_final_snapshot = true
  deletion_protection = false
  apply_immediately   = true

  lifecycle {
    ignore_changes = [engine_version]   # AWS applies minor upgrades on its own
  }

  tags = { Name = "${var.project}-postgres" }
}
