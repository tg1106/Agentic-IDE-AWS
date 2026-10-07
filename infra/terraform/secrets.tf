# ── Secrets Manager: single secret bundle ────────────────────────────────
# Stores all sensitive values in one JSON secret.
# The EC2 IAM role has GetSecretValue permission; user_data.sh fetches it
# at boot time and writes a .env file (chmod 600, owned by ubuntu).
resource "aws_secretsmanager_secret" "ide_secrets" {
  name                    = "${var.project}/credentials"
  description             = "Agentic IDE credentials: IDE auth, DB password"
  recovery_window_in_days = 0   # immediate deletion allowed (dev/student account)

  tags = { Name = "${var.project}-secrets" }
}

resource "aws_secretsmanager_secret_version" "ide_secrets" {
  secret_id = aws_secretsmanager_secret.ide_secrets.id

  secret_string = jsonencode({
    ide_user    = var.ide_user
    ide_pass    = var.ide_pass
    db_password = var.db_password
  })
}
