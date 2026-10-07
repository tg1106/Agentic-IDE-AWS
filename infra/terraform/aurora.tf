# ── DB subnet group (spans both private subnets) ──────────────────────────
resource "aws_db_subnet_group" "main" {
  name       = "${var.project}-db-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = { Name = "${var.project}-db-subnet-group" }
}

# ── Aurora Serverless v2 PostgreSQL cluster ───────────────────────────────
# Serverless v2 scales ACUs between 0.5 and 4 — cheap for a student demo
# while showing real Aurora Serverless capability.
resource "aws_rds_cluster" "main" {
  cluster_identifier      = "${var.project}-aurora"
  engine                  = "aurora-postgresql"
  engine_mode             = "provisioned"   # required for Serverless v2
  engine_version          = "15.4"
  database_name           = var.db_name
  master_username         = var.db_username
  master_password         = var.db_password
  db_subnet_group_name    = aws_db_subnet_group.main.name
  vpc_security_group_ids  = [aws_security_group.aurora.id]

  # Serverless v2 scaling configuration
  serverlessv2_scaling_configuration {
    min_capacity = 0.5
    max_capacity = 4.0
  }

  # Automated backups: 7-day retention for disaster recovery
  backup_retention_period = 7
  preferred_backup_window = "02:00-03:00"   # 2–3 AM UTC (off-peak for ap-southeast-2)

  # Encrypt at rest with AWS-managed KMS key
  storage_encrypted = true

  # Allow destroying from Terraform during development
  skip_final_snapshot       = true
  deletion_protection       = false

  tags = { Name = "${var.project}-aurora" }
}

# ── One Serverless v2 instance (writer) ───────────────────────────────────
resource "aws_rds_cluster_instance" "main" {
  identifier         = "${var.project}-aurora-writer"
  cluster_identifier = aws_rds_cluster.main.id
  instance_class     = "db.serverless"
  engine             = aws_rds_cluster.main.engine
  engine_version     = aws_rds_cluster.main.engine_version

  tags = { Name = "${var.project}-aurora-writer" }
}
