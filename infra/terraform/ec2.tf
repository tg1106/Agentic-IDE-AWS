# ── Latest Ubuntu 22.04 LTS AMI (Deep Learning Base, us/ap regions) ───────
# The Deep Learning Base AMI ships with NVIDIA drivers + CUDA pre-installed,
# saving ~15 min of setup time on a fresh g4dn instance.
data "aws_ami" "dlami" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["Deep Learning Base OSS Nvidia Driver GPU AMI (Ubuntu 22.04)*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# ── IAM role for EC2 ──────────────────────────────────────────────────────
resource "aws_iam_role" "ec2" {
  name = "${var.project}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "${var.project}-ec2-role" }
}

# S3 access: read + write to the workspace bucket only
resource "aws_iam_role_policy" "s3" {
  name = "${var.project}-s3-policy"
  role = aws_iam_role.ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket",
      ]
      Resource = [
        aws_s3_bucket.workspace.arn,
        "${aws_s3_bucket.workspace.arn}/*",
      ]
    }]
  })
}

# Secrets Manager: read the IDE secrets bundle
resource "aws_iam_role_policy" "secrets" {
  name = "${var.project}-secrets-policy"
  role = aws_iam_role.ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = aws_secretsmanager_secret.ide_secrets.arn
    }]
  })
}

# SSM: allows Session Manager access (optional, handy for debugging)
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${var.project}-ec2-profile"
  role = aws_iam_role.ec2.name
}

# ── EC2 instance ──────────────────────────────────────────────────────────
resource "aws_instance" "ide" {
  ami                    = data.aws_ami.dlami.id
  instance_type          = var.ec2_instance_type
  key_name               = var.key_pair_name
  subnet_id              = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.ec2.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2.name

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.ec2_root_volume_gb
    delete_on_termination = true
    encrypted             = true
  }

  # Cloud-init bootstrap: installs dependencies, clones the repo, builds the
  # frontend, starts vLLM + the IDE server as systemd services.
  user_data = base64encode(templatefile("${path.module}/user_data.sh.tpl", {
    secret_arn   = aws_secretsmanager_secret.ide_secrets.arn
    aws_region   = var.aws_region
    llm_model    = var.llm_model
    idle_minutes = var.idle_minutes
    s3_bucket    = aws_s3_bucket.workspace.bucket
    db_host      = aws_db_instance.main.address
    db_port      = aws_db_instance.main.port
    db_name      = var.db_name
  }))

  tags = { Name = "${var.project}-ide" }

  # Wait for the database to be available before the instance boots and tries to connect.
  depends_on = [aws_db_instance.main]
}
