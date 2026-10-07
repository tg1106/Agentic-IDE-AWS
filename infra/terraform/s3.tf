# ── Workspace S3 bucket ───────────────────────────────────────────────────
resource "aws_s3_bucket" "workspace" {
  bucket        = var.s3_bucket_name
  force_destroy = true   # allows `terraform destroy` to delete non-empty bucket

  tags = { Name = var.s3_bucket_name, Purpose = "agentic-ide-workspace" }
}

# Block all public access — files are accessed only by the EC2 IAM role
resource "aws_s3_bucket_public_access_block" "workspace" {
  bucket                  = aws_s3_bucket.workspace.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Versioning: keeps previous versions of workspace files (disaster recovery)
resource "aws_s3_bucket_versioning" "workspace" {
  bucket = aws_s3_bucket.workspace.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Server-side encryption with AWS-managed keys
resource "aws_s3_bucket_server_side_encryption_configuration" "workspace" {
  bucket = aws_s3_bucket.workspace.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
  }
}

# Lifecycle: move non-current versions to Glacier after 30 days,
# expire them after 90 days — keeps costs low on a student account.
resource "aws_s3_bucket_lifecycle_configuration" "workspace" {
  bucket = aws_s3_bucket.workspace.id

  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    filter {}   # apply to all objects in the bucket

    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "GLACIER"
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}
