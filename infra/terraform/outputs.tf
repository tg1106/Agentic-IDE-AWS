# ── Access ────────────────────────────────────────────────────────────────
output "app_url" {
  description = "Public URL of the Agentic IDE (via ALB)."
  value       = "http://${aws_lb.main.dns_name}"
}

output "alb_dns_name" {
  description = "Raw ALB DNS name."
  value       = aws_lb.main.dns_name
}

output "ec2_public_ip" {
  description = "EC2 public IP — use for SSH access."
  value       = aws_instance.ide.public_ip
}

output "ec2_ssh_command" {
  description = "SSH command to log into the instance."
  value       = "ssh -i <your-key>.pem ubuntu@${aws_instance.ide.public_ip}"
}

# ── Storage ───────────────────────────────────────────────────────────────
output "s3_bucket" {
  description = "S3 bucket storing workspace files."
  value       = aws_s3_bucket.workspace.bucket
}

# ── Database ──────────────────────────────────────────────────────────────
output "aurora_endpoint" {
  description = "RDS PostgreSQL instance endpoint."
  value       = aws_db_instance.main.address
}

output "aurora_port" {
  description = "RDS PostgreSQL port."
  value       = aws_db_instance.main.port
}

# ── Secrets ───────────────────────────────────────────────────────────────
output "secrets_manager_arn" {
  description = "ARN of the Secrets Manager secret holding all credentials."
  value       = aws_secretsmanager_secret.ide_secrets.arn
}

# ── WAF ───────────────────────────────────────────────────────────────────
output "waf_web_acl_arn" {
  description = "WAFv2 WebACL ARN associated with the ALB."
  value       = aws_wafv2_web_acl.main.arn
}
